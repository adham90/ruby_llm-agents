# frozen_string_literal: true

module RubyLLM
  module Agents
    module DSL
      # Base DSL available to all agents.
      #
      # Provides common configuration methods that every agent type needs:
      # - model: The LLM model to use
      # - version: Cache invalidation version
      # - description: Human-readable description
      # - timeout: Request timeout
      #
      # @example Basic usage
      #   class MyAgent < RubyLLM::Agents::BaseAgent
      #     extend DSL::Base
      #
      #     model "gpt-4o"
      #     version "2.0"
      #     description "A helpful agent"
      #   end
      #
      module Base
        # @!group Configuration DSL

        # Sets or returns the LLM model for this agent class
        #
        # @param value [String, nil] The model identifier to set
        # @return [String] The current model setting
        # @example
        #   model "gpt-4o"
        def model(value = nil)
          @model = value if value
          @model || inherited_or_default(:model, default_model)
        end

        # Sets or returns the version string for cache invalidation
        #
        # Change this when you want to invalidate cached results
        # (e.g., after changing prompts or behavior).
        #
        # @param value [String, nil] Version string
        # @return [String] The current version
        # @example
        #   version "2.0"
        def version(value = nil)
          @version = value if value
          @version || inherited_or_default(:version, "1.0")
        end

        # Sets or returns the description for this agent class
        #
        # Useful for documentation and tool registration.
        #
        # @param value [String, nil] The description text
        # @return [String, nil] The current description
        # @example
        #   description "Searches the knowledge base for relevant documents"
        def description(value = nil)
          @description = value if value
          @description || inherited_or_default(:description, nil)
        end

        # Sets or returns the timeout in seconds for LLM requests
        #
        # @param value [Integer, nil] Timeout in seconds
        # @return [Integer] The current timeout setting
        # @example
        #   timeout 30
        def timeout(value = nil)
          @timeout = value if value
          @timeout || inherited_or_default(:timeout, default_timeout)
        end

        # @!endgroup

        private

        # Looks up setting from superclass or uses default
        #
        # @param method [Symbol] The method to call on superclass
        # @param default [Object] Default value if not found
        # @return [Object] The resolved value
        def inherited_or_default(method, default)
          return default unless superclass.respond_to?(method)

          superclass.send(method)
        end

        # Returns the default model from configuration
        #
        # @return [String] The default model
        def default_model
          RubyLLM::Agents.configuration.default_model
        rescue StandardError
          "gpt-4o"
        end

        # Returns the default timeout from configuration
        #
        # @return [Integer] The default timeout
        def default_timeout
          RubyLLM::Agents.configuration.default_timeout
        rescue StandardError
          120
        end
      end
    end
  end
end
