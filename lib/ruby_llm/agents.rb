# frozen_string_literal: true

require "csv"
require "ruby_llm"

# Core
require_relative "agents/core/version"
require_relative "agents/core/configuration"
require_relative "agents/core/deprecations"
require_relative "agents/core/errors"
require_relative "agents/core/resolved_config"
require_relative "agents/core/llm_tenant"

# Infrastructure - Reliability
require_relative "agents/infrastructure/reliability"
require_relative "agents/infrastructure/reliability/retry_strategy"
require_relative "agents/infrastructure/reliability/fallback_routing"
require_relative "agents/infrastructure/reliability/breaker_manager"
require_relative "agents/infrastructure/reliability/execution_constraints"
require_relative "agents/infrastructure/reliability/executor"

# Pipeline infrastructure (middleware-based execution)
require_relative "agents/pipeline"

# DSL modules for agent configuration
require_relative "agents/dsl"

# BaseAgent - new middleware-based agent architecture
require_relative "agents/base_agent"

# Infrastructure - Budget & Utilities
require_relative "agents/infrastructure/redactor"
require_relative "agents/infrastructure/circuit_breaker"
require_relative "agents/infrastructure/budget_tracker"
require_relative "agents/infrastructure/alert_manager"
require_relative "agents/infrastructure/attempt_tracker"
require_relative "agents/infrastructure/cache_helper"
require_relative "agents/infrastructure/budget/budget_query"
require_relative "agents/infrastructure/budget/config_resolver"
require_relative "agents/infrastructure/budget/forecaster"
require_relative "agents/infrastructure/budget/spend_recorder"

# Results
require_relative "agents/results/base"
require_relative "agents/results/embedding_result"
require_relative "agents/results/moderation_result"
require_relative "agents/results/transcription_result"
require_relative "agents/results/speech_result"
require_relative "agents/results/image_generation_result"
require_relative "agents/results/image_variation_result"
require_relative "agents/results/image_edit_result"
require_relative "agents/results/image_transform_result"
require_relative "agents/results/image_upscale_result"
require_relative "agents/results/image_analysis_result"
require_relative "agents/results/background_removal_result"
require_relative "agents/results/image_pipeline_result"

# Image concerns (shared DSL/execution for image operations)
require_relative "agents/image/concerns/image_operation_dsl"
require_relative "agents/image/concerns/image_operation_execution"

# Text agents
require_relative "agents/text/embedder"
require_relative "agents/text/moderator"

# Audio agents
require_relative "agents/audio/transcriber"
require_relative "agents/audio/speaker"

# Image agents
require_relative "agents/image/generator"
require_relative "agents/image/variator"
require_relative "agents/image/editor"
require_relative "agents/image/transformer"
require_relative "agents/image/upscaler"
require_relative "agents/image/analyzer"
require_relative "agents/image/background_remover"
require_relative "agents/image/pipeline"

# Workflow
require_relative "agents/workflow/async"
require_relative "agents/workflow/orchestrator"
require_relative "agents/workflow/async_executor"

# Rails integration
if defined?(Rails)
  require_relative "agents/core/inflections"
  require_relative "agents/core/instrumentation"
  require_relative "agents/infrastructure/execution_logger_job"
end
require_relative "agents/rails/engine" if defined?(Rails::Engine)

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
