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
end
