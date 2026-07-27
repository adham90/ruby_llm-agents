# frozen_string_literal: true

require "rails_helper"

# The Reliability middleware records each failed attempt on context.error, and
# Context#success? requires that to be nil. Nothing used to clear it, so an
# execution that failed once and then succeeded stayed "failed" for every
# middleware outside Reliability: Budget skipped recording the spend (budget
# limits were bypassable by any agent that blipped), Cache skipped writing the
# result (cache_for silently stopped working), and the execution row was saved
# green but carrying an error_class.
RSpec.describe "recovered retry" do
  let(:tenant_id) { "recovered-retry-org" }

  before do
    RubyLLM::Agents.reset_configuration!
    RubyLLM::Agents.configure do |c|
      c.track_executions = true
      c.async_logging = false
      c.multi_tenancy_enabled = true
      c.budgets = {enforcement: :soft, global_daily: 1000.0}
      c.cache_store = ActiveSupport::Cache::MemoryStore.new
    end
  end

  after { RubyLLM::Agents.reset_configuration! }

  let(:agent_class) do
    Class.new(RubyLLM::Agents::Base) do
      def self.name = "RecoveredRetryAgent"

      model "gpt-4.1"
      prompt "say hi"
      cache_for 300
      on_failure { retries times: 2, backoff: :constant, base: 0.0 }
    end
  end

  let(:response) do
    RubyLLM::Message.new(role: :assistant, content: "hello",
      input_tokens: 100, output_tokens: 50, model_id: "gpt-4.1")
  end

  # Fails the first LLM call, succeeds on the retry.
  def stub_flaky_client!
    calls = 0
    client = double("RubyLLM::Chat")
    %i[with_temperature with_instructions with_schema with_tools with_thinking].each do |m|
      allow(client).to receive(m).and_return(client)
    end
    allow(client).to receive(:messages).and_return([])
    allow(client).to receive(:ask) do
      calls += 1
      raise Timeout::Error, "transient" if calls == 1
      response
    end
    allow(RubyLLM).to receive(:chat).and_return(client)
    allow_any_instance_of(RubyLLM::Agents::Pipeline::Middleware::Reliability)
      .to receive(:async_aware_sleep)
  end

  before { stub_flaky_client! }

  it "returns the successful result" do
    expect(agent_class.call(tenant: {id: tenant_id}).content).to eq("hello")
  end

  it "records the spend against the tenant's budget" do
    tenant = RubyLLM::Agents::Tenant.create!(tenant_id: tenant_id, name: "Recovered")

    agent_class.call(tenant: {id: tenant_id})

    tenant.reload
    expect(tenant.daily_executions_count).to eq(1)
    expect(tenant.daily_cost_spent.to_f).to be > 0
  end

  it "writes the result to the cache so the next identical call is a hit" do
    agent_class.call(tenant: {id: tenant_id})

    expect(RubyLLM::Agents::Execution.count).to eq(1)

    agent_class.call(tenant: {id: tenant_id})

    expect(RubyLLM::Agents::Execution.order(:id).last.cache_hit).to be true
  end

  it "does not stamp an error_class on the successful execution" do
    agent_class.call(tenant: {id: tenant_id})

    execution = RubyLLM::Agents::Execution.order(:id).first
    expect(execution.status).to eq("success")
    expect(execution.error_class).to be_nil
  end

  it "leaves the context in a successful state" do
    context = RubyLLM::Agents::Pipeline::Context.new(
      input: "x", agent_class: agent_class, model: "gpt-4.1"
    )
    calls = 0
    app = Object.new
    app.define_singleton_method(:call) do |ctx|
      calls += 1
      raise Timeout::Error, "transient" if calls == 1
      ctx.output = "recovered"
      ctx
    end
    middleware = RubyLLM::Agents::Pipeline::Middleware::Reliability.new(app, agent_class)
    allow(middleware).to receive(:async_aware_sleep)

    middleware.call(context)

    expect(context.success?).to be true
    expect(context.failed?).to be false
    expect(context.error).to be_nil
  end

  it "keeps the model that actually succeeded rather than reverting to the primary" do
    fallback_agent = Class.new(RubyLLM::Agents::Base) do
      def self.name = "RecoveredFallbackAgent"

      model "gpt-4.1"
      on_failure { fallback to: "gpt-4.1-mini" }
    end

    context = RubyLLM::Agents::Pipeline::Context.new(
      input: "x", agent_class: fallback_agent, model: "gpt-4.1"
    )
    app = Object.new
    app.define_singleton_method(:call) do |ctx|
      raise Timeout::Error, "primary down" if ctx.model == "gpt-4.1"
      ctx.output = "ok"
      ctx
    end
    middleware = RubyLLM::Agents::Pipeline::Middleware::Reliability.new(app, fallback_agent)
    allow(middleware).to receive(:async_aware_sleep)

    middleware.call(context)

    expect(context.model).to eq("gpt-4.1-mini")
  end

  it "still surfaces the error when every attempt fails" do
    client = double("RubyLLM::Chat")
    %i[with_temperature with_instructions with_schema with_tools with_thinking].each do |m|
      allow(client).to receive(m).and_return(client)
    end
    allow(client).to receive(:messages).and_return([])
    allow(client).to receive(:ask).and_raise(Timeout::Error, "always down")
    allow(RubyLLM).to receive(:chat).and_return(client)

    expect { agent_class.call(tenant: {id: tenant_id}) }
      .to raise_error(RubyLLM::Agents::Reliability::AllModelsExhaustedError)

    expect(RubyLLM::Agents::Execution.order(:id).last.error_class)
      .to eq("RubyLLM::Agents::Reliability::AllModelsExhaustedError")
  end
end
