# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Budget AS::Notifications" do
  let(:agent_class) do
    Class.new do
      def self.name
        "BudgetTestAgent"
      end

      def self.agent_type
        :conversation
      end

      def self.model
        "gpt-4o-mini"
      end
    end
  end

  let(:cache_store) { ActiveSupport::Cache::MemoryStore.new }

  before do
    RubyLLM::Agents.reset_configuration!
    RubyLLM::Agents.configure do |c|
      c.cache_store = cache_store
      c.budgets = {
        enforcement: :hard,
        global_daily: 100.0,
        global_monthly: 1000.0
      }
    end
  end

  after do
    RubyLLM::Agents.reset_configuration!
  end

  def build_context(**overrides)
    RubyLLM::Agents::Pipeline::Context.new(
      input: "test input",
      agent_class: agent_class,
      **overrides
    )
  end

  def build_budget_middleware(app_lambda)
    RubyLLM::Agents::Pipeline::Middleware::Budget.new(app_lambda, agent_class)
  end

  def collect_events(event_name)
    events = []
    sub = ActiveSupport::Notifications.subscribe(event_name) do |*args|
      events << ActiveSupport::Notifications::Event.new(*args)
    end
    yield
    events
  ensure
    ActiveSupport::Notifications.unsubscribe(sub)
  end

  describe "budget.check event" do
    it "emits ruby_llm_agents.budget.check before execution" do
      app = ->(ctx) {
        ctx.output = RubyLLM::Agents::Result.new(content: "done")
        ctx
      }
      middleware = build_budget_middleware(app)
      context = build_context

      events = collect_events("ruby_llm_agents.budget.check") do
        middleware.call(context)
      end

      expect(events.length).to eq(1)
      payload = events.first.payload
      expect(payload[:agent_type]).to eq("BudgetTestAgent")
      expect(payload[:tenant_id]).to be_nil
    end

    it "includes tenant_id when set" do
      app = ->(ctx) {
        ctx.output = RubyLLM::Agents::Result.new(content: "done")
        ctx
      }
      middleware = build_budget_middleware(app)
      context = build_context
      context.tenant_id = "org-123"

      events = collect_events("ruby_llm_agents.budget.check") do
        middleware.call(context)
      end

      expect(events.first.payload[:tenant_id]).to eq("org-123")
    end
  end

  describe "budget.record event" do
    it "emits ruby_llm_agents.budget.record after successful execution" do
      app = ->(ctx) {
        ctx.output = RubyLLM::Agents::Result.new(content: "done")
        ctx.total_cost = 0.005
        ctx.input_tokens = 100
        ctx.output_tokens = 50
        ctx
      }
      middleware = build_budget_middleware(app)
      context = build_context

      events = collect_events("ruby_llm_agents.budget.record") do
        middleware.call(context)
      end

      expect(events.length).to eq(1)
      payload = events.first.payload
      expect(payload[:agent_type]).to eq("BudgetTestAgent")
      expect(payload[:total_cost]).to eq(0.005)
      expect(payload[:total_tokens]).to eq(150)
    end

    it "does not emit budget.record for cached results" do
      app = ->(ctx) {
        ctx.output = RubyLLM::Agents::Result.new(content: "cached")
        ctx.cached = true
        ctx.total_cost = 0.0
        ctx
      }
      middleware = build_budget_middleware(app)
      context = build_context

      events = collect_events("ruby_llm_agents.budget.record") do
        middleware.call(context)
      end

      expect(events).to be_empty
    end
  end

  describe "budget.exceeded event" do
    it "emits ruby_llm_agents.budget.exceeded when budget is exceeded" do
      # Set budget to 0 so any existing spend (even 0.0 >= 0.0) triggers exceeded
      RubyLLM::Agents.configure do |c|
        c.budgets = {
          enforcement: :hard,
          global_daily: 0.0
        }
      end

      app = ->(ctx) {
        ctx.output = RubyLLM::Agents::Result.new(content: "done")
        ctx
      }
      middleware = build_budget_middleware(app)
      context = build_context

      events = collect_events("ruby_llm_agents.budget.exceeded") do
        middleware.call(context)
      rescue
        nil
      end

      expect(events.length).to eq(1)
      payload = events.first.payload
      expect(payload[:agent_type]).to eq("BudgetTestAgent")
    end
  end

  describe "when budgets are disabled" do
    it "does not emit any budget events" do
      RubyLLM::Agents.configure do |c|
        c.budgets = nil
      end

      app = ->(ctx) {
        ctx.output = RubyLLM::Agents::Result.new(content: "done")
        ctx
      }
      middleware = build_budget_middleware(app)

      all_events = []
      sub = ActiveSupport::Notifications.subscribe(/ruby_llm_agents\.budget\./) do |*args|
        all_events << ActiveSupport::Notifications::Event.new(*args)
      end

      middleware.call(build_context)

      ActiveSupport::Notifications.unsubscribe(sub)
      expect(all_events).to be_empty
    end
  end
end
