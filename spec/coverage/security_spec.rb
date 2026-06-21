# frozen_string_literal: true

require "rails_helper"

# Security-focused, real-code specs. No internal classes are mocked or stubbed —
# the real Instrumentation middleware runs against the real Execution /
# ExecutionDetail ActiveRecord models on the in-memory SQLite database, and the
# real query scopes / validations are exercised directly.
#
# The only thing faked is the downstream "app" of the middleware pipeline,
# which stands in for the LLM-calling core executor (the external network
# boundary). It is a plain proc that sets ctx.output, exactly as a real core
# executor would after a successful LLM call.
#
# Coverage:
#   1. Sensitive parameter keys are redacted to "[REDACTED]" in persisted
#      ExecutionDetail#parameters.
#   2. Internal keys (_replay_source_id, _ask_message, ...) are stripped.
#   3. No API key / credential value leaks into execution.metadata or detail.
#   4. Analytics scopes / grouping are injection-safe for hostile agent_type /
#      metadata-key inputs (table survives, no SQL error, parameter-bound).
#   5. Numeric/decimal cost validations reject negative values.
RSpec.describe "Security", type: :model do
  # ── Real agent instance carrying an options hash ────────────────────────
  #
  # Mirrors how a real BaseAgent exposes its call-time params via the private
  # #options reader, which Instrumentation#sanitize_parameters reads.
  def build_agent_instance(options)
    klass = Class.new do
      def initialize(options)
        @options = options
      end

      private

      attr_reader :options
    end
    klass.new(options)
  end

  let(:agent_class) do
    Class.new do
      def self.name = "SecurityProbeAgent"

      def self.agent_type = :embedding

      def self.model = "text-embedding-3-small"
    end
  end

  # Real pass-through app standing in for the LLM-calling core executor.
  let(:passthrough_app) do
    proc do |ctx|
      ctx.output = "ok"
      ctx
    end
  end

  def run_middleware(options)
    agent_instance = build_agent_instance(options)
    context = RubyLLM::Agents::Pipeline::Context.new(
      input: "embed this",
      agent_class: agent_class,
      agent_instance: agent_instance
    )
    middleware = RubyLLM::Agents::Pipeline::Middleware::Instrumentation.new(passthrough_app, agent_class)
    middleware.call(context)
    RubyLLM::Agents::Execution.last
  end

  before do
    RubyLLM::Agents.reset_configuration!
    RubyLLM::Agents.configure do |c|
      c.track_embeddings = true
      c.track_executions = true
      c.async_logging = false
      c.multi_tenancy_enabled = false
      c.persist_prompts = false
      c.persist_responses = false
    end
  end

  after { RubyLLM::Agents.reset_configuration! }

  # ── 1. Sensitive parameter redaction ───────────────────────────────────
  describe "sensitive parameter redaction (real Instrumentation middleware)" do
    # Every key listed in Instrumentation::SENSITIVE_KEYS, paired with a
    # realistic secret value that must NOT be persisted in cleartext.
    let(:secret_values) do
      {
        "password" => "hunter2-supersecret",
        "token" => "tok_live_#{SecureRandom.hex(16)}",
        "api_key" => "sk-#{SecureRandom.hex(24)}",
        "secret" => SecureRandom.hex(20),
        "credential" => "basic #{SecureRandom.base64(18)}",
        "auth" => "Bearer #{SecureRandom.hex(20)}",
        "key" => SecureRandom.hex(16),
        "access_token" => "at_#{SecureRandom.hex(20)}",
        "refresh_token" => "rt_#{SecureRandom.hex(20)}",
        "private_key" => "-----BEGIN PRIVATE KEY-----\n#{SecureRandom.base64(48)}\n-----END PRIVATE KEY-----",
        "secret_key" => "sec_#{SecureRandom.hex(24)}"
      }
    end

    it "covers every key in SENSITIVE_KEYS (guards against drift)" do
      # If a new sensitive key is added to the middleware constant, this test
      # forces the fixture above to be updated too.
      expect(secret_values.keys).to match_array(
        RubyLLM::Agents::Pipeline::Middleware::Instrumentation::SENSITIVE_KEYS
      )
    end

    it "redacts every sensitive key to [REDACTED] in persisted parameters" do
      options = {"query" => "vectorize me"}.merge(secret_values)

      execution = run_middleware(options)

      expect(execution).to be_present
      expect(execution.detail).to be_present
      params = execution.detail.parameters

      # Non-sensitive params survive untouched.
      expect(params["query"]).to eq("vectorize me")

      # Every sensitive key is redacted.
      secret_values.each_key do |key|
        expect(params[key]).to eq("[REDACTED]"),
          "expected #{key.inspect} to be redacted, got #{params[key].inspect}"
      end
    end

    it "does not persist any sensitive value in cleartext anywhere on the record" do
      options = {"query" => "vectorize me"}.merge(secret_values)

      execution = run_middleware(options)
      execution.reload

      # Serialize the entire persisted record graph (columns + delegated detail)
      # and assert none of the actual secret strings appear anywhere.
      haystack = [
        execution.attributes.to_json,
        execution.detail&.attributes.to_json,
        execution.metadata.to_json
      ].join("\n")

      secret_values.each_value do |secret|
        expect(haystack).not_to include(secret),
          "secret value leaked into the persisted record: #{secret.inspect}"
      end
    end

    it "redacts symbol-keyed sensitive params too (keys are normalized to strings)" do
      execution = run_middleware({query: "x", api_key: "sk-symbolic-leak", password: "pw"})

      params = execution.detail.parameters
      expect(params["api_key"]).to eq("[REDACTED]")
      expect(params["password"]).to eq("[REDACTED]")
      expect(params["query"]).to eq("x")
    end
  end

  # ── 2. Internal keys stripped ───────────────────────────────────────────
  describe "internal key stripping" do
    it "removes every INTERNAL_KEY from persisted parameters" do
      internal = RubyLLM::Agents::Pipeline::Middleware::Instrumentation::INTERNAL_KEYS
      # Sanity: the documented internal keys are present.
      expect(internal).to include("_replay_source_id", "_ask_message",
        "_parent_execution_id", "_root_execution_id")

      options = {"query" => "keep me"}
      internal.each { |k| options[k] = "internal-#{k}" }

      execution = run_middleware(options)
      params = execution.detail.parameters

      expect(params["query"]).to eq("keep me")
      internal.each do |k|
        expect(params).not_to have_key(k),
          "internal key #{k.inspect} should have been stripped, got #{params[k].inspect}"
      end
    end

    it "strips internal keys regardless of symbol vs string key form" do
      execution = run_middleware({query: "y", _replay_source_id: 123, _ask_message: "hi"})

      params = execution.detail.parameters
      expect(params).not_to have_key("_replay_source_id")
      expect(params).not_to have_key("_ask_message")
      expect(params["query"]).to eq("y")
    end
  end

  # ── 3. No credential leak into metadata / detail ────────────────────────
  describe "credentials never reach metadata or detail" do
    # An agent whose metadata accidentally references the same secret material:
    # the middleware persists agent metadata verbatim, so this proves the
    # redaction path is the parameters path, and confirms what does/doesn't end
    # up in the metadata column for an ordinary (non-secret) agent.
    let(:agent_with_metadata) do
      Class.new do
        def self.name = "MetaAgent"

        def self.agent_type = :embedding

        def self.model = "text-embedding-3-small"

        def initialize(options)
          @options = options
        end

        def metadata
          {experiment: "ranker_v3", user_id: 7}
        end

        private

        attr_reader :options
      end
    end

    it "keeps secrets out of the metadata column while persisting params (redacted)" do
      api_key = "sk-#{SecureRandom.hex(24)}"
      agent_instance = agent_with_metadata.new({"query" => "q", "api_key" => api_key})

      context = RubyLLM::Agents::Pipeline::Context.new(
        input: "embed",
        agent_class: agent_with_metadata,
        agent_instance: agent_instance
      )
      middleware = RubyLLM::Agents::Pipeline::Middleware::Instrumentation.new(passthrough_app, agent_with_metadata)
      middleware.call(context)

      execution = RubyLLM::Agents::Execution.last.reload

      # Metadata holds only the agent-declared, non-secret fields.
      expect(execution.metadata).to include("experiment" => "ranker_v3", "user_id" => 7)
      expect(execution.metadata.to_json).not_to include(api_key)

      # The secret reaches the parameters store only in redacted form.
      expect(execution.detail.parameters["api_key"]).to eq("[REDACTED]")
      expect(execution.detail.attributes.to_json).not_to include(api_key)
    end
  end

  # ── 4. Injection safety of analytics scopes / grouping ──────────────────
  describe "query scopes are injection-safe" do
    # A representative SQL-injection payload that would drop the table if the
    # value were interpolated into raw SQL instead of bound as a parameter.
    let(:drop_table_payload) { "x'; DROP TABLE ruby_llm_agents_executions; --" }
    let(:json_path_payload) { "evil\"]); DROP TABLE ruby_llm_agents_executions; --" }

    def table_present?
      ActiveRecord::Base.connection.table_exists?("ruby_llm_agents_executions")
    end

    before do
      # Seed one legitimate row so the queries have something to scan.
      create(:execution, agent_type: "RealAgent", metadata: {"rate_limited" => true})
    end

    it "binds agent_type in #by_agent (no injection, table survives)" do
      result = nil
      expect {
        result = RubyLLM::Agents::Execution.by_agent(drop_table_payload).count
      }.not_to raise_error

      expect(result).to eq(0) # payload matched no agent_type, no rows deleted
      expect(table_present?).to be(true)
      # The real row is untouched.
      expect(RubyLLM::Agents::Execution.count).to eq(1)
    end

    it "is safe to group analytics by agent_type after a hostile insert" do
      # Persist a row whose agent_type IS the injection payload — group/count
      # must treat it as plain data, not SQL.
      create(:execution, agent_type: drop_table_payload)

      grouped = nil
      expect {
        grouped = RubyLLM::Agents::Execution.group(:agent_type).count
      }.not_to raise_error

      expect(table_present?).to be(true)
      expect(grouped[drop_table_payload]).to eq(1)
      expect(grouped["RealAgent"]).to eq(1)
    end

    it "binds the JSON path key in #metadata_true (no injection)" do
      result = nil
      expect {
        result = RubyLLM::Agents::Execution.metadata_true(json_path_payload).count
      }.not_to raise_error

      expect(result).to eq(0)
      expect(table_present?).to be(true)
      # The legitimately-flagged row is still queryable via a clean key.
      expect(RubyLLM::Agents::Execution.metadata_true("rate_limited").count).to eq(1)
    end

    it "binds the JSON path key in #metadata_value (no injection)" do
      expect {
        RubyLLM::Agents::Execution.metadata_value(json_path_payload, "anything").count
      }.not_to raise_error
      expect(table_present?).to be(true)
    end

    it "binds the parameter key in #with_parameter (no injection)" do
      # with_parameter joins execution_details and filters by a JSON path key.
      expect {
        RubyLLM::Agents::Execution.with_parameter(json_path_payload).count
      }.not_to raise_error
      expect(table_present?).to be(true)
    end

    it "real analytics rollups run without error against hostile-named rows" do
      create(:execution, agent_type: drop_table_payload, status: "error", error_class: "Boom")

      expect { RubyLLM::Agents::Execution.daily_report }.not_to raise_error
      expect { RubyLLM::Agents::Execution.batch_agent_stats }.not_to raise_error
      expect { RubyLLM::Agents::Execution.cost_by_agent(period: :all_time) }.not_to raise_error
      expect { RubyLLM::Agents::Execution.stats_for(drop_table_payload, period: :all_time) }.not_to raise_error
      expect(table_present?).to be(true)
    end
  end

  # ── 5. Cost validations reject negatives ────────────────────────────────
  describe "numeric/decimal cost validations" do
    def base_attrs
      {agent_type: "ValidAgent", model_id: "gpt-4o", started_at: Time.current, status: "success"}
    end

    it "rejects a negative total_cost" do
      execution = RubyLLM::Agents::Execution.new(base_attrs.merge(total_cost: -0.01))
      expect(execution).not_to be_valid
      expect(execution.errors[:total_cost]).to include("must be greater than or equal to 0")
    end

    it "rejects a negative input_cost and output_cost" do
      execution = RubyLLM::Agents::Execution.new(base_attrs.merge(input_cost: -1.0, output_cost: -2.0))
      expect(execution).not_to be_valid
      expect(execution.errors[:input_cost]).to include("must be greater than or equal to 0")
      expect(execution.errors[:output_cost]).to include("must be greater than or equal to 0")
    end

    it "rejects negative token counts and duration" do
      execution = RubyLLM::Agents::Execution.new(
        base_attrs.merge(input_tokens: -5, output_tokens: -10, duration_ms: -3)
      )
      expect(execution).not_to be_valid
      expect(execution.errors[:input_tokens]).to include("must be greater than or equal to 0")
      expect(execution.errors[:output_tokens]).to include("must be greater than or equal to 0")
      expect(execution.errors[:duration_ms]).to include("must be greater than or equal to 0")
    end

    it "allows zero and positive costs (boundary)" do
      zero = RubyLLM::Agents::Execution.new(base_attrs.merge(input_cost: 0, output_cost: 0, total_cost: 0))
      expect(zero).to be_valid

      positive = RubyLLM::Agents::Execution.new(base_attrs.merge(input_cost: 0.003, output_cost: 0.006, total_cost: 0.009))
      expect(positive).to be_valid
    end

    it "refuses to persist a negative-cost row to the database" do
      execution = RubyLLM::Agents::Execution.new(base_attrs.merge(total_cost: -100.0))
      expect { execution.save! }.to raise_error(ActiveRecord::RecordInvalid)
      expect(RubyLLM::Agents::Execution.where(agent_type: "ValidAgent").count).to eq(0)
    end
  end
end
