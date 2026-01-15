# frozen_string_literal: true

module RubyLLM
  module Agents
    module Reliability
      # Routes execution through fallback models when primary fails
      #
      # Manages the model fallback chain and tracks which models have been tried.
      #
      # @example
      #   routing = FallbackRouting.new("gpt-4o", fallback_models: ["gpt-4o-mini"])
      #   routing.current_model  # => "gpt-4o"
      #   routing.advance!       # => "gpt-4o-mini"
      #   routing.exhausted?     # => false
      #
      # @api private
      class FallbackRouting
        attr_reader :models

        # @param primary_model [String] The primary model identifier
        # @param fallback_models [Array<String>] Fallback model identifiers
        def initialize(primary_model, fallback_models: [])
          @models = [primary_model, *fallback_models].uniq
          @current_index = 0
        end

        # Returns the current model to try
        #
        # @return [String, nil] Model identifier or nil if exhausted
        def current_model
          models[@current_index]
        end

        # Advances to the next fallback model
        #
        # @return [String, nil] Next model or nil if exhausted
        def advance!
          @current_index += 1
          current_model
        end

        # Checks if more models are available after current
        #
        # @return [Boolean] true if more models to try
        def has_more?
          @current_index < models.length - 1
        end

        # Checks if all models have been exhausted
        #
        # @return [Boolean] true if no more models
        def exhausted?
          @current_index >= models.length
        end

        # Resets to the first model
        #
        # @return [void]
        def reset!
          @current_index = 0
        end

        # Returns models that have been tried so far
        #
        # @return [Array<String>] Models already attempted
        def tried_models
          models[0..@current_index]
        end
      end
    end
  end
end
