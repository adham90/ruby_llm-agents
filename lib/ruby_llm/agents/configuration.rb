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
                    :job_retry_attempts

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
      end

      # Returns the configured cache store, falling back to Rails.cache
      #
      # @return [ActiveSupport::Cache::Store] The cache store instance
      # @example Using a custom cache store
      #   config.cache_store = ActiveSupport::Cache::MemoryStore.new
      def cache_store
        @cache_store || Rails.cache
      end
    end
  end
end
