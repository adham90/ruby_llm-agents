# frozen_string_literal: true

require "rails_helper"

RSpec.describe "LLM HTTP request capture", type: :model do
  let(:agent_class) do
    Class.new(RubyLLM::Agents::BaseAgent) do
      def self.name
        "RequestCaptureAgent"
      end

      model "gpt-4o-mini"
    end
  end

  before do
    RubyLLM::Agents.reset_configuration!
    RubyLLM::Agents.configure do |c|
      c.track_executions = true
      c.async_logging = false
    end
  end

  after do
    RubyLLM::Agents.reset_configuration!
  end

  def build_context
    RubyLLM::Agents::Pipeline::Context.new(input: "test", agent_class: agent_class)
  end

  def build_middleware(app)
    RubyLLM::Agents::Pipeline::Middleware::Instrumentation.new(app, agent_class)
  end

  def emit_request
    ActiveSupport::Notifications.instrument("request.ruby_llm", provider: "openai") { :ok }
  end

  it "records provider request timing and count from request.ruby_llm events" do
    app = lambda do |ctx|
      2.times { emit_request }
      ctx.output = RubyLLM::Agents::Result.new(content: "done")
      ctx.input_tokens = 100
      ctx.output_tokens = 50
      ctx
    end

    context = build_context
    build_middleware(app).call(context)

    execution = RubyLLM::Agents::Execution.find(context.execution_id)
    expect(execution.metadata["llm_request_count"]).to eq(2)
    expect(execution.metadata["llm_request_ms"]).to be >= 0
  end

  it "records nothing when no LLM HTTP requests fire" do
    app = lambda do |ctx|
      ctx.output = RubyLLM::Agents::Result.new(content: "done")
      ctx
    end

    context = build_context
    build_middleware(app).call(context)

    execution = RubyLLM::Agents::Execution.find(context.execution_id)
    expect(execution.metadata || {}).not_to have_key("llm_request_count")
  end

  it "still captures request timing when the downstream call raises" do
    app = lambda do |ctx|
      emit_request
      raise "boom"
    end

    context = build_context
    expect { build_middleware(app).call(context) }.to raise_error("boom")

    execution = RubyLLM::Agents::Execution.find(context.execution_id)
    expect(execution.metadata["llm_request_count"]).to eq(1)
  end

  describe "attribution scope (no cross-execution contamination)" do
    let(:middleware) { build_middleware(->(ctx) { ctx }) }

    it "attributes nested sub-agent requests to the innermost execution only" do
      outer = build_context
      inner = build_context

      middleware.send(:capture_llm_requests, outer) do
        emit_request # belongs to outer
        middleware.send(:capture_llm_requests, inner) do
          emit_request # belongs to inner, not outer
        end
        emit_request # belongs to outer again
      end

      expect(outer[:llm_request_count]).to eq(2)
      expect(inner[:llm_request_count]).to eq(1)
    end

    it "does not count request.ruby_llm events emitted on other threads" do
      other = build_context
      subscribed = Queue.new
      may_emit = Queue.new

      worker = Thread.new do
        middleware.send(:capture_llm_requests, other) do
          subscribed << true   # subscription is now active
          may_emit.pop         # wait until the main thread has emitted
        end
      end

      subscribed.pop
      # A different execution on the main thread fires its own LLM request.
      emit_request
      may_emit << true
      worker.join

      # `other` made no requests of its own, so a leaked global subscription
      # would wrongly attribute the main thread's request to it.
      expect(other[:llm_request_count]).to be_nil
    ensure
      may_emit << true # avoid hanging the worker if an assertion fails early
      worker&.join
    end
  end
end
