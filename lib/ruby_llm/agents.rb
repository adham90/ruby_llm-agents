# frozen_string_literal: true

require "csv"

require_relative "agents/version"
require_relative "agents/configuration"
require_relative "agents/reliability"
require_relative "agents/redactor"
require_relative "agents/circuit_breaker"
require_relative "agents/budget_tracker"
require_relative "agents/alert_manager"
require_relative "agents/attempt_tracker"
require_relative "agents/inflections" if defined?(Rails)
require_relative "agents/engine" if defined?(Rails::Engine)

module RubyLLM
  # Agent framework for building LLM-powered agents with observability
  #
  # RubyLLM::Agents provides a DSL for creating agents that interact with
  # large language models, with built-in execution tracking, cost monitoring,
  # and a dashboard for observability.
  #
  # @example Basic configuration
  #   RubyLLM::Agents.configure do |config|
  #     config.default_model = "gpt-4o"
  #     config.async_logging = true
  #   end
  #
  # @example Creating an agent
  #   class SearchAgent < ApplicationAgent
  #     model "gpt-4o"
  #     param :query, required: true
  #
  #     def user_prompt
  #       "Search for: #{query}"
  #     end
  #   end
  #
  #   SearchAgent.call(query: "ruby gems")
  #
  # @see RubyLLM::Agents::Base
  # @see RubyLLM::Agents::Configuration
  module Agents
    # Base error class for agent-related exceptions
    class Error < StandardError; end

    class << self
      # Returns the global configuration instance
      #
      # @return [Configuration] The configuration object
      def configuration
        @configuration ||= Configuration.new
      end

      # Yields the configuration for modification
      #
      # @yield [Configuration] The configuration object
      # @return [void]
      # @example
      #   RubyLLM::Agents.configure do |config|
      #     config.default_model = "claude-3-sonnet"
      #   end
      def configure
        yield(configuration)
      end

      # Resets configuration to defaults
      #
      # Primarily used for testing to ensure clean state.
      #
      # @return [Configuration] A new configuration instance
      # @api private
      def reset_configuration!
        @configuration = Configuration.new
      end
    end
  end
end
