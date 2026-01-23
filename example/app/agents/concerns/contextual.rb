# frozen_string_literal: true

module Concerns
  # Contextual - Inject user/request context into agent prompts
  #
  # This concern provides DSL methods for configuring context sources
  # and execution methods for resolving and formatting context.
  #
  # Example usage:
  #   class MyAgent < ApplicationAgent
  #     extend Concerns::Contextual::DSL
  #     include Concerns::Contextual::Execution
  #
  #     context_from :current_user, :request
  #     context_includes :user_id, :user_name, :locale
  #     default_context timezone: "UTC", locale: "en"
  #   end
  #
  #   agent = MyAgent.new(
  #     query: "Hello",
  #     current_user: OpenStruct.new(id: 1, name: "Alice"),
  #     request: { locale: "fr" }
  #   )
  #   agent.resolved_context
  #   # => { user_id: 1, user_name: "Alice", locale: "fr", timezone: "UTC" }
  #
  module Contextual
    # DSL module - class-level context configuration
    module DSL
      VALID_SOURCES = %i[current_user request options session params].freeze

      # Specify context sources to extract data from
      # @param sources [Array<Symbol>] Sources like :current_user, :request, :options
      def context_from(*sources)
        if sources.any?
          invalid = sources - VALID_SOURCES
          if invalid.any?
            raise ArgumentError, "Invalid context sources: #{invalid.join(', ')}. Valid sources: #{VALID_SOURCES.join(', ')}"
          end

          @context_sources = sources
        else
          @context_sources || inherited_context_config(:context_sources) || []
        end
      end

      # Specify which fields to include from context sources
      # @param fields [Array<Symbol>] Field names to include
      def context_includes(*fields)
        if fields.any?
          @context_fields = fields
        else
          @context_fields || inherited_context_config(:context_fields) || []
        end
      end

      # Set default context values
      # @param defaults [Hash] Default values for context fields
      def default_context(defaults = nil)
        if defaults
          @default_context = defaults
        else
          merged_defaults = {}
          merged_defaults.merge!(inherited_context_config(:default_context) || {})
          merged_defaults.merge!(@default_context || {})
          merged_defaults
        end
      end

      # Define a context transformation
      # @param field [Symbol] The field to transform
      # @param block [Proc] The transformation block
      def transform_context(field, &block)
        @context_transforms ||= {}
        @context_transforms[field] = block
      end

      # Get context transforms
      def context_transforms
        inherited = inherited_context_config(:context_transforms) || {}
        inherited.merge(@context_transforms || {})
      end

      # Get full context configuration
      def context_config
        {
          sources: context_from,
          fields: context_includes,
          defaults: default_context,
          transforms: context_transforms
        }
      end

      # Check if context is configured
      def context_configured?
        context_from.any? || context_includes.any?
      end

      private

      def inherited_context_config(attribute)
        return nil unless superclass.respond_to?(attribute, true)

        superclass.send(attribute)
      rescue StandardError
        nil
      end
    end

    # Execution module - instance-level context methods
    module Execution
      # Resolve and merge context from all sources
      # @return [Hash] Merged context data
      def resolved_context
        @resolved_context ||= build_resolved_context
      end

      # Generate a context prefix for system prompts
      # @return [String] Formatted context for prompt injection
      def context_prompt_prefix
        ctx = resolved_context
        return "" if ctx.empty?

        lines = ["Context:"]
        ctx.each do |key, value|
          formatted_key = key.to_s.tr("_", " ").capitalize
          lines << "- #{formatted_key}: #{value}"
        end
        lines.join("\n")
      end

      # Get context as a formatted string
      # @param format [Symbol] Output format (:text, :json, :yaml)
      # @return [String]
      def context_as(format = :text)
        ctx = resolved_context

        case format
        when :json
          ctx.to_json
        when :yaml
          ctx.to_yaml
        when :text
          context_prompt_prefix
        else
          ctx.to_s
        end
      end

      # Check if a specific context field is present
      # @param field [Symbol] The field to check
      # @return [Boolean]
      def context_has?(field)
        resolved_context.key?(field)
      end

      # Get a specific context value
      # @param field [Symbol] The field to get
      # @param default [Object] Default value if not present
      # @return [Object]
      def context_get(field, default = nil)
        resolved_context.fetch(field, default)
      end

      # Clear cached context (useful if underlying data changes)
      def clear_context_cache!
        @resolved_context = nil
      end

      # Override context values at runtime
      # @param overrides [Hash] Values to override
      # @return [Hash] The updated context
      def with_context(**overrides)
        @context_overrides = (@context_overrides || {}).merge(overrides)
        clear_context_cache!
        resolved_context
      end

      private

      def build_resolved_context
        config = self.class.context_config
        context = {}

        # Apply defaults first
        context.merge!(config[:defaults])

        # Extract from sources
        config[:sources].each do |source|
          context.merge!(extract_from_source(source, config[:fields]))
        end

        # Apply transforms
        config[:transforms].each do |field, transform|
          context[field] = transform.call(context[field]) if context.key?(field)
        end

        # Apply runtime overrides
        context.merge!(@context_overrides || {})

        # Filter to only include configured fields if specified
        if config[:fields].any?
          context.select { |k, _| config[:fields].include?(k) }
        else
          context
        end
      end

      def extract_from_source(source, fields)
        source_data = get_source_data(source)
        return {} unless source_data

        extracted = {}

        fields.each do |field|
          value = extract_field_from_source(source_data, field, source)
          extracted[field] = value unless value.nil?
        end

        extracted
      end

      def get_source_data(source)
        case source
        when :current_user
          @current_user || @options&.dig(:current_user)
        when :request
          @request || @options&.dig(:request)
        when :session
          @session || @options&.dig(:session)
        when :params
          @params || @options&.dig(:params)
        when :options
          @options
        end
      end

      def extract_field_from_source(source_data, field, source_type)
        # Try different extraction methods based on source type
        prefixed_field = "#{source_type}_#{field}".to_sym
        unprefixed_field = field.to_s.delete_prefix("#{source_type}_").to_sym

        # First try the exact field name
        value = try_extract(source_data, field)
        return value unless value.nil?

        # Try without source prefix (e.g., :user_id -> :id for current_user source)
        if field.to_s.start_with?("#{source_type}_")
          value = try_extract(source_data, unprefixed_field)
          return value unless value.nil?
        end

        # Try extracting :id, :name etc. and mapping to user_id, user_name
        base_field = field.to_s.delete_prefix("#{source_type}_").delete_prefix("user_").to_sym
        try_extract(source_data, base_field)
      end

      def try_extract(source_data, field)
        if source_data.respond_to?(field)
          source_data.send(field)
        elsif source_data.is_a?(Hash)
          source_data[field] || source_data[field.to_s]
        end
      end
    end
  end
end
