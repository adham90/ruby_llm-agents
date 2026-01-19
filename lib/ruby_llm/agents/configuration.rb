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

      # @!attribute [rw] default_retryable_patterns
      #   Default patterns in error messages that indicate retryable errors.
      #   Organized by category for easy customization.
      #   @return [Hash<Symbol, Array<String>>] Categorized patterns
      #   @example
      #     config.default_retryable_patterns = {
      #       rate_limiting: ["rate limit", "429"],
      #       server_errors: ["500", "502", "503"],
      #       capacity: ["overloaded"]
      #     }

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

      # @!attribute [rw] default_thinking
      #   Default thinking/reasoning configuration for all agents.
      #   When set, enables extended thinking for supported models (Claude, Gemini, etc.).
      #   Can be overridden per-agent using the `thinking` DSL method.
      #   @return [Hash, nil] Thinking config with :effort and/or :budget keys (default: nil)
      #   @example Enable medium-effort thinking globally
      #     config.default_thinking = { effort: :medium }
      #   @example Enable high-effort thinking with budget
      #     config.default_thinking = { effort: :high, budget: 10000 }

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

      # @!attribute [rw] tenant_config_resolver
      #   Lambda that returns tenant configuration without querying the database.
      #   Called when resolving tenant budget config. If set, this takes priority
      #   over the TenantBudget database lookup.
      #   @return [Proc, nil] Tenant config resolver lambda (default: nil)
      #   @example Using an external tenant service
      #     config.tenant_config_resolver = ->(tenant_id) {
      #       tenant = Tenant.find(tenant_id)
      #       {
      #         name: tenant.name,
      #         daily_limit: tenant.subscription.daily_budget,
      #         monthly_limit: tenant.subscription.monthly_budget,
      #         daily_token_limit: tenant.subscription.daily_tokens,
      #         monthly_token_limit: tenant.subscription.monthly_tokens,
      #         enforcement: tenant.subscription.hard_limits? ? :hard : :soft
      #       }
      #     }

      # @!attribute [rw] persist_messages_summary
      #   Whether to persist a summary of conversation messages in execution records.
      #   When true, stores message count and first/last messages (truncated).
      #   Set to false to disable message summary persistence.
      #   @return [Boolean] Enable messages summary persistence (default: true)

      # @!attribute [rw] messages_summary_max_length
      #   Maximum character length for message content in the summary.
      #   Content exceeding this length will be truncated with "...".
      #   @return [Integer] Max length for message content (default: 500)

      # @!attribute [rw] default_embedding_model
      #   The default embedding model identifier for all embedders.
      #   Can be overridden per-embedder using the `model` DSL method.
      #   @return [String] Model identifier (default: "text-embedding-3-small")
      #   @example
      #     config.default_embedding_model = "text-embedding-3-large"

      # @!attribute [rw] default_embedding_dimensions
      #   The default vector dimensions for embeddings.
      #   Set to nil to use the model's default dimensions.
      #   Some models (like OpenAI text-embedding-3) support dimension reduction.
      #   @return [Integer, nil] Dimensions or nil for model default (default: nil)
      #   @example
      #     config.default_embedding_dimensions = 512

      # @!attribute [rw] default_embedding_batch_size
      #   The default batch size for embedding operations.
      #   When embedding multiple texts, they are split into batches of this size.
      #   @return [Integer] Batch size (default: 100)
      #   @example
      #     config.default_embedding_batch_size = 50

      # @!attribute [rw] track_embeddings
      #   Whether to track embedding executions in the database.
      #   When enabled, embedding operations are logged like agent executions.
      #   @return [Boolean] Enable embedding tracking (default: true)
      #   @example
      #     config.track_embeddings = false

      # @!attribute [rw] default_moderation_model
      #   The default moderation model identifier for all agents.
      #   Can be overridden per-agent using the `moderation` DSL method.
      #   @return [String] Model identifier (default: "omni-moderation-latest")
      #   @example
      #     config.default_moderation_model = "text-moderation-007"

      # @!attribute [rw] default_moderation_threshold
      #   The default threshold for moderation scores.
      #   Content with scores at or above this threshold will be flagged.
      #   Set to nil to use the provider's default flagging.
      #   @return [Float, nil] Threshold (0.0-1.0) or nil for provider default (default: nil)
      #   @example
      #     config.default_moderation_threshold = 0.8

      # @!attribute [rw] default_moderation_action
      #   The default action when content is flagged.
      #   Can be overridden per-agent using the `moderation` DSL method.
      #   @return [Symbol] Action (:block, :raise, :warn, :log) (default: :block)
      #   @example
      #     config.default_moderation_action = :raise

      # @!attribute [rw] track_moderation
      #   Whether to track moderation executions in the database.
      #   When enabled, moderation operations are logged as executions.
      #   @return [Boolean] Enable moderation tracking (default: true)
      #   @example
      #     config.track_moderation = false

      # Attributes without validation (simple accessors)
      attr_accessor :default_model,
                    :async_logging,
                    :retention_period,
                    :dashboard_parent_controller,
                    :basic_auth_username,
                    :basic_auth_password,
                    :default_fallback_models,
                    :default_total_timeout,
                    :default_streaming,
                    :default_tools,
                    :default_thinking,
                    :alerts,
                    :persist_prompts,
                    :persist_responses,
                    :redaction,
                    :multi_tenancy_enabled,
                    :persist_messages_summary,
                    :default_retryable_patterns,
                    :default_embedding_model,
                    :default_embedding_dimensions,
                    :default_embedding_batch_size,
                    :track_embeddings,
                    :default_moderation_model,
                    :default_moderation_threshold,
                    :default_moderation_action,
                    :track_moderation

      # Attributes with validation (readers only, custom setters below)
      attr_reader :default_temperature,
                  :default_timeout,
                  :anomaly_cost_threshold,
                  :anomaly_duration_threshold,
                  :per_page,
                  :recent_executions_limit,
                  :job_retry_attempts,
                  :messages_summary_max_length,
                  :dashboard_auth,
                  :tenant_resolver,
                  :tenant_config_resolver,
                  :default_retries,
                  :budgets

      attr_writer :cache_store

      # Sets default_temperature with validation
      #
      # @param value [Float] Temperature (0.0 to 2.0)
      # @raise [ArgumentError] If value is outside valid range
      def default_temperature=(value)
        validate_range!(:default_temperature, value, 0.0, 2.0)
        @default_temperature = value
      end

      # Sets default_timeout with validation
      #
      # @param value [Integer] Timeout in seconds (must be > 0)
      # @raise [ArgumentError] If value is not positive
      def default_timeout=(value)
        validate_positive!(:default_timeout, value)
        @default_timeout = value
      end

      # Sets anomaly_cost_threshold with validation
      #
      # @param value [Float] Cost threshold (must be >= 0)
      # @raise [ArgumentError] If value is negative
      def anomaly_cost_threshold=(value)
        validate_non_negative!(:anomaly_cost_threshold, value)
        @anomaly_cost_threshold = value
      end

      # Sets anomaly_duration_threshold with validation
      #
      # @param value [Integer] Duration threshold in ms (must be >= 0)
      # @raise [ArgumentError] If value is negative
      def anomaly_duration_threshold=(value)
        validate_non_negative!(:anomaly_duration_threshold, value)
        @anomaly_duration_threshold = value
      end

      # Sets per_page with validation
      #
      # @param value [Integer] Records per page (must be > 0)
      # @raise [ArgumentError] If value is not positive
      def per_page=(value)
        validate_positive!(:per_page, value)
        @per_page = value
      end

      # Sets recent_executions_limit with validation
      #
      # @param value [Integer] Limit (must be > 0)
      # @raise [ArgumentError] If value is not positive
      def recent_executions_limit=(value)
        validate_positive!(:recent_executions_limit, value)
        @recent_executions_limit = value
      end

      # Sets job_retry_attempts with validation
      #
      # @param value [Integer] Retry attempts (must be >= 0)
      # @raise [ArgumentError] If value is negative
      def job_retry_attempts=(value)
        validate_non_negative!(:job_retry_attempts, value)
        @job_retry_attempts = value
      end

      # Sets messages_summary_max_length with validation
      #
      # @param value [Integer] Max length (must be > 0)
      # @raise [ArgumentError] If value is not positive
      def messages_summary_max_length=(value)
        validate_positive!(:messages_summary_max_length, value)
        @messages_summary_max_length = value
      end

      # Sets dashboard_auth with validation
      #
      # @param value [Proc, nil] Authentication lambda or nil
      # @raise [ArgumentError] If value is not callable or nil
      def dashboard_auth=(value)
        validate_callable!(:dashboard_auth, value, allow_nil: true)
        @dashboard_auth = value
      end

      # Sets tenant_resolver with validation
      #
      # @param value [Proc] Tenant resolution lambda (must be callable)
      # @raise [ArgumentError] If value is not callable
      def tenant_resolver=(value)
        validate_callable!(:tenant_resolver, value, allow_nil: false)
        @tenant_resolver = value
      end

      # Sets tenant_config_resolver with validation
      #
      # @param value [Proc, nil] Tenant config resolver lambda or nil
      # @raise [ArgumentError] If value is not callable or nil
      def tenant_config_resolver=(value)
        validate_callable!(:tenant_config_resolver, value, allow_nil: true)
        @tenant_config_resolver = value
      end

      # Sets default_retries with validation
      #
      # @param value [Hash] Retry configuration
      # @raise [ArgumentError] If any values are invalid
      def default_retries=(value)
        validate_retries!(value)
        @default_retries = value
      end

      # Sets budgets with validation
      #
      # @param value [Hash, nil] Budget configuration
      # @raise [ArgumentError] If enforcement is invalid
      def budgets=(value)
        validate_budgets!(value)
        @budgets = value
      end

      # Sets default_embedding_batch_size with validation
      #
      # @param value [Integer] Batch size (must be > 0)
      # @raise [ArgumentError] If value is not positive
      def default_embedding_batch_size=(value)
        validate_positive!(:default_embedding_batch_size, value)
        @default_embedding_batch_size = value
      end

      # Sets default_embedding_dimensions with validation
      #
      # @param value [Integer, nil] Dimensions (must be nil or > 0)
      # @raise [ArgumentError] If value is not nil or positive
      def default_embedding_dimensions=(value)
        unless value.nil? || (value.is_a?(Numeric) && value > 0)
          raise ArgumentError, "default_embedding_dimensions must be nil or greater than 0"
        end

        @default_embedding_dimensions = value
      end

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
        @default_retryable_patterns = {
          rate_limiting: ["rate limit", "rate_limit", "too many requests", "429"],
          server_errors: ["500", "502", "503", "504", "service unavailable",
                         "internal server error", "bad gateway", "gateway timeout"],
          capacity: ["overloaded", "capacity"]
        }

        # Streaming, tools, and thinking defaults
        @default_streaming = false
        @default_tools = []
        @default_thinking = nil

        # Governance defaults
        @budgets = nil
        @alerts = nil
        @persist_prompts = true
        @persist_responses = true
        @redaction = nil

        # Multi-tenancy defaults (disabled for backward compatibility)
        @multi_tenancy_enabled = false
        @tenant_resolver = -> { nil }
        @tenant_config_resolver = nil

        # Messages summary defaults
        @persist_messages_summary = true
        @messages_summary_max_length = 500

        # Embedding defaults
        @default_embedding_model = "text-embedding-3-small"
        @default_embedding_dimensions = nil
        @default_embedding_batch_size = 100
        @track_embeddings = true

        # Moderation defaults
        @default_moderation_model = "omni-moderation-latest"
        @default_moderation_threshold = nil
        @default_moderation_action = :block
        @track_moderation = true
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

      # Returns all retryable patterns as a flat array
      #
      # @return [Array<String>] All patterns from all categories
      def all_retryable_patterns
        default_retryable_patterns.values.flatten.uniq
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

      private

      # Validates that a value is within a range
      #
      # @param attr [Symbol] Attribute name for error message
      # @param value [Numeric] Value to validate
      # @param min [Numeric] Minimum value (inclusive)
      # @param max [Numeric] Maximum value (inclusive)
      # @raise [ArgumentError] If value is outside range
      def validate_range!(attr, value, min, max)
        return if value.is_a?(Numeric) && value >= min && value <= max

        raise ArgumentError, "#{attr} must be between #{min} and #{max}"
      end

      # Validates that a value is positive (greater than 0)
      #
      # @param attr [Symbol] Attribute name for error message
      # @param value [Numeric] Value to validate
      # @raise [ArgumentError] If value is not positive
      def validate_positive!(attr, value)
        return if value.is_a?(Numeric) && value > 0

        raise ArgumentError, "#{attr} must be greater than 0"
      end

      # Validates that a value is non-negative (>= 0)
      #
      # @param attr [Symbol] Attribute name for error message
      # @param value [Numeric] Value to validate
      # @raise [ArgumentError] If value is negative
      def validate_non_negative!(attr, value)
        return if value.is_a?(Numeric) && value >= 0

        raise ArgumentError, "#{attr} must be >= 0"
      end

      # Validates that a value is callable (responds to :call)
      #
      # @param attr [Symbol] Attribute name for error message
      # @param value [Object] Value to validate
      # @param allow_nil [Boolean] Whether nil is allowed
      # @raise [ArgumentError] If value is not callable (or nil when allowed)
      def validate_callable!(attr, value, allow_nil:)
        return if allow_nil && value.nil?
        return if value.respond_to?(:call)

        if allow_nil
          raise ArgumentError, "#{attr} must be callable or nil"
        else
          raise ArgumentError, "#{attr} must be callable"
        end
      end

      # Validates retries configuration hash
      #
      # @param value [Hash] Retries configuration
      # @raise [ArgumentError] If any values are invalid
      def validate_retries!(value)
        return unless value.is_a?(Hash)

        if value.key?(:backoff) && ![:exponential, :constant].include?(value[:backoff])
          raise ArgumentError, "default_retries[:backoff] must be :exponential or :constant"
        end

        if value.key?(:base) && (!value[:base].is_a?(Numeric) || value[:base] <= 0)
          raise ArgumentError, "default_retries[:base] must be greater than 0"
        end

        if value.key?(:max_delay) && (!value[:max_delay].is_a?(Numeric) || value[:max_delay] <= 0)
          raise ArgumentError, "default_retries[:max_delay] must be greater than 0"
        end
      end

      # Validates budgets configuration hash
      #
      # @param value [Hash, nil] Budgets configuration
      # @raise [ArgumentError] If enforcement is invalid
      def validate_budgets!(value)
        return if value.nil?
        return unless value.is_a?(Hash)

        if value.key?(:enforcement) && ![:none, :soft, :hard].include?(value[:enforcement])
          raise ArgumentError, "budgets[:enforcement] must be :none, :soft, or :hard"
        end
      end
    end
  end
end
