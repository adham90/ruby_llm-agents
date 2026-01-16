# frozen_string_literal: true

module RubyLLM
  module Agents
    # Global configuration for RubyLLM::Agents
    #
    # Provides centralized settings for agent behavior, dashboard authentication,
    # caching, and observability thresholds.
    #
    # @example Basic configuration
    #   RubyLLM::Agents.configure do |config|
    #     config.default_model = "gpt-4o"
    #     config.default_temperature = 0.7
    #     config.async_logging = true
    #   end
    #
    # @example Dashboard with HTTP Basic Auth
    #   RubyLLM::Agents.configure do |config|
    #     config.basic_auth_username = ENV["AGENTS_USER"]
    #     config.basic_auth_password = ENV["AGENTS_PASS"]
    #   end
    #
    # @example Dashboard with custom authentication
    #   RubyLLM::Agents.configure do |config|
    #     config.dashboard_parent_controller = "AdminController"
    #     config.dashboard_auth = ->(controller) { controller.current_user&.admin? }
    #   end
    #
    # @see RubyLLM::Agents.configure
    # @api public
    class Configuration
      # @!attribute [rw] default_model
      #   The default LLM model identifier for all agents.
      #   Can be overridden per-agent using the `model` DSL method.
      #   @return [String] Model identifier (default: "gemini-2.0-flash")
      #   @example
      #     config.default_model = "gpt-4o"

      # @!attribute [rw] default_temperature
      #   The default temperature for LLM responses (0.0 to 2.0).
      #   Lower values produce more deterministic outputs.
      #   @return [Float] Temperature value (default: 0.0)

      # @!attribute [rw] default_timeout
      #   Maximum seconds to wait for an LLM response before timing out.
      #   @return [Integer] Timeout in seconds (default: 60)

      # @!attribute [rw] async_logging
      #   Whether to log executions via background job (recommended for production).
      #   When false, executions are logged synchronously.
      #   @return [Boolean] Enable async logging (default: true)

      # @!attribute [rw] retention_period
      #   How long to retain execution records before cleanup.
      #   @return [ActiveSupport::Duration] Retention period (default: 30.days)

      # @!attribute [rw] anomaly_cost_threshold
      #   Cost threshold in dollars that triggers anomaly logging.
      #   Executions exceeding this cost are logged as warnings.
      #   @return [Float] Cost threshold in USD (default: 5.00)

      # @!attribute [rw] anomaly_duration_threshold
      #   Duration threshold in milliseconds that triggers anomaly logging.
      #   @return [Integer] Duration threshold in ms (default: 10_000)

      # @!attribute [rw] dashboard_auth
      #   Lambda for custom dashboard authentication.
      #   Receives the controller instance, should return truthy to allow access.
      #   @return [Proc] Authentication lambda (default: allows all)
      #   @example
      #     config.dashboard_auth = ->(c) { c.current_user&.admin? }

      # @!attribute [rw] dashboard_parent_controller
      #   Parent controller class name for the dashboard.
      #   Use this to inherit authentication from your app's admin controller.
      #   @return [String] Controller class name (default: "ActionController::Base")

      # @!attribute [rw] basic_auth_username
      #   Username for HTTP Basic Auth on the dashboard.
      #   Both username and password must be set to enable Basic Auth.
      #   @return [String, nil] Username or nil to disable (default: nil)

      # @!attribute [rw] basic_auth_password
      #   Password for HTTP Basic Auth on the dashboard.
      #   @return [String, nil] Password or nil to disable (default: nil)

      # @!attribute [rw] per_page
      #   Number of records per page in dashboard listings.
      #   @return [Integer] Records per page (default: 25)

      # @!attribute [rw] recent_executions_limit
      #   Number of recent executions shown on the dashboard home.
      #   @return [Integer] Limit for recent executions (default: 10)

      # @!attribute [rw] job_retry_attempts
      #   Number of retry attempts for the async logging job on failure.
      #   @return [Integer] Retry attempts (default: 3)

      # @!attribute [w] cache_store
      #   Custom cache store for agent response caching.
      #   Falls back to Rails.cache if not set.
      #   @return [ActiveSupport::Cache::Store, nil]

      # @!attribute [rw] default_retries
      #   Default retry configuration for all agents.
      #   Can be overridden per-agent using the `retries` DSL method.
      #   @return [Hash] Retry config with :max, :backoff, :base, :max_delay, :on keys
      #   @example
      #     config.default_retries = { max: 2, backoff: :exponential, base: 0.4, max_delay: 3.0, on: [] }

      # @!attribute [rw] default_fallback_models
      #   Default fallback models for all agents.
      #   Can be overridden per-agent using the `fallback_models` DSL method.
      #   @return [Array<String>] List of model identifiers to try on failure

      # @!attribute [rw] default_total_timeout
      #   Default total timeout across all retry attempts.
      #   Can be overridden per-agent using the `total_timeout` DSL method.
      #   @return [Integer, nil] Total timeout in seconds, or nil for no limit

      # @!attribute [rw] default_streaming
      #   Whether streaming mode is enabled by default for all agents.
      #   When enabled and a block is passed to call, chunks are yielded as they arrive.
      #   Can be overridden per-agent using the `streaming` DSL method.
      #   @return [Boolean] Enable streaming (default: false)
      #   @example
      #     config.default_streaming = true

      # @!attribute [rw] default_tools
      #   Default tools available to all agents.
      #   Should be an array of RubyLLM::Tool classes.
      #   Can be overridden or extended per-agent using the `tools` DSL method.
      #   @return [Array<Class>] Tool classes (default: [])
      #   @example
      #     config.default_tools = [WeatherTool, SearchTool]

      # @!attribute [rw] budgets
      #   Budget configuration for cost governance.
      #   @return [Hash, nil] Budget config with :global_daily, :global_monthly, :per_agent_daily, :per_agent_monthly, :enforcement keys
      #   @example
      #     config.budgets = {
      #       global_daily: 25.0,
      #       global_monthly: 300.0,
      #       per_agent_daily: { "ContentAgent" => 5.0 },
      #       per_agent_monthly: { "ContentAgent" => 120.0 },
      #       enforcement: :soft
      #     }

      # @!attribute [rw] alerts
      #   Alert configuration for notifications.
      #   @return [Hash, nil] Alert config with :slack_webhook_url, :webhook_url, :on_events, :custom keys
      #   @example
      #     config.alerts = {
      #       slack_webhook_url: ENV["SLACK_WEBHOOK"],
      #       webhook_url: ENV["AGENTS_WEBHOOK"],
      #       on_events: [:budget_soft_cap, :budget_hard_cap, :breaker_open],
      #       custom: ->(event, payload) { Rails.logger.info("Alert: #{event}") }
      #     }

      # @!attribute [rw] persist_prompts
      #   Whether to persist system and user prompts in execution records.
      #   Set to false to reduce storage or for privacy compliance.
      #   @return [Boolean] Enable prompt persistence (default: true)

      # @!attribute [rw] persist_responses
      #   Whether to persist LLM responses in execution records.
      #   Set to false to reduce storage or for privacy compliance.
      #   @return [Boolean] Enable response persistence (default: true)

      # @!attribute [rw] redaction
      #   Redaction configuration for PII and sensitive data.
      #   @return [Hash, nil] Redaction config with :fields, :patterns, :placeholder, :max_value_length keys
      #   @example
      #     config.redaction = {
      #       fields: %w[password api_key email ssn],
      #       patterns: [/\b\d{3}-\d{2}-\d{4}\b/],
      #       placeholder: "[REDACTED]",
      #       max_value_length: 5000
      #     }

      # @!attribute [rw] multi_tenancy_enabled
      #   Whether multi-tenancy features are enabled.
      #   When false, the gem behaves exactly as before (backward compatible).
      #   @return [Boolean] Enable multi-tenancy (default: false)
      #   @example
      #     config.multi_tenancy_enabled = true

      # @!attribute [rw] tenant_resolver
      #   Lambda that returns the current tenant identifier.
      #   Called whenever tenant context is needed for budget tracking,
      #   circuit breakers, and execution recording.
      #   @return [Proc] Tenant resolution lambda (default: -> { nil })
      #   @example Using Rails CurrentAttributes
      #     config.tenant_resolver = -> { Current.tenant&.id }
      #   @example Using request store
      #     config.tenant_resolver = -> { RequestStore[:tenant_id] }

      # @!attribute [rw] persist_messages_summary
      #   Whether to persist a summary of conversation messages in execution records.
      #   When true, stores message count and first/last messages (truncated).
      #   Set to false to disable message summary persistence.
      #   @return [Boolean] Enable messages summary persistence (default: true)

      # @!attribute [rw] messages_summary_max_length
      #   Maximum character length for message content in the summary.
      #   Content exceeding this length will be truncated with "...".
      #   @return [Integer] Max length for message content (default: 500)

      attr_accessor :default_model,
                    :default_temperature,
                    :default_timeout,
                    :async_logging,
                    :retention_period,
                    :anomaly_cost_threshold,
                    :anomaly_duration_threshold,
                    :dashboard_auth,
                    :dashboard_parent_controller,
                    :basic_auth_username,
                    :basic_auth_password,
                    :per_page,
                    :recent_executions_limit,
                    :job_retry_attempts,
                    :default_retries,
                    :default_fallback_models,
                    :default_total_timeout,
                    :default_streaming,
                    :default_tools,
                    :budgets,
                    :alerts,
                    :persist_prompts,
                    :persist_responses,
                    :redaction,
                    :multi_tenancy_enabled,
                    :tenant_resolver,
                    :persist_messages_summary,
                    :messages_summary_max_length

      attr_writer :cache_store

      # Initializes configuration with default values
      #
      # @return [Configuration] A new configuration instance with defaults
      # @api private
      def initialize
        @default_model = "gemini-2.0-flash"
        @default_temperature = 0.0
        @default_timeout = 60
        @cache_store = nil
        @async_logging = true
        @retention_period = 30.days
        @anomaly_cost_threshold = 5.00
        @anomaly_duration_threshold = 10_000
        @dashboard_auth = ->(_controller) { true }
        @dashboard_parent_controller = "ActionController::Base"
        @basic_auth_username = nil
        @basic_auth_password = nil
        @per_page = 25
        @recent_executions_limit = 10
        @job_retry_attempts = 3

        # Reliability defaults (all disabled by default for backward compatibility)
        @default_retries = { max: 0, backoff: :exponential, base: 0.4, max_delay: 3.0, on: [] }
        @default_fallback_models = []
        @default_total_timeout = nil

        # Streaming and tools defaults
        @default_streaming = false
        @default_tools = []

        # Governance defaults
        @budgets = nil
        @alerts = nil
        @persist_prompts = true
        @persist_responses = true
        @redaction = nil

        # Multi-tenancy defaults (disabled for backward compatibility)
        @multi_tenancy_enabled = false
        @tenant_resolver = -> { nil }

        # Messages summary defaults
        @persist_messages_summary = true
        @messages_summary_max_length = 500
      end

      # Returns the configured cache store, falling back to Rails.cache
      #
      # @return [ActiveSupport::Cache::Store] The cache store instance
      # @example Using a custom cache store
      #   config.cache_store = ActiveSupport::Cache::MemoryStore.new
      def cache_store
        @cache_store || Rails.cache
      end

      # Returns whether budgets are configured and enforcement is enabled
      #
      # @return [Boolean] true if budgets are configured with enforcement
      def budgets_enabled?
        budgets.is_a?(Hash) && budgets[:enforcement] && budgets[:enforcement] != :none
      end

      # Returns the budget enforcement mode
      #
      # @return [Symbol] :none, :soft, or :hard
      def budget_enforcement
        budgets&.dig(:enforcement) || :none
      end

      # Returns whether alerts are configured
      #
      # @return [Boolean] true if any alert destination is configured
      def alerts_enabled?
        return false unless alerts.is_a?(Hash)

        alerts[:slack_webhook_url].present? ||
          alerts[:webhook_url].present? ||
          alerts[:custom].present?
      end

      # Returns the list of events to alert on
      #
      # @return [Array<Symbol>] Event names to trigger alerts
      def alert_events
        alerts&.dig(:on_events) || []
      end

      # Returns merged redaction fields (default sensitive keys + configured)
      #
      # @return [Array<String>] Field names to redact
      def redaction_fields
        default_fields = %w[password token api_key secret credential auth key access_token]
        configured_fields = redaction&.dig(:fields) || []
        (default_fields + configured_fields).map(&:downcase).uniq
      end

      # Returns redaction patterns
      #
      # @return [Array<Regexp>] Patterns to match and redact
      def redaction_patterns
        redaction&.dig(:patterns) || []
      end

      # Returns the redaction placeholder string
      #
      # @return [String] Placeholder to replace redacted values
      def redaction_placeholder
        redaction&.dig(:placeholder) || "[REDACTED]"
      end

      # Returns the maximum value length before truncation
      #
      # @return [Integer, nil] Max length, or nil for no limit
      def redaction_max_value_length
        redaction&.dig(:max_value_length)
      end

      # Returns whether multi-tenancy is enabled
      #
      # @return [Boolean] true if multi-tenancy is enabled
      def multi_tenancy_enabled?
        @multi_tenancy_enabled == true
      end

      # Returns the current tenant ID from the resolver
      #
      # @return [String, nil] Current tenant identifier or nil
      def current_tenant_id
        return nil unless multi_tenancy_enabled?

        tenant_resolver&.call
      end
    end
  end
end
