# frozen_string_literal: true

module RubyLLM
  module Agents
    # Unified redaction utility for PII and sensitive data
    #
    # Provides methods to redact sensitive information from hashes, arrays, and strings
    # based on configurable field names and regex patterns.
    #
    # @example Redacting a hash
    #   Redactor.redact({ password: "secret", name: "John" })
    #   # => { password: "[REDACTED]", name: "John" }
    #
    # @example Redacting a string with patterns
    #   Redactor.redact_string("SSN: 123-45-6789")
    #   # => "SSN: [REDACTED]"
    #
    # @see RubyLLM::Agents::Configuration
    # @api public
    module Redactor
      class << self
        # Redacts sensitive data from an object (hash, array, or primitive)
        #
        # @param obj [Object] The object to redact
        # @param config [Configuration, nil] Optional configuration override
        # @return [Object] The redacted object (new object, original not modified)
        def redact(obj, config = nil)
          config ||= RubyLLM::Agents.configuration

          case obj
          when Hash
            redact_hash(obj, config)
          when Array
            redact_array(obj, config)
          when String
            redact_string(obj, config)
          else
            obj
          end
        end

        # Redacts sensitive data from a string using configured patterns
        #
        # @param str [String, nil] The string to redact
        # @param config [Configuration, nil] Optional configuration override
        # @return [String, nil] The redacted string
        def redact_string(str, config = nil)
          return nil if str.nil?
          return str unless str.is_a?(String)

          config ||= RubyLLM::Agents.configuration
          result = str.dup

          # Apply pattern-based redaction
          config.redaction_patterns.each do |pattern|
            result = result.gsub(pattern, config.redaction_placeholder)
          end

          # Truncate if max length is configured
          max_length = config.redaction_max_value_length
          if max_length && result.length > max_length
            result = result[0, max_length] + "..."
          end

          result
        end

        private

        # Redacts sensitive fields from a hash
        #
        # @param hash [Hash] The hash to redact
        # @param config [Configuration] The configuration
        # @return [Hash] The redacted hash
        def redact_hash(hash, config)
          hash.each_with_object({}) do |(key, value), result|
            key_str = key.to_s.downcase

            if sensitive_field?(key_str, config)
              result[key] = config.redaction_placeholder
            else
              result[key] = redact_value(value, config)
            end
          end
        end

        # Redacts sensitive values from an array
        #
        # @param array [Array] The array to redact
        # @param config [Configuration] The configuration
        # @return [Array] The redacted array
        def redact_array(array, config)
          array.map { |item| redact(item, config) }
        end

        # Redacts a single value based on its type
        #
        # @param value [Object] The value to redact
        # @param config [Configuration] The configuration
        # @return [Object] The redacted value
        def redact_value(value, config)
          case value
          when Hash
            redact_hash(value, config)
          when Array
            redact_array(value, config)
          when String
            redact_string(value, config)
          when defined?(ActiveRecord::Base) && ActiveRecord::Base
            # Convert ActiveRecord objects to safe references
            { id: value&.id, type: value&.class&.name }
          else
            value
          end
        end

        # Checks if a field name is sensitive
        #
        # @param field_name [String] The field name to check (lowercase)
        # @param config [Configuration] The configuration
        # @return [Boolean] true if the field should be redacted
        def sensitive_field?(field_name, config)
          config.redaction_fields.any? do |sensitive|
            field_name.include?(sensitive.downcase)
          end
        end
      end
    end
  end
end
