# frozen_string_literal: true

module RubyLLM
  module Agents
    class Base
      # Class-level DSL for configuring agents
      #
      # Provides methods for setting model, temperature, timeout, caching,
      # reliability, streaming, tools, and parameters.
      module DSL
        # @!visibility private
        VERSION = "1.0"
        # @!visibility private
        CACHE_TTL = 1.hour

        # @!group Configuration DSL

        # Sets or returns the LLM model for this agent class
        #
        # @param value [String, nil] The model identifier to set
        # @return [String] The current model setting
        # @example
        #   model "gpt-4o"
        def model(value = nil)
          @model = value if value
          @model || inherited_or_default(:model, RubyLLM::Agents.configuration.default_model)
        end

        # Sets or returns the temperature for LLM responses
        #
        # @param value [Float, nil] Temperature value (0.0-2.0)
        # @return [Float] The current temperature setting
        # @example
        #   temperature 0.7
        def temperature(value = nil)
          @temperature = value if value
          @temperature || inherited_or_default(:temperature, RubyLLM::Agents.configuration.default_temperature)
        end

        # Sets or returns the version string for cache invalidation
        #
        # @param value [String, nil] Version string
        # @return [String] The current version
        # @example
        #   version "2.0"
        def version(value = nil)
          @version = value if value
          @version || inherited_or_default(:version, VERSION)
        end

        # Sets or returns the timeout in seconds for LLM requests
        #
        # @param value [Integer, nil] Timeout in seconds
        # @return [Integer] The current timeout setting
        # @example
        #   timeout 30
        def timeout(value = nil)
          @timeout = value if value
          @timeout || inherited_or_default(:timeout, RubyLLM::Agents.configuration.default_timeout)
        end

        # @!endgroup

        # @!group Reliability DSL

        # Configures retry behavior for this agent
        #
        # @param max [Integer] Maximum number of retry attempts (default: 0)
        # @param backoff [Symbol] Backoff strategy (:constant or :exponential)
        # @param base [Float] Base delay in seconds
        # @param max_delay [Float] Maximum delay between retries
        # @param on [Array<Class>] Error classes to retry on (extends defaults)
        # @return [Hash] The current retry configuration
        # @example
        #   retries max: 2, backoff: :exponential, base: 0.4, max_delay: 3.0, on: [Timeout::Error]
        def retries(max: nil, backoff: nil, base: nil, max_delay: nil, on: nil)
          if max || backoff || base || max_delay || on
            @retries_config ||= RubyLLM::Agents.configuration.default_retries.dup
            @retries_config[:max] = max if max
            @retries_config[:backoff] = backoff if backoff
            @retries_config[:base] = base if base
            @retries_config[:max_delay] = max_delay if max_delay
            @retries_config[:on] = on if on
          end
          @retries_config || inherited_or_default(:retries_config, RubyLLM::Agents.configuration.default_retries)
        end

        # Returns the retry configuration for this agent
        #
        # @return [Hash, nil] The retry configuration
        def retries_config
          @retries_config || (superclass.respond_to?(:retries_config) ? superclass.retries_config : nil)
        end

        # Sets or returns fallback models to try when primary model fails
        #
        # @param models [Array<String>, nil] Model identifiers to use as fallbacks
        # @return [Array<String>] The current fallback models
        # @example
        #   fallback_models ["gpt-4o-mini", "gpt-4o"]
        def fallback_models(models = nil)
          @fallback_models = models if models
          @fallback_models || inherited_or_default(:fallback_models, RubyLLM::Agents.configuration.default_fallback_models)
        end

        # Sets or returns the total timeout for all retry/fallback attempts
        #
        # @param seconds [Integer, nil] Total timeout in seconds
        # @return [Integer, nil] The current total timeout
        # @example
        #   total_timeout 20
        def total_timeout(seconds = nil)
          @total_timeout = seconds if seconds
          @total_timeout || inherited_or_default(:total_timeout, RubyLLM::Agents.configuration.default_total_timeout)
        end

        # Configures circuit breaker for this agent
        #
        # @param errors [Integer] Number of errors to trigger open state
        # @param within [Integer] Rolling window in seconds
        # @param cooldown [Integer] Cooldown period in seconds when open
        # @return [Hash, nil] The current circuit breaker configuration
        # @example
        #   circuit_breaker errors: 10, within: 60, cooldown: 300
        def circuit_breaker(errors: nil, within: nil, cooldown: nil)
          if errors || within || cooldown
            @circuit_breaker_config ||= { errors: 10, within: 60, cooldown: 300 }
            @circuit_breaker_config[:errors] = errors if errors
            @circuit_breaker_config[:within] = within if within
            @circuit_breaker_config[:cooldown] = cooldown if cooldown
          end
          @circuit_breaker_config || (superclass.respond_to?(:circuit_breaker_config) ? superclass.circuit_breaker_config : nil)
        end

        # Returns the circuit breaker configuration for this agent
        #
        # @return [Hash, nil] The circuit breaker configuration
        def circuit_breaker_config
          @circuit_breaker_config || (superclass.respond_to?(:circuit_breaker_config) ? superclass.circuit_breaker_config : nil)
        end

        # @!endgroup

        # @!group Parameter DSL

        # Defines a parameter for the agent
        #
        # Creates an accessor method for the parameter that retrieves values
        # from the options hash, falling back to the default value.
        #
        # @param name [Symbol] The parameter name
        # @param required [Boolean] Whether the parameter is required
        # @param default [Object, nil] Default value if not provided
        # @return [void]
        # @example
        #   param :query, required: true
        #   param :limit, default: 10
        def param(name, required: false, default: nil)
          @params ||= {}
          @params[name] = { required: required, default: default }
          define_method(name) do
            @options[name] || @options[name.to_s] || self.class.params.dig(name, :default)
          end
        end

        # Returns all defined parameters including inherited ones
        #
        # @return [Hash{Symbol => Hash}] Parameter definitions
        def params
          parent = superclass.respond_to?(:params) ? superclass.params : {}
          parent.merge(@params || {})
        end

        # @!endgroup

        # @!group Caching DSL

        # Enables caching for this agent with optional TTL
        #
        # @param ttl [ActiveSupport::Duration] Time-to-live for cached responses
        # @return [void]
        # @example
        #   cache 1.hour
        def cache(ttl = CACHE_TTL)
          @cache_enabled = true
          @cache_ttl = ttl
        end

        # Returns whether caching is enabled for this agent
        #
        # @return [Boolean] true if caching is enabled
        def cache_enabled?
          @cache_enabled || false
        end

        # Returns the cache TTL for this agent
        #
        # @return [ActiveSupport::Duration] The cache TTL
        def cache_ttl
          @cache_ttl || CACHE_TTL
        end

        # @!endgroup

        # @!group Streaming DSL

        # Enables or returns streaming mode for this agent
        #
        # When streaming is enabled and a block is passed to call,
        # chunks will be yielded to the block as they arrive.
        #
        # @param value [Boolean, nil] Whether to enable streaming
        # @return [Boolean] The current streaming setting
        # @example
        #   streaming true
        def streaming(value = nil)
          @streaming = value unless value.nil?
          return @streaming unless @streaming.nil?

          inherited_or_default(:streaming, RubyLLM::Agents.configuration.default_streaming)
        end

        # @!endgroup

        # @!group Tools DSL

        # Sets or returns the tools available to this agent
        #
        # Tools are RubyLLM::Tool classes that the model can invoke.
        # The agent will automatically execute tool calls and continue
        # until the model produces a final response.
        #
        # @param tool_classes [Array<Class>] Tool classes to make available
        # @return [Array<Class>] The current tools
        # @example Single tool
        #   tools WeatherTool
        # @example Multiple tools
        #   tools WeatherTool, SearchTool, CalculatorTool
        def tools(*tool_classes)
          if tool_classes.any?
            @tools = tool_classes.flatten
          end
          @tools || inherited_or_default(:tools, RubyLLM::Agents.configuration.default_tools)
        end

        # @!endgroup

        private

        # Looks up setting from superclass or uses default
        #
        # @param method [Symbol] The method to call on superclass
        # @param default [Object] Default value if not found
        # @return [Object] The resolved value
        def inherited_or_default(method, default)
          superclass.respond_to?(method) ? superclass.send(method) : default
        end
      end
    end
  end
end
