# frozen_string_literal: true

require "rails_helper"

# The response cache used to key only on [agent_type, class, model, user_prompt].
# Everything else that changes the response was invisible to it: a different
# image attachment on the same text prompt returned the wrong cached result, an
# edited system prompt served stale answers for the whole TTL, and the entry was
# shared across tenants.
RSpec.describe "response cache key isolation" do
  let(:agent_class) do
    Class.new do
      def self.name = "CacheKeyAgent"

      def self.agent_type = :conversation

      def self.model = "gpt-4.1"

      def self.cache_enabled? = true

      def self.cache_ttl = 3600
    end
  end

  let(:cache_store) { ActiveSupport::Cache::MemoryStore.new }

  before do
    RubyLLM::Agents.reset_configuration!
    RubyLLM::Agents.configure { |c| c.cache_store = cache_store }
  end

  after { RubyLLM::Agents.reset_configuration! }

  def key_for(input: "same prompt", tenant_id: nil, **exec_options)
    context = RubyLLM::Agents::Pipeline::Context.new(
      input: input, agent_class: agent_class, model: "gpt-4.1",
      options: exec_options
    )
    context.tenant_id = tenant_id

    middleware = RubyLLM::Agents::Pipeline::Middleware::Cache.new(->(ctx) { ctx }, agent_class)
    middleware.send(:generate_cache_key, context)
  end

  it "separates identical prompts carrying different attachments" do
    expect(key_for(attachments: "invoice-jan.png"))
      .not_to eq(key_for(attachments: "invoice-feb.png"))
  end

  it "separates tenants" do
    expect(key_for(tenant_id: "acme")).not_to eq(key_for(tenant_id: "globex"))
  end

  it "does not serve a tenant's entry to an untenanted call" do
    expect(key_for(tenant_id: "acme")).not_to eq(key_for)
  end

  it "invalidates when the system prompt changes" do
    expect(key_for(system_prompt: "You are terse."))
      .not_to eq(key_for(system_prompt: "You are verbose."))
  end

  it "invalidates when the temperature changes" do
    expect(key_for(temperature: 0.0)).not_to eq(key_for(temperature: 1.0))
  end

  it "invalidates when the structured-output schema changes" do
    expect(key_for(schema: {type: "object", properties: {a: {type: "string"}}}))
      .not_to eq(key_for(schema: {type: "object", properties: {b: {type: "string"}}}))
  end

  it "invalidates when the assistant prefill changes" do
    expect(key_for(assistant_prefill: {role: :assistant, content: "{"}))
      .not_to eq(key_for(assistant_prefill: {role: :assistant, content: "["}))
  end

  it "invalidates when the tool set changes" do
    tool_a = Class.new { def self.name = "SearchTool" }
    tool_b = Class.new { def self.name = "CalculatorTool" }

    expect(key_for(tools: [tool_a])).not_to eq(key_for(tools: [tool_b]))
  end

  it "invalidates when thinking configuration changes" do
    expect(key_for(thinking: {effort: "low"})).not_to eq(key_for(thinking: {effort: "high"}))
  end

  it "still returns the same key for genuinely identical calls" do
    opts = {system_prompt: "You are terse.", temperature: 0.2, attachments: "a.png"}

    expect(key_for(tenant_id: "acme", **opts)).to eq(key_for(tenant_id: "acme", **opts))
  end

  it "ignores options that cannot change the response" do
    expect(key_for(timeout: 30)).to eq(key_for(timeout: 120))
  end

  it "survives an unserializable attachment rather than raising" do
    file = Tempfile.new("cache-key")

    expect { key_for(attachments: file) }.not_to raise_error
  ensure
    file&.close!
  end
end
