# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Reliability AS::Notifications" do
  let(:agent_class) do
    Class.new(RubyLLM::Agents::BaseAgent) do
      def self.name
        "ReliabilityNotifAgent"
      end

      model "gpt-4o"
      param :query, required: true

      reliability do
        retries max: 1, backoff: :constant
        fallback_models "gpt-4o-mini"
      end

      def user_prompt
        query
      end
    end
  end

  before do
    RubyLLM::Agents.reset_configuration!
    RubyLLM::Agents.configure do |c|
      c.track_executions = false
      c.async_logging = false
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

  def build_reliability_middleware(app_lambda)
    RubyLLM::Agents::Pipeline::Middleware::Reliability.new(app_lambda, agent_class)
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

  describe "reliability.fallback_used event" do
    it "emits when a fallback model succeeds" do
      call_count = 0
      app = ->(ctx) {
        call_count += 1
        if ctx.model == "gpt-4o"
          raise "primary model failed"
        end
        # Fallback model succeeds
        ctx.output = RubyLLM::Agents::Result.new(content: "fallback worked")
        ctx
      }
      middleware = build_reliability_middleware(app)
      context = build_context

      events = collect_events("ruby_llm_agents.reliability.fallback_used") do
        middleware.call(context)
      end

      expect(events.length).to eq(1)
      payload = events.first.payload
      expect(payload[:agent_type]).to eq("ReliabilityNotifAgent")
      expect(payload[:primary_model]).to eq("gpt-4o")
      expect(payload[:used_model]).to eq("gpt-4o-mini")
      expect(payload[:attempts_made]).to be >= 2
    end
  end

  describe "reliability.all_models_exhausted event" do
    it "emits when all models fail" do
      app = ->(_ctx) {
        raise "model failed"
      }
      middleware = build_reliability_middleware(app)
      context = build_context

      events = collect_events("ruby_llm_agents.reliability.all_models_exhausted") do
        middleware.call(context)
      rescue
        nil
      end

      expect(events.length).to eq(1)
      payload = events.first.payload
      expect(payload[:agent_type]).to eq("ReliabilityNotifAgent")
      expect(payload[:models_tried]).to include("gpt-4o", "gpt-4o-mini")
    end

    it "still raises AllModelsExhaustedError after emitting" do
      app = ->(_ctx) { raise "fail" }
      middleware = build_reliability_middleware(app)
      context = build_context

      expect {
        middleware.call(context)
      }.to raise_error(RubyLLM::Agents::Reliability::AllModelsExhaustedError)
    end
  end

  describe "when reliability is not configured" do
    let(:no_reliability_agent) do
      Class.new(RubyLLM::Agents::BaseAgent) do
        def self.name
          "NoReliabilityAgent"
        end

        model "gpt-4o"
        param :query, required: true

        def user_prompt
          query
        end
      end
    end

    it "does not emit any reliability events" do
      app = ->(ctx) {
        ctx.output = RubyLLM::Agents::Result.new(content: "done")
        ctx
      }
      middleware = RubyLLM::Agents::Pipeline::Middleware::Reliability.new(app, no_reliability_agent)

      all_events = []
      sub = ActiveSupport::Notifications.subscribe(/ruby_llm_agents\.reliability\./) do |*args|
        all_events << ActiveSupport::Notifications::Event.new(*args)
      end

      middleware.call(build_context)

      ActiveSupport::Notifications.unsubscribe(sub)
      expect(all_events).to be_empty
    end
  end
end
