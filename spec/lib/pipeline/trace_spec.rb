# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Pipeline Debug Trace" do
  let(:agent_class) do
    Class.new(RubyLLM::Agents::BaseAgent) do
      def self.name
        "TraceTestAgent"
      end

      model "test-model"

      def self.agent_type
        :conversation
      end

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

  describe "Pipeline::Context trace" do
    it "is disabled by default" do
      context = RubyLLM::Agents::Pipeline::Context.new(
        input: "test",
        agent_class: agent_class
      )

      expect(context.trace_enabled?).to be false
      expect(context.trace).to eq([])
    end

    it "is enabled when debug: true is passed" do
      context = RubyLLM::Agents::Pipeline::Context.new(
        input: "test",
        agent_class: agent_class,
        debug: true
      )

      expect(context.trace_enabled?).to be true
    end

    it "accumulates trace entries" do
      context = RubyLLM::Agents::Pipeline::Context.new(
        input: "test",
        agent_class: agent_class,
        debug: true
      )

      context.add_trace("TestMiddleware", started_at: Time.current, duration_ms: 1.5, action: "test")
      context.add_trace("AnotherMiddleware", started_at: Time.current, duration_ms: 0.3)

      expect(context.trace.size).to eq(2)
      expect(context.trace.first[:middleware]).to eq("TestMiddleware")
      expect(context.trace.first[:duration_ms]).to eq(1.5)
      expect(context.trace.first[:action]).to eq("test")
      expect(context.trace.last[:middleware]).to eq("AnotherMiddleware")
      expect(context.trace.last[:action]).to be_nil
    end
  end

  describe "Middleware::Base#trace" do
    let(:app) {
      proc { |ctx|
        ctx.output = "result"
        ctx
      }
    }

    it "adds no trace entry when tracing is disabled" do
      context = RubyLLM::Agents::Pipeline::Context.new(
        input: "test",
        agent_class: agent_class
      )

      middleware = RubyLLM::Agents::Pipeline::Middleware::Instrumentation.new(app, agent_class)
      middleware.call(context)

      expect(context.trace).to eq([])
    end

    it "adds trace entries when tracing is enabled" do
      context = RubyLLM::Agents::Pipeline::Context.new(
        input: "test",
        agent_class: agent_class,
        debug: true
      )

      middleware = RubyLLM::Agents::Pipeline::Middleware::Instrumentation.new(app, agent_class)
      middleware.call(context)

      expect(context.trace).not_to be_empty
      expect(context.trace.first[:middleware]).to eq("Instrumentation")
      expect(context.trace.first[:duration_ms]).to be_a(Numeric)
    end
  end
end
