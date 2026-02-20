# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Instrumentation AS::Notifications" do
  let(:agent_class) do
    Class.new(RubyLLM::Agents::BaseAgent) do
      def self.name
        "NotificationTestAgent"
      end

      model "gpt-4o-mini"
      param :query, required: true

      def user_prompt
        query
      end
    end
  end

  before do
    RubyLLM::Agents.reset_configuration!
    RubyLLM::Agents.configure do |c|
      c.track_executions = true
      c.async_logging = false
      c.persist_prompts = false
      c.persist_responses = false
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

  def build_instrumentation(app_lambda)
    RubyLLM::Agents::Pipeline::Middleware::Instrumentation.new(app_lambda, agent_class)
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

  describe "execution.start event" do
    it "emits ruby_llm_agents.execution.start before execution" do
      app = ->(ctx) {
        ctx.output = RubyLLM::Agents::Result.new(content: "done")
        ctx
      }
      middleware = build_instrumentation(app)
      context = build_context

      events = collect_events("ruby_llm_agents.execution.start") do
        middleware.call(context)
      end

      expect(events.length).to eq(1)
      payload = events.first.payload
      expect(payload[:agent_type]).to eq("NotificationTestAgent")
      expect(payload[:model]).to eq("gpt-4o-mini")
      expect(payload[:execution_id]).to be_present
    end

    it "includes tenant_id in start payload when set" do
      app = ->(ctx) {
        ctx.output = RubyLLM::Agents::Result.new(content: "done")
        ctx
      }
      middleware = build_instrumentation(app)
      context = build_context
      context.tenant_id = "tenant-abc"

      events = collect_events("ruby_llm_agents.execution.start") do
        middleware.call(context)
      end

      expect(events.first.payload[:tenant_id]).to eq("tenant-abc")
    end
  end

  describe "execution.complete event" do
    it "emits ruby_llm_agents.execution.complete on success" do
      app = ->(ctx) {
        ctx.output = RubyLLM::Agents::Result.new(content: "done")
        ctx.input_tokens = 100
        ctx.output_tokens = 50
        ctx.total_cost = 0.001
        ctx
      }
      middleware = build_instrumentation(app)
      context = build_context

      events = collect_events("ruby_llm_agents.execution.complete") do
        middleware.call(context)
      end

      expect(events.length).to eq(1)
      payload = events.first.payload
      expect(payload[:status]).to eq("success")
      expect(payload[:agent_type]).to eq("NotificationTestAgent")
      expect(payload[:model]).to eq("gpt-4o-mini")
      expect(payload[:input_tokens]).to eq(100)
      expect(payload[:output_tokens]).to eq(50)
      expect(payload[:total_tokens]).to eq(150)
      expect(payload[:total_cost]).to eq(0.001)
      expect(payload[:duration_ms]).to be_a(Integer)
      expect(payload[:execution_id]).to be_present
      expect(payload[:error_class]).to be_nil
      expect(payload[:error_message]).to be_nil
    end

    it "includes all context fields in complete payload" do
      app = ->(ctx) {
        ctx.output = RubyLLM::Agents::Result.new(content: "done")
        ctx.input_tokens = 200
        ctx.output_tokens = 100
        ctx.input_cost = 0.002
        ctx.output_cost = 0.001
        ctx.total_cost = 0.003
        ctx.model_used = "gpt-4o-mini"
        ctx.finish_reason = "stop"
        ctx.time_to_first_token_ms = 234
        ctx.attempts_made = 2
        ctx
      }
      middleware = build_instrumentation(app)
      context = build_context

      events = collect_events("ruby_llm_agents.execution.complete") do
        middleware.call(context)
      end

      payload = events.first.payload
      expect(payload[:model_used]).to eq("gpt-4o-mini")
      expect(payload[:input_cost]).to eq(0.002)
      expect(payload[:output_cost]).to eq(0.001)
      expect(payload[:finish_reason]).to eq("stop")
      expect(payload[:time_to_first_token_ms]).to eq(234)
      expect(payload[:attempts_made]).to eq(2)
      expect(payload[:cached]).to eq(false)
    end
  end

  describe "execution.error event" do
    it "emits ruby_llm_agents.execution.error on failure" do
      app = ->(_ctx) { raise StandardError, "something broke" }
      middleware = build_instrumentation(app)
      context = build_context

      events = collect_events("ruby_llm_agents.execution.error") do
        middleware.call(context)
      rescue
        nil
      end

      expect(events.length).to eq(1)
      payload = events.first.payload
      expect(payload[:status]).to eq("error")
      expect(payload[:agent_type]).to eq("NotificationTestAgent")
      expect(payload[:error_class]).to eq("StandardError")
      expect(payload[:error_message]).to eq("something broke")
      expect(payload[:duration_ms]).to be_a(Integer)
    end

    it "emits execution.error with timeout status for Timeout::Error" do
      app = ->(_ctx) { raise Timeout::Error, "timed out" }
      middleware = build_instrumentation(app)
      context = build_context

      events = collect_events("ruby_llm_agents.execution.error") do
        middleware.call(context)
      rescue
        nil
      end

      expect(events.first.payload[:status]).to eq("timeout")
    end

    it "still raises the original exception after emitting" do
      app = ->(_ctx) { raise StandardError, "boom" }
      middleware = build_instrumentation(app)
      context = build_context

      expect {
        middleware.call(context)
      }.to raise_error(StandardError, "boom")
    end
  end

  describe "notification safety" do
    it "does not emit execution.complete when execution errors" do
      app = ->(_ctx) { raise StandardError, "fail" }
      middleware = build_instrumentation(app)
      context = build_context

      complete_events = collect_events("ruby_llm_agents.execution.complete") do
        middleware.call(context)
      rescue
        nil
      end

      expect(complete_events).to be_empty
    end

    it "emits both start and complete on success" do
      app = ->(ctx) {
        ctx.output = RubyLLM::Agents::Result.new(content: "ok")
        ctx
      }
      middleware = build_instrumentation(app)
      context = build_context

      start_events = []
      complete_events = []

      sub_start = ActiveSupport::Notifications.subscribe("ruby_llm_agents.execution.start") do |*args|
        start_events << ActiveSupport::Notifications::Event.new(*args)
      end
      sub_complete = ActiveSupport::Notifications.subscribe("ruby_llm_agents.execution.complete") do |*args|
        complete_events << ActiveSupport::Notifications::Event.new(*args)
      end

      middleware.call(context)

      ActiveSupport::Notifications.unsubscribe(sub_start)
      ActiveSupport::Notifications.unsubscribe(sub_complete)

      expect(start_events.length).to eq(1)
      expect(complete_events.length).to eq(1)
    end

    it "emits start and error on failure" do
      app = ->(_ctx) { raise StandardError, "fail" }
      middleware = build_instrumentation(app)
      context = build_context

      start_events = []
      error_events = []

      sub_start = ActiveSupport::Notifications.subscribe("ruby_llm_agents.execution.start") do |*args|
        start_events << ActiveSupport::Notifications::Event.new(*args)
      end
      sub_error = ActiveSupport::Notifications.subscribe("ruby_llm_agents.execution.error") do |*args|
        error_events << ActiveSupport::Notifications::Event.new(*args)
      end

      begin
        middleware.call(context)
      rescue
        nil
      end

      ActiveSupport::Notifications.unsubscribe(sub_start)
      ActiveSupport::Notifications.unsubscribe(sub_error)

      expect(start_events.length).to eq(1)
      expect(error_events.length).to eq(1)
    end
  end

  describe "notifications fire even when tracking is disabled" do
    it "still emits notifications when track_executions is false" do
      RubyLLM::Agents.configuration.track_executions = false

      app = ->(ctx) {
        ctx.output = RubyLLM::Agents::Result.new(content: "done")
        ctx
      }
      middleware = build_instrumentation(app)
      context = build_context

      events = collect_events("ruby_llm_agents.execution.complete") do
        middleware.call(context)
      end

      expect(events.length).to eq(1)
      expect(events.first.payload[:status]).to eq("success")
    end
  end
end
