# frozen_string_literal: true

module Concerns
  # Validatable - Declarative input validation for agents
  #
  # This concern provides DSL methods for declaring validations and
  # execution methods for running validations.
  #
  # Example usage:
  #   class MyAgent < ApplicationAgent
  #     extend Concerns::Validatable::DSL
  #     include Concerns::Validatable::Execution
  #
  #     validates_presence_of :query
  #     validates_length_of :query, min: 3, max: 1000
  #     validates_format_of :email, with: /\A[\w+\-.]+@[a-z\d\-]+(\.[a-z]+)*\.[a-z]+\z/i
  #     validate :status, inclusion: %w[active pending completed]
  #   end
  #
  #   agent = MyAgent.new(query: "hi", email: "bad")
  #   agent.valid?  # => false
  #   agent.validation_errors
  #   # => ["query is too short (minimum 3 characters)", "email has invalid format"]
  #
  module Validatable
    # DSL module - class-level validation declarations
    module DSL
      # Validate that a field is present (not nil, not empty)
      # @param field [Symbol] The field name to validate
      # @param options [Hash] Options (message: custom error message)
      def validates_presence_of(field, **options)
        add_validation(field, :presence, options)
      end

      # Validate field format with a regex pattern
      # @param field [Symbol] The field name to validate
      # @param with [Regexp] The pattern to match
      # @param options [Hash] Options (message: custom error message)
      def validates_format_of(field, with:, **options)
        add_validation(field, :format, options.merge(pattern: with))
      end

      # Validate field length constraints
      # @param field [Symbol] The field name to validate
      # @param min [Integer] Minimum length (optional)
      # @param max [Integer] Maximum length (optional)
      # @param options [Hash] Options (message: custom error message)
      def validates_length_of(field, min: nil, max: nil, **options)
        add_validation(field, :length, options.merge(min: min, max: max))
      end

      # Validate field with custom constraints
      # @param field [Symbol] The field name to validate
      # @param inclusion [Array] Valid values for the field (optional)
      # @param exclusion [Array] Invalid values for the field (optional)
      # @param numericality [Boolean, Hash] Numeric validation (optional)
      # @param options [Hash] Other options
      def validate(field, inclusion: nil, exclusion: nil, numericality: nil, **options)
        add_validation(field, :inclusion, options.merge(values: inclusion)) if inclusion
        add_validation(field, :exclusion, options.merge(values: exclusion)) if exclusion
        add_validation(field, :numericality, options.merge(constraints: numericality)) if numericality
      end

      # Add a custom validation method
      # @param method_name [Symbol] The method to call for validation
      def validates_with(method_name)
        add_validation(nil, :custom, method: method_name)
      end

      # Get all validations for this class
      def validations
        @validations ||= []
        inherited_validations + @validations
      end

      # Check if any validations are defined
      def validations_defined?
        validations.any?
      end

      private

      def add_validation(field, type, options)
        @validations ||= []
        @validations << {
          field: field,
          type: type,
          options: options
        }
      end

      def inherited_validations
        return [] unless superclass.respond_to?(:validations)

        superclass.validations
      rescue StandardError
        []
      end
    end

    # Execution module - instance-level validation methods
    module Execution
      # Run all validations and raise on failure
      # @raise [ValidationError] If any validation fails
      def validate!
        return true if valid?

        raise ValidationError, validation_errors.join(', ')
      end

      # Check if all validations pass
      # @return [Boolean]
      def valid?
        @validation_errors = []
        run_validations
        @validation_errors.empty?
      end

      # Get all validation error messages
      # @return [Array<String>]
      def validation_errors
        @validation_errors ||= []
        @validation_errors.dup
      end

      # Check if there are any validation errors
      # @return [Boolean]
      def invalid?
        !valid?
      end

      # Custom error class for validation failures
      class ValidationError < StandardError; end

      private

      def run_validations
        self.class.validations.each do |validation|
          case validation[:type]
          when :presence
            validate_presence(validation[:field], validation[:options])
          when :format
            validate_format(validation[:field], validation[:options])
          when :length
            validate_length(validation[:field], validation[:options])
          when :inclusion
            validate_inclusion(validation[:field], validation[:options])
          when :exclusion
            validate_exclusion(validation[:field], validation[:options])
          when :numericality
            validate_numericality(validation[:field], validation[:options])
          when :custom
            validate_custom(validation[:options])
          end
        end
      end

      def validate_presence(field, options)
        value = get_field_value(field)

        return unless value.nil? || (value.respond_to?(:empty?) && value.empty?)

        add_error(field, options[:message] || "#{field} can't be blank")
      end

      def validate_format(field, options)
        value = get_field_value(field)
        return if value.nil? # Skip format validation if value is nil

        pattern = options[:pattern]
        return if value.to_s.match?(pattern)

        add_error(field, options[:message] || "#{field} has invalid format")
      end

      def validate_length(field, options)
        value = get_field_value(field)
        return if value.nil?

        length = value.respond_to?(:length) ? value.length : value.to_s.length
        min = options[:min]
        max = options[:max]

        if min && length < min
          add_error(field, options[:message] || "#{field} is too short (minimum #{min} characters)")
        end

        return unless max && length > max

        add_error(field, options[:message] || "#{field} is too long (maximum #{max} characters)")
      end

      def validate_inclusion(field, options)
        value = get_field_value(field)
        return if value.nil?

        values = options[:values]
        return if values.include?(value)

        add_error(field, options[:message] || "#{field} must be one of: #{values.join(', ')}")
      end

      def validate_exclusion(field, options)
        value = get_field_value(field)
        return if value.nil?

        values = options[:values]
        return unless values.include?(value)

        add_error(field, options[:message] || "#{field} cannot be one of: #{values.join(', ')}")
      end

      def validate_numericality(field, options)
        value = get_field_value(field)
        return if value.nil?

        constraints = options[:constraints]

        unless value.is_a?(Numeric)
          add_error(field, options[:message] || "#{field} must be a number")
          return
        end

        return unless constraints.is_a?(Hash)

        if constraints[:greater_than] && value <= constraints[:greater_than]
          add_error(field, "#{field} must be greater than #{constraints[:greater_than]}")
        end

        if constraints[:greater_than_or_equal_to] && value < constraints[:greater_than_or_equal_to]
          add_error(field, "#{field} must be greater than or equal to #{constraints[:greater_than_or_equal_to]}")
        end

        if constraints[:less_than] && value >= constraints[:less_than]
          add_error(field, "#{field} must be less than #{constraints[:less_than]}")
        end

        if constraints[:less_than_or_equal_to] && value > constraints[:less_than_or_equal_to]
          add_error(field, "#{field} must be less than or equal to #{constraints[:less_than_or_equal_to]}")
        end

        return unless constraints[:equal_to] && value != constraints[:equal_to]

        add_error(field, "#{field} must be equal to #{constraints[:equal_to]}")
      end

      def validate_custom(options)
        method_name = options[:method]
        return unless respond_to?(method_name, true)

        send(method_name)
      end

      def get_field_value(field)
        if respond_to?(field)
          send(field)
        elsif instance_variable_defined?("@#{field}")
          instance_variable_get("@#{field}")
        elsif @options.is_a?(Hash) && @options.key?(field)
          @options[field]
        end
      end

      def add_error(_field, message)
        @validation_errors ||= []
        @validation_errors << message
      end
    end
  end
end
