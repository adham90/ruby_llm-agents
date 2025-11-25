# frozen_string_literal: true

module RubyLLM
  module Agents
    class Configuration
      attr_accessor :default_model,
                    :default_temperature,
                    :default_timeout,
                    :async_logging,
                    :retention_period,
                    :anomaly_cost_threshold,
                    :anomaly_duration_threshold,
                    :dashboard_auth,
                    :dashboard_parent_controller

      attr_writer :cache_store

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
      end

      def cache_store
        @cache_store || Rails.cache
      end
    end
  end
end
