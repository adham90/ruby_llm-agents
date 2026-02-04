# frozen_string_literal: true

module RubyLLM
  module Agents
    module Concerns
      # Shared DSL methods for all image operation classes
      #
      # Provides common configuration options like model,
      # description, and caching that are shared across ImageVariator,
      # ImageEditor, ImageTransformer, and ImageUpscaler.
      #
      module ImageOperationDSL
        # Set or get the model
        #
        # @param value [String, nil] Model identifier
        # @return [String] The model to use
        def model(value = nil)
          if value
            @model = value
          else
            @model || inherited_or_default(:model, default_model)
          end
        end

        # Set or get the description
        #
        # @param value [String, nil] Description
        # @return [String, nil] The description
        def description(value = nil)
          if value
            @description = value
          else
            @description || inherited_or_default(:description, nil)
          end
        end

        # Enable caching with the given TTL
        #
        # @param ttl [ActiveSupport::Duration, Integer] Cache duration
        def cache_for(ttl)
          @cache_ttl = ttl
        end

        # Get the cache TTL
        #
        # @return [ActiveSupport::Duration, Integer, nil] The cache TTL
        def cache_ttl
          @cache_ttl || inherited_or_default(:cache_ttl, nil)
        end

        # Check if caching is enabled
        #
        # @return [Boolean] true if caching is enabled
        def cache_enabled?
          !cache_ttl.nil?
        end

        private

        def config
          RubyLLM::Agents.configuration
        end

        def inherited_or_default(attribute, default)
          if superclass.respond_to?(attribute)
            superclass.public_send(attribute)
          else
            default
          end
        end

        # Override in submodules to provide default model
        def default_model
          config.default_image_model
        end
      end
    end
  end
end
