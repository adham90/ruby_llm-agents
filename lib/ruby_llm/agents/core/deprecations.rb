# frozen_string_literal: true

module RubyLLM
  module Agents
    # Manages deprecation warnings with configurable behavior
    #
    # Provides a centralized mechanism for deprecation warnings that can be
    # configured to raise exceptions in test environments or emit warnings
    # in production.
    #
    # @example Emitting a deprecation warning
    #   Deprecations.warn("cache(ttl) is deprecated, use cache_for(ttl) instead")
    #
    # @example Enabling strict mode in tests
    #   RubyLLM::Agents::Deprecations.raise_on_deprecation = true
    #
    # @api public
    module Deprecations
      # Error raised when deprecation warnings are configured to raise
      #
      # @api public
      class DeprecationError < StandardError; end

      class << self
        # @!attribute [rw] raise_on_deprecation
        #   @return [Boolean] Whether to raise exceptions instead of warnings
        attr_accessor :raise_on_deprecation

        # @!attribute [rw] silenced
        #   @return [Boolean] Whether to silence all deprecation warnings
        attr_accessor :silenced

        # Emits a deprecation warning or raises an error
        #
        # @param message [String] The deprecation message
        # @param callstack [Array<String>] The call stack (defaults to caller)
        # @return [void]
        # @raise [DeprecationError] If raise_on_deprecation is true
        def warn(message, callstack = caller)
          return if silenced

          full_message = "[RubyLLM::Agents DEPRECATION] #{message}"

          if raise_on_deprecation
            raise DeprecationError, full_message
          elsif defined?(Rails) && Rails.respond_to?(:application) && Rails.application
            # Use Rails deprecator if available (Rails 7.1+)
            if Rails.application.respond_to?(:deprecators)
              Rails.application.deprecators[:ruby_llm_agents]&.warn(full_message, callstack) ||
                ::Kernel.warn("#{full_message}\n  #{callstack.first}")
            else
              ::Kernel.warn("#{full_message}\n  #{callstack.first}")
            end
          else
            ::Kernel.warn("#{full_message}\n  #{callstack.first}")
          end
        end

        # Temporarily silence deprecation warnings within a block
        #
        # @yield Block to execute with silenced warnings
        # @return [Object] The return value of the block
        def silence
          old_silenced = silenced
          self.silenced = true
          yield
        ensure
          self.silenced = old_silenced
        end
      end

      # Reset to defaults
      self.raise_on_deprecation = false
      self.silenced = false
    end
  end
end
