# frozen_string_literal: true

require "rails_helper"

RSpec.describe RubyLLM::Agents::Configuration do
  subject(:config) { described_class.new }

  describe "#initialize" do
    it "sets default model" do
      expect(config.default_model).to eq("gemini-2.0-flash")
    end

    it "sets default temperature" do
      expect(config.default_temperature).to eq(0.0)
    end

    it "sets default timeout" do
      expect(config.default_timeout).to eq(60)
    end

    it "sets async_logging to true by default" do
      expect(config.async_logging).to be true
    end

    it "sets retention_period to 30 days" do
      expect(config.retention_period).to eq(30.days)
    end

    it "sets anomaly thresholds" do
      expect(config.anomaly_cost_threshold).to eq(5.00)
      expect(config.anomaly_duration_threshold).to eq(10_000)
    end

    it "sets dashboard defaults" do
      expect(config.dashboard_parent_controller).to eq("ActionController::Base")
      expect(config.basic_auth_username).to be_nil
      expect(config.basic_auth_password).to be_nil
      expect(config.per_page).to eq(25)
      expect(config.recent_executions_limit).to eq(10)
    end

    it "sets job defaults" do
      expect(config.job_retry_attempts).to eq(3)
    end

    it "sets reliability defaults" do
      expect(config.default_retries).to eq({ max: 0, backoff: :exponential, base: 0.4, max_delay: 3.0, on: [] })
      expect(config.default_fallback_models).to eq([])
      expect(config.default_total_timeout).to be_nil
    end

    it "sets streaming and tools defaults" do
      expect(config.default_streaming).to be false
      expect(config.default_tools).to eq([])
    end

    it "sets governance defaults" do
      expect(config.budgets).to be_nil
      expect(config.alerts).to be_nil
      expect(config.persist_prompts).to be true
      expect(config.persist_responses).to be true
      expect(config.redaction).to be_nil
    end

    it "sets embedding defaults" do
      expect(config.default_embedding_model).to eq("text-embedding-3-small")
      expect(config.default_embedding_dimensions).to be_nil
      expect(config.default_embedding_batch_size).to eq(100)
      expect(config.track_embeddings).to be true
    end

    it "sets multi-tenancy defaults" do
      expect(config.multi_tenancy_enabled).to be false
      expect(config.tenant_resolver).to be_a(Proc)
      expect(config.tenant_resolver.call).to be_nil
    end

    it "sets dashboard_auth to allow all by default" do
      expect(config.dashboard_auth.call(nil)).to be true
    end
  end

  describe "#cache_store" do
    it "falls back to Rails.cache when not set" do
      expect(config.cache_store).to eq(Rails.cache)
    end

    it "returns custom cache store when set" do
      custom_store = ActiveSupport::Cache::MemoryStore.new
      config.cache_store = custom_store
      expect(config.cache_store).to eq(custom_store)
    end
  end

  describe "#budgets_enabled?" do
    it "returns false when budgets is nil" do
      config.budgets = nil
      expect(config.budgets_enabled?).to be false
    end

    it "returns false when budgets is not a hash" do
      config.budgets = "invalid"
      expect(config.budgets_enabled?).to be false
    end

    it "returns falsey when enforcement is nil" do
      config.budgets = { global_daily: 100 }
      expect(config.budgets_enabled?).to be_falsey
    end

    it "returns false when enforcement is :none" do
      config.budgets = { global_daily: 100, enforcement: :none }
      expect(config.budgets_enabled?).to be false
    end

    it "returns true when enforcement is :soft" do
      config.budgets = { global_daily: 100, enforcement: :soft }
      expect(config.budgets_enabled?).to be true
    end

    it "returns true when enforcement is :hard" do
      config.budgets = { global_daily: 100, enforcement: :hard }
      expect(config.budgets_enabled?).to be true
    end
  end

  describe "#budget_enforcement" do
    it "returns :none when budgets is nil" do
      config.budgets = nil
      expect(config.budget_enforcement).to eq(:none)
    end

    it "returns :none when enforcement is not set" do
      config.budgets = { global_daily: 100 }
      expect(config.budget_enforcement).to eq(:none)
    end

    it "returns the configured enforcement" do
      config.budgets = { enforcement: :hard }
      expect(config.budget_enforcement).to eq(:hard)
    end
  end

  describe "#alerts_enabled?" do
    it "returns false when alerts is nil" do
      config.alerts = nil
      expect(config.alerts_enabled?).to be false
    end

    it "returns false when alerts is not a hash" do
      config.alerts = "invalid"
      expect(config.alerts_enabled?).to be false
    end

    it "returns false when no destinations are configured" do
      config.alerts = { on_events: [:budget_exceeded] }
      expect(config.alerts_enabled?).to be false
    end

    it "returns true when slack_webhook_url is configured" do
      config.alerts = { slack_webhook_url: "https://hooks.slack.com/..." }
      expect(config.alerts_enabled?).to be true
    end

    it "returns true when webhook_url is configured" do
      config.alerts = { webhook_url: "https://example.com/webhook" }
      expect(config.alerts_enabled?).to be true
    end

    it "returns true when custom callback is configured" do
      config.alerts = { custom: ->(event, payload) { } }
      expect(config.alerts_enabled?).to be true
    end
  end

  describe "#alert_events" do
    it "returns empty array when alerts is nil" do
      config.alerts = nil
      expect(config.alert_events).to eq([])
    end

    it "returns empty array when on_events is not set" do
      config.alerts = { slack_webhook_url: "url" }
      expect(config.alert_events).to eq([])
    end

    it "returns configured events" do
      config.alerts = { on_events: [:budget_soft_cap, :breaker_open] }
      expect(config.alert_events).to eq([:budget_soft_cap, :breaker_open])
    end
  end

  describe "#redaction_fields" do
    it "returns default sensitive fields when redaction is nil" do
      config.redaction = nil
      expect(config.redaction_fields).to include("password", "token", "api_key", "secret")
    end

    it "merges custom fields with defaults" do
      config.redaction = { fields: %w[ssn credit_card] }
      expect(config.redaction_fields).to include("password", "ssn", "credit_card")
    end

    it "deduplicates and downcases fields" do
      config.redaction = { fields: %w[PASSWORD Token] }
      fields = config.redaction_fields
      expect(fields.count("password")).to eq(1)
      expect(fields.count("token")).to eq(1)
    end
  end

  describe "#redaction_patterns" do
    it "returns empty array when redaction is nil" do
      config.redaction = nil
      expect(config.redaction_patterns).to eq([])
    end

    it "returns configured patterns" do
      ssn_pattern = /\b\d{3}-\d{2}-\d{4}\b/
      config.redaction = { patterns: [ssn_pattern] }
      expect(config.redaction_patterns).to eq([ssn_pattern])
    end
  end

  describe "#redaction_placeholder" do
    it "returns default placeholder when redaction is nil" do
      config.redaction = nil
      expect(config.redaction_placeholder).to eq("[REDACTED]")
    end

    it "returns default placeholder when not configured" do
      config.redaction = { fields: %w[password] }
      expect(config.redaction_placeholder).to eq("[REDACTED]")
    end

    it "returns configured placeholder" do
      config.redaction = { placeholder: "***" }
      expect(config.redaction_placeholder).to eq("***")
    end
  end

  describe "#redaction_max_value_length" do
    it "returns nil when redaction is nil" do
      config.redaction = nil
      expect(config.redaction_max_value_length).to be_nil
    end

    it "returns nil when not configured" do
      config.redaction = { fields: %w[password] }
      expect(config.redaction_max_value_length).to be_nil
    end

    it "returns configured max length" do
      config.redaction = { max_value_length: 5000 }
      expect(config.redaction_max_value_length).to eq(5000)
    end
  end

  describe "#multi_tenancy_enabled?" do
    it "returns false by default" do
      expect(config.multi_tenancy_enabled?).to be false
    end

    it "returns true when enabled" do
      config.multi_tenancy_enabled = true
      expect(config.multi_tenancy_enabled?).to be true
    end

    it "returns false for truthy non-true values" do
      config.multi_tenancy_enabled = "yes"
      expect(config.multi_tenancy_enabled?).to be false
    end
  end

  describe "#current_tenant_id" do
    it "returns nil when multi-tenancy is disabled" do
      config.multi_tenancy_enabled = false
      config.tenant_resolver = -> { "tenant_123" }
      expect(config.current_tenant_id).to be_nil
    end

    it "calls tenant_resolver when multi-tenancy is enabled" do
      config.multi_tenancy_enabled = true
      config.tenant_resolver = -> { "tenant_123" }
      expect(config.current_tenant_id).to eq("tenant_123")
    end

    it "returns nil when tenant_resolver returns nil" do
      config.multi_tenancy_enabled = true
      config.tenant_resolver = -> { nil }
      expect(config.current_tenant_id).to be_nil
    end
  end

  describe "attribute accessors" do
    it "allows setting and getting all attributes" do
      config.default_model = "gpt-4"
      config.default_temperature = 0.7
      config.default_timeout = 120
      config.async_logging = false
      config.retention_period = 60.days
      config.anomaly_cost_threshold = 10.0
      config.anomaly_duration_threshold = 20_000
      config.dashboard_parent_controller = "AdminController"
      config.basic_auth_username = "admin"
      config.basic_auth_password = "secret"
      config.per_page = 50
      config.recent_executions_limit = 20
      config.job_retry_attempts = 5
      config.default_retries = { max: 3 }
      config.default_fallback_models = ["gpt-4o-mini"]
      config.default_total_timeout = 300
      config.default_streaming = true
      config.default_tools = [String]
      config.persist_prompts = false
      config.persist_responses = false
      config.default_embedding_model = "text-embedding-3-large"
      config.default_embedding_dimensions = 512
      config.default_embedding_batch_size = 50
      config.track_embeddings = false

      expect(config.default_model).to eq("gpt-4")
      expect(config.default_temperature).to eq(0.7)
      expect(config.default_timeout).to eq(120)
      expect(config.async_logging).to be false
      expect(config.retention_period).to eq(60.days)
      expect(config.anomaly_cost_threshold).to eq(10.0)
      expect(config.anomaly_duration_threshold).to eq(20_000)
      expect(config.dashboard_parent_controller).to eq("AdminController")
      expect(config.basic_auth_username).to eq("admin")
      expect(config.basic_auth_password).to eq("secret")
      expect(config.per_page).to eq(50)
      expect(config.recent_executions_limit).to eq(20)
      expect(config.job_retry_attempts).to eq(5)
      expect(config.default_retries).to eq({ max: 3 })
      expect(config.default_fallback_models).to eq(["gpt-4o-mini"])
      expect(config.default_total_timeout).to eq(300)
      expect(config.default_streaming).to be true
      expect(config.default_tools).to eq([String])
      expect(config.persist_prompts).to be false
      expect(config.persist_responses).to be false
      expect(config.default_embedding_model).to eq("text-embedding-3-large")
      expect(config.default_embedding_dimensions).to eq(512)
      expect(config.default_embedding_batch_size).to eq(50)
      expect(config.track_embeddings).to be false
    end
  end

  describe "validation" do
    describe "#default_temperature=" do
      it "accepts values between 0.0 and 2.0" do
        expect { config.default_temperature = 0.0 }.not_to raise_error
        expect { config.default_temperature = 1.0 }.not_to raise_error
        expect { config.default_temperature = 2.0 }.not_to raise_error
      end

      it "raises ArgumentError for values below 0.0" do
        expect { config.default_temperature = -0.1 }.to raise_error(
          ArgumentError, "default_temperature must be between 0.0 and 2.0"
        )
      end

      it "raises ArgumentError for values above 2.0" do
        expect { config.default_temperature = 2.1 }.to raise_error(
          ArgumentError, "default_temperature must be between 0.0 and 2.0"
        )
      end

      it "raises ArgumentError for non-numeric values" do
        expect { config.default_temperature = "high" }.to raise_error(
          ArgumentError, "default_temperature must be between 0.0 and 2.0"
        )
      end
    end

    describe "#default_timeout=" do
      it "accepts positive values" do
        expect { config.default_timeout = 1 }.not_to raise_error
        expect { config.default_timeout = 120 }.not_to raise_error
      end

      it "raises ArgumentError for zero" do
        expect { config.default_timeout = 0 }.to raise_error(
          ArgumentError, "default_timeout must be greater than 0"
        )
      end

      it "raises ArgumentError for negative values" do
        expect { config.default_timeout = -1 }.to raise_error(
          ArgumentError, "default_timeout must be greater than 0"
        )
      end
    end

    describe "#anomaly_cost_threshold=" do
      it "accepts zero and positive values" do
        expect { config.anomaly_cost_threshold = 0 }.not_to raise_error
        expect { config.anomaly_cost_threshold = 10.0 }.not_to raise_error
      end

      it "raises ArgumentError for negative values" do
        expect { config.anomaly_cost_threshold = -1 }.to raise_error(
          ArgumentError, "anomaly_cost_threshold must be >= 0"
        )
      end
    end

    describe "#anomaly_duration_threshold=" do
      it "accepts zero and positive values" do
        expect { config.anomaly_duration_threshold = 0 }.not_to raise_error
        expect { config.anomaly_duration_threshold = 5000 }.not_to raise_error
      end

      it "raises ArgumentError for negative values" do
        expect { config.anomaly_duration_threshold = -100 }.to raise_error(
          ArgumentError, "anomaly_duration_threshold must be >= 0"
        )
      end
    end

    describe "#per_page=" do
      it "accepts positive values" do
        expect { config.per_page = 1 }.not_to raise_error
        expect { config.per_page = 100 }.not_to raise_error
      end

      it "raises ArgumentError for zero" do
        expect { config.per_page = 0 }.to raise_error(
          ArgumentError, "per_page must be greater than 0"
        )
      end

      it "raises ArgumentError for negative values" do
        expect { config.per_page = -10 }.to raise_error(
          ArgumentError, "per_page must be greater than 0"
        )
      end
    end

    describe "#recent_executions_limit=" do
      it "accepts positive values" do
        expect { config.recent_executions_limit = 1 }.not_to raise_error
        expect { config.recent_executions_limit = 50 }.not_to raise_error
      end

      it "raises ArgumentError for zero" do
        expect { config.recent_executions_limit = 0 }.to raise_error(
          ArgumentError, "recent_executions_limit must be greater than 0"
        )
      end
    end

    describe "#job_retry_attempts=" do
      it "accepts zero and positive values" do
        expect { config.job_retry_attempts = 0 }.not_to raise_error
        expect { config.job_retry_attempts = 5 }.not_to raise_error
      end

      it "raises ArgumentError for negative values" do
        expect { config.job_retry_attempts = -1 }.to raise_error(
          ArgumentError, "job_retry_attempts must be >= 0"
        )
      end
    end

    describe "#messages_summary_max_length=" do
      it "accepts positive values" do
        expect { config.messages_summary_max_length = 1 }.not_to raise_error
        expect { config.messages_summary_max_length = 1000 }.not_to raise_error
      end

      it "raises ArgumentError for zero" do
        expect { config.messages_summary_max_length = 0 }.to raise_error(
          ArgumentError, "messages_summary_max_length must be greater than 0"
        )
      end
    end

    describe "#dashboard_auth=" do
      it "accepts callable objects" do
        expect { config.dashboard_auth = -> { true } }.not_to raise_error
        expect { config.dashboard_auth = proc { true } }.not_to raise_error
      end

      it "accepts nil" do
        expect { config.dashboard_auth = nil }.not_to raise_error
      end

      it "raises ArgumentError for non-callable values" do
        expect { config.dashboard_auth = "not callable" }.to raise_error(
          ArgumentError, "dashboard_auth must be callable or nil"
        )
      end
    end

    describe "#tenant_resolver=" do
      it "accepts callable objects" do
        expect { config.tenant_resolver = -> { "tenant_123" } }.not_to raise_error
      end

      it "raises ArgumentError for nil" do
        expect { config.tenant_resolver = nil }.to raise_error(
          ArgumentError, "tenant_resolver must be callable"
        )
      end

      it "raises ArgumentError for non-callable values" do
        expect { config.tenant_resolver = "not callable" }.to raise_error(
          ArgumentError, "tenant_resolver must be callable"
        )
      end
    end

    describe "#tenant_config_resolver=" do
      it "accepts callable objects" do
        expect { config.tenant_config_resolver = ->(id) { { daily: 100 } } }.not_to raise_error
      end

      it "accepts nil" do
        expect { config.tenant_config_resolver = nil }.not_to raise_error
      end

      it "raises ArgumentError for non-callable values" do
        expect { config.tenant_config_resolver = "not callable" }.to raise_error(
          ArgumentError, "tenant_config_resolver must be callable or nil"
        )
      end
    end

    describe "#default_retries=" do
      it "accepts valid retry configurations" do
        expect { config.default_retries = { max: 3, backoff: :exponential, base: 0.5, max_delay: 5.0 } }.not_to raise_error
        expect { config.default_retries = { max: 3, backoff: :constant, base: 1.0, max_delay: 10.0 } }.not_to raise_error
        expect { config.default_retries = { max: 0 } }.not_to raise_error
      end

      it "raises ArgumentError for invalid backoff" do
        expect { config.default_retries = { backoff: :invalid } }.to raise_error(
          ArgumentError, "default_retries[:backoff] must be :exponential or :constant"
        )
      end

      it "raises ArgumentError for non-positive base" do
        expect { config.default_retries = { base: 0 } }.to raise_error(
          ArgumentError, "default_retries[:base] must be greater than 0"
        )
        expect { config.default_retries = { base: -1 } }.to raise_error(
          ArgumentError, "default_retries[:base] must be greater than 0"
        )
      end

      it "raises ArgumentError for non-positive max_delay" do
        expect { config.default_retries = { max_delay: 0 } }.to raise_error(
          ArgumentError, "default_retries[:max_delay] must be greater than 0"
        )
      end
    end

    describe "#budgets=" do
      it "accepts nil" do
        expect { config.budgets = nil }.not_to raise_error
      end

      it "accepts valid enforcement values" do
        expect { config.budgets = { enforcement: :none } }.not_to raise_error
        expect { config.budgets = { enforcement: :soft } }.not_to raise_error
        expect { config.budgets = { enforcement: :hard } }.not_to raise_error
      end

      it "accepts budget config without enforcement" do
        expect { config.budgets = { global_daily: 100 } }.not_to raise_error
      end

      it "raises ArgumentError for invalid enforcement" do
        expect { config.budgets = { enforcement: :invalid } }.to raise_error(
          ArgumentError, "budgets[:enforcement] must be :none, :soft, or :hard"
        )
      end
    end

    describe "#default_embedding_batch_size=" do
      it "accepts positive values" do
        expect { config.default_embedding_batch_size = 1 }.not_to raise_error
        expect { config.default_embedding_batch_size = 100 }.not_to raise_error
      end

      it "raises ArgumentError for zero" do
        expect { config.default_embedding_batch_size = 0 }.to raise_error(
          ArgumentError, "default_embedding_batch_size must be greater than 0"
        )
      end

      it "raises ArgumentError for negative values" do
        expect { config.default_embedding_batch_size = -1 }.to raise_error(
          ArgumentError, "default_embedding_batch_size must be greater than 0"
        )
      end
    end

    describe "#default_embedding_dimensions=" do
      it "accepts nil" do
        expect { config.default_embedding_dimensions = nil }.not_to raise_error
      end

      it "accepts positive values" do
        expect { config.default_embedding_dimensions = 256 }.not_to raise_error
        expect { config.default_embedding_dimensions = 1536 }.not_to raise_error
      end

      it "raises ArgumentError for zero" do
        expect { config.default_embedding_dimensions = 0 }.to raise_error(
          ArgumentError, "default_embedding_dimensions must be nil or greater than 0"
        )
      end

      it "raises ArgumentError for negative values" do
        expect { config.default_embedding_dimensions = -1 }.to raise_error(
          ArgumentError, "default_embedding_dimensions must be nil or greater than 0"
        )
      end
    end
  end

  describe "directory and namespace configuration" do
    describe "#root_directory" do
      it "defaults to 'agents'" do
        expect(config.root_directory).to eq("agents")
      end

      it "can be customized" do
        config.root_directory = "ai"
        expect(config.root_directory).to eq("ai")
      end
    end

    describe "#root_namespace" do
      it "defaults to nil (no namespace)" do
        expect(config.root_namespace).to be_nil
      end

      it "can be customized" do
        config.root_namespace = "AI"
        expect(config.root_namespace).to eq("AI")
      end

      it "can be set to nil for no namespace" do
        config.root_namespace = nil
        expect(config.root_namespace).to be_nil
      end

      it "can be set to empty string for no namespace" do
        config.root_namespace = ""
        expect(config.root_namespace).to eq("")
      end
    end

    describe "#namespace_for" do
      context "with default namespace (nil)" do
        it "returns nil for nil category" do
          expect(config.namespace_for(nil)).to be_nil
        end

        it "returns nil for no argument" do
          expect(config.namespace_for).to be_nil
        end

        it "returns Images for :images category" do
          expect(config.namespace_for(:images)).to eq("Images")
        end

        it "returns Audio for :audio category" do
          expect(config.namespace_for(:audio)).to eq("Audio")
        end

        it "returns Embedders for :embedders category" do
          expect(config.namespace_for(:embedders)).to eq("Embedders")
        end

        it "returns Moderators for :moderators category" do
          expect(config.namespace_for(:moderators)).to eq("Moderators")
        end

        it "returns Workflows for :workflows category" do
          expect(config.namespace_for(:workflows)).to eq("Workflows")
        end
      end
    end

    describe "#path_for" do
      context "with default root_directory (agents)" do
        it "returns app/agents for nil category" do
          expect(config.path_for(nil)).to eq("app/agents")
        end

        it "returns app/agents/tools for tools type" do
          expect(config.path_for(nil, "tools")).to eq("app/agents/tools")
        end

        it "returns app/agents/images for :images category" do
          expect(config.path_for(:images)).to eq("app/agents/images")
        end

        it "returns app/agents/audio for :audio category" do
          expect(config.path_for(:audio)).to eq("app/agents/audio")
        end

        it "returns app/agents/embedders for :embedders category" do
          expect(config.path_for(:embedders)).to eq("app/agents/embedders")
        end

        it "returns app/agents/moderators for :moderators category" do
          expect(config.path_for(:moderators)).to eq("app/agents/moderators")
        end

        it "returns app/agents/workflows for :workflows category" do
          expect(config.path_for(:workflows)).to eq("app/agents/workflows")
        end
      end
    end

    describe "#all_autoload_paths" do
      it "returns an array of paths" do
        expect(config.all_autoload_paths).to be_an(Array)
      end

      it "includes base agents path" do
        paths = config.all_autoload_paths
        expect(paths).to include("app/agents")
      end

      it "includes images path" do
        paths = config.all_autoload_paths
        expect(paths).to include("app/agents/images")
      end

      it "includes audio path" do
        paths = config.all_autoload_paths
        expect(paths).to include("app/agents/audio")
      end

      it "includes embedders path" do
        paths = config.all_autoload_paths
        expect(paths).to include("app/agents/embedders")
      end

      it "includes moderators path" do
        paths = config.all_autoload_paths
        expect(paths).to include("app/agents/moderators")
      end

      it "includes workflows path" do
        paths = config.all_autoload_paths
        expect(paths).to include("app/agents/workflows")
      end
    end
  end
end
