# frozen_string_literal: true

require "rails_helper"

# The Tenant middleware stored per-tenant provider keys in context[:tenant_api_keys],
# and Instrumentation copies the whole metadata bag onto the execution record —
# which executions/show renders as pretty-printed JSON with a copy button. Every
# execution for a tenant therefore wrote that tenant's live API key into the
# database in plaintext and displayed it to anyone with dashboard access.
RSpec.describe "tenant API key leak" do
  before do
    RubyLLM::Agents.reset_configuration!
    RubyLLM::Agents.configure do |c|
      c.track_executions = true
      c.async_logging = false
      c.multi_tenancy_enabled = true
    end
  end

  after { RubyLLM::Agents.reset_configuration! }

  let(:tenant_object) do
    Class.new do
      def self.name = "LeakOrg"

      def llm_tenant_id = "leak-org"

      def llm_api_keys = {openai: "sk-live-SUPERSECRET1234567890"}

      # Not an AR model, so the middleware takes the minimal-record path
      def is_a?(klass) = (klass == ::ActiveRecord::Base) ? false : super
    end.new
  end

  let(:agent_class) do
    Class.new(RubyLLM::Agents::Base) do
      def self.name = "LeakAgent"

      model "gpt-4.1"
      prompt "hi"
    end
  end

  before do
    client = double("RubyLLM::Chat")
    %i[with_temperature with_instructions with_schema with_tools with_thinking].each do |m|
      allow(client).to receive(m).and_return(client)
    end
    allow(client).to receive(:messages).and_return([])
    allow(client).to receive(:ask).and_return(
      RubyLLM::Message.new(role: :assistant, content: "hi",
        input_tokens: 10, output_tokens: 5, model_id: "gpt-4.1")
    )
    allow(RubyLLM).to receive(:chat).and_return(client)
    allow_any_instance_of(RubyLLM::Context).to receive(:chat).and_return(client)
  end

  it "never writes the tenant's API key to the execution record" do
    agent_class.call(tenant: tenant_object)

    execution = RubyLLM::Agents::Execution.order(:id).last
    raw_column = execution.read_attribute_before_type_cast(:metadata).to_s

    expect(raw_column).not_to include("SUPERSECRET")
    expect(execution.metadata.to_h.keys).not_to include("tenant_api_keys")
  end

  it "still scopes the LLM call to the tenant's keys" do
    context = RubyLLM::Agents::Pipeline::Context.new(input: "hi", agent_class: agent_class)
    middleware = RubyLLM::Agents::Pipeline::Middleware::Tenant.new(->(ctx) { ctx }, agent_class)
    context.options[:tenant] = tenant_object

    middleware.call(context)

    expect(context.tenant_api_keys).to eq({openai: "sk-live-SUPERSECRET1234567890"})
    expect(context.llm).to be_a(RubyLLM::Context)
    expect(context.metadata).not_to have_key(:tenant_api_keys)
  end

  describe "metadata redaction backstop" do
    # Agent-supplied metadata can carry secrets too. Redact credential-shaped
    # keys on the way to the column, without eating the token counters.
    def metadata_for(agent_metadata)
      klass = Class.new(RubyLLM::Agents::Base) do
        def self.name = "RedactAgent"
        model "gpt-4.1"
        prompt "hi"
      end
      klass.define_method(:metadata) { agent_metadata }
      klass.call
      RubyLLM::Agents::Execution.order(:id).last.metadata
    end

    it "redacts credential-shaped keys" do
      stored = metadata_for({
        api_key: "sk-nope", openai_api_key: "sk-nope", access_token: "nope",
        refresh_token: "nope", client_secret: "nope", user_password: "nope",
        private_key: "nope", token: "nope"
      })

      expect(stored.values.uniq).to eq(["[REDACTED]"])
    end

    it "leaves legitimate token counters and identifiers alone" do
      stored = metadata_for({
        cached_tokens: 6016, token_count: 42, thinking_tokens: 10,
        trace_id: "abc", response_cache_key: "k/1", cost_breakdown: {"cache_read" => 0.1}
      })

      expect(stored["cached_tokens"]).to eq(6016)
      expect(stored["token_count"]).to eq(42)
      expect(stored["thinking_tokens"]).to eq(10)
      expect(stored["trace_id"]).to eq("abc")
      expect(stored["response_cache_key"]).to eq("k/1")
      expect(stored["cost_breakdown"]).to eq({"cache_read" => 0.1})
    end
  end
end
