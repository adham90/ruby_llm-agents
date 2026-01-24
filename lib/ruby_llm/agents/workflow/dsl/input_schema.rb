# frozen_string_literal: true

module RubyLLM
  module Agents
    class Workflow
      module DSL
        # Defines and validates input schema for a workflow
        #
        # Provides a DSL for declaring required and optional input parameters
        # with type validation and default values.
        #
        # @example Defining input schema
        #   class MyWorkflow < RubyLLM::Agents::Workflow
        #     input do
        #       required :order_id, String
        #       required :user_id, Integer
        #       optional :priority, String, default: "normal"
        #       optional :expedited, Boolean, default: false
        #     end
        #   end
        #
        # @api private
        class InputSchema
          # Error raised when input validation fails
          class ValidationError < StandardError
            attr_reader :errors

            def initialize(message, errors: [])
              super(message)
              @errors = errors
            end
          end

          # Represents a single field in the schema
          class Field
            attr_reader :name, :type, :required, :default, :options

            def initialize(name, type, required:, default: nil, **options)
              @name = name
              @type = type
              @required = required
              @default = default
              @options = options
            end

            def required?
              @required
            end

            def optional?
              !@required
            end

            def has_default?
              !@default.nil? || @options.key?(:default)
            end

            def validate(value)
              errors = []

              # Check required
              if required? && value.nil?
                errors << "#{name} is required"
                return errors
              end

              # Skip validation for nil optional values
              return errors if value.nil? && optional?

              # Type validation
              unless valid_type?(value)
                errors << "#{name} must be a #{type_description}"
              end

              # Enum validation
              if options[:in] && !options[:in].include?(value)
                errors << "#{name} must be one of: #{options[:in].join(', ')}"
              end

              # Custom validation
              if options[:validate] && !options[:validate].call(value)
                errors << "#{name} failed custom validation"
              end

              errors
            end

            def to_h
              {
                name: name,
                type: type_description,
                required: required?,
                default: default,
                options: options.except(:validate)
              }.compact
            end

            private

            def valid_type?(value)
              return true if type.nil?

              case type
              when :boolean, "Boolean"
                value == true || value == false
              else
                value.is_a?(type)
              end
            end

            def type_description
              case type
              when :boolean, "Boolean"
                "Boolean"
              when Class
                type.name
              else
                type.to_s
              end
            end
          end

          def initialize
            @fields = {}
          end

          # Defines a required field
          #
          # @param name [Symbol] Field name
          # @param type [Class, Symbol] Expected type
          # @param options [Hash] Additional options
          # @return [void]
          def required(name, type = nil, **options)
            @fields[name] = Field.new(name, type, required: true, **options)
          end

          # Defines an optional field
          #
          # @param name [Symbol] Field name
          # @param type [Class, Symbol] Expected type
          # @param default [Object] Default value
          # @param options [Hash] Additional options
          # @return [void]
          def optional(name, type = nil, default: nil, **options)
            @fields[name] = Field.new(name, type, required: false, default: default, **options)
          end

          # Returns all fields
          #
          # @return [Hash<Symbol, Field>]
          attr_reader :fields

          # Returns required field names
          #
          # @return [Array<Symbol>]
          def required_fields
            @fields.select { |_, f| f.required? }.keys
          end

          # Returns optional field names
          #
          # @return [Array<Symbol>]
          def optional_fields
            @fields.select { |_, f| f.optional? }.keys
          end

          # Validates input against the schema
          #
          # @param input [Hash] Input data to validate
          # @return [Hash] Validated and normalized input
          # @raise [ValidationError] If validation fails
          def validate!(input)
            errors = []
            normalized = {}

            @fields.each do |name, field|
              value = input.key?(name) ? input[name] : field.default
              field_errors = field.validate(value)
              errors.concat(field_errors)
              normalized[name] = value unless value.nil? && field.optional?
            end

            # Include any extra fields not in schema
            input.each do |key, value|
              normalized[key] = value unless @fields.key?(key)
            end

            if errors.any?
              raise ValidationError.new(
                "Input validation failed: #{errors.join(', ')}",
                errors: errors
              )
            end

            normalized
          end

          # Applies defaults to input without validation
          #
          # @param input [Hash] Input data
          # @return [Hash] Input with defaults applied
          def apply_defaults(input)
            result = input.dup
            @fields.each do |name, field|
              result[name] = field.default if !result.key?(name) && field.has_default?
            end
            result
          end

          # Converts to hash for serialization
          #
          # @return [Hash]
          def to_h
            {
              fields: @fields.transform_values(&:to_h)
            }
          end

          # Returns whether the schema is empty
          #
          # @return [Boolean]
          def empty?
            @fields.empty?
          end
        end

        # Output schema for workflow results
        #
        # Similar to InputSchema but for validating workflow output.
        class OutputSchema < InputSchema
          # Validates output against the schema
          #
          # @param output [Hash] Output data to validate
          # @return [Hash] Validated output
          # @raise [ValidationError] If validation fails
          def validate!(output)
            output_hash = output.is_a?(Hash) ? output : { result: output }
            super(output_hash)
          end
        end
      end
    end
  end
end
