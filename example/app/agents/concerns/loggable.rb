# frozen_string_literal: true

module Concerns
  # Loggable - Adds structured logging to agent execution
  #
  # This concern provides DSL methods for configuring logging behavior
  # and execution methods for logging before/after agent execution.
  #
  # Example usage:
  #   class MyAgent < ApplicationAgent
  #     extend Concerns::Loggable::DSL
  #     include Concerns::Loggable::Execution
  #
  #     log_level :info
  #     log_format :detailed
  #     log_include :input, :duration, :tokens
  #   end
  #
  module Loggable
    # DSL module - class-level configuration methods
    module DSL
      VALID_LEVELS = %i[debug info warn error].freeze
      VALID_FORMATS = %i[simple detailed json].freeze
      VALID_FIELDS = %i[input output duration tokens model timestamp].freeze

      # Set the logging level
      # @param level [Symbol] One of :debug, :info, :warn, :error
      def log_level(level = nil)
        if level
          unless VALID_LEVELS.include?(level)
            raise ArgumentError, "Invalid log level: #{level}. Valid levels: #{VALID_LEVELS.join(', ')}"
          end

          @log_level = level
        else
          @log_level || inherited_log_config(:log_level) || :info
        end
      end

      # Set the logging format
      # @param format [Symbol] One of :simple, :detailed, :json
      def log_format(format = nil)
        if format
          unless VALID_FORMATS.include?(format)
            raise ArgumentError, "Invalid log format: #{format}. Valid formats: #{VALID_FORMATS.join(', ')}"
          end

          @log_format = format
        else
          @log_format || inherited_log_config(:log_format) || :simple
        end
      end

      # Specify which fields to include in log output
      # @param fields [Array<Symbol>] Fields to log (e.g., :input, :duration, :tokens)
      def log_include(*fields)
        if fields.any?
          invalid = fields - VALID_FIELDS
          if invalid.any?
            raise ArgumentError, "Invalid log fields: #{invalid.join(', ')}. Valid fields: #{VALID_FIELDS.join(', ')}"
          end

          @log_include_fields = fields
        else
          @log_include_fields || inherited_log_config(:log_include_fields) || %i[duration]
        end
      end

      # Check if logging is enabled
      def logging_enabled?
        @logging_enabled != false && inherited_log_config(:logging_enabled) != false
      end

      # Disable logging for this agent
      def disable_logging!
        @logging_enabled = false
      end

      # Enable logging for this agent
      def enable_logging!
        @logging_enabled = true
      end

      # Get the full logging configuration
      def log_config
        {
          level: log_level,
          format: log_format,
          fields: log_include,
          enabled: logging_enabled?
        }
      end

      private

      def inherited_log_config(attribute)
        return nil unless superclass.respond_to?(attribute, true)

        superclass.send(attribute)
      rescue StandardError
        nil
      end
    end

    # Execution module - instance-level logging methods
    module Execution
      # Log before execution starts
      # @param input [String, Hash] The input being processed
      def log_before_execution(input = nil)
        return unless logging_enabled?

        data = build_log_data(:before, input: input)
        write_log(:before, data)
      end

      # Log after execution completes
      # @param result [Object] The execution result
      # @param started_at [Time] When execution started
      # @param tokens [Hash] Token usage data (optional)
      def log_after_execution(result, started_at: nil, tokens: nil)
        return unless logging_enabled?

        data = build_log_data(:after,
                              output: result,
                              started_at: started_at,
                              tokens: tokens)
        write_log(:after, data)
      end

      # Log an error during execution
      # @param error [Exception] The error that occurred
      # @param started_at [Time] When execution started
      def log_error(error, started_at: nil)
        return unless logging_enabled?

        data = build_log_data(:error,
                              error: error,
                              started_at: started_at)
        write_log(:error, data)
      end

      private

      def logging_enabled?
        self.class.logging_enabled?
      end

      def log_config
        self.class.log_config
      end

      def build_log_data(phase, input: nil, output: nil, started_at: nil, tokens: nil, error: nil)
        fields = log_config[:fields]
        data = {
          agent: self.class.name,
          phase: phase,
          timestamp: current_time
        }

        data[:input] = sanitize_for_log(input) if fields.include?(:input) && input
        data[:output] = sanitize_for_log(output) if fields.include?(:output) && output
        data[:duration] = calculate_duration(started_at) if fields.include?(:duration) && started_at
        data[:tokens] = tokens if fields.include?(:tokens) && tokens
        data[:model] = resolve_log_model if fields.include?(:model)
        data[:error] = { class: error.class.name, message: error.message } if error

        data
      end

      def sanitize_for_log(value)
        case value
        when String
          value.length > 500 ? "#{value[0, 500]}..." : value
        when Hash
          value.transform_values { |v| sanitize_for_log(v) }
        when Array
          value.map { |v| sanitize_for_log(v) }
        else
          value.to_s
        end
      end

      def calculate_duration(started_at)
        return nil unless started_at

        ((current_time - started_at) * 1000).round(2)
      end

      # Get current time, using Rails Time.current if available
      def current_time
        if defined?(Time.current)
          Time.current
        else
          Time.now
        end
      end

      def resolve_log_model
        return self.class.model if self.class.respond_to?(:model)

        "unknown"
      end

      def write_log(phase, data)
        formatted = format_log_output(data)

        case log_config[:level]
        when :debug
          logger.debug(formatted)
        when :info
          logger.info(formatted)
        when :warn
          logger.warn(formatted)
        when :error
          logger.error(formatted)
        end
      end

      def format_log_output(data)
        case log_config[:format]
        when :simple
          format_simple(data)
        when :detailed
          format_detailed(data)
        when :json
          format_json(data)
        end
      end

      def format_simple(data)
        parts = ["[#{data[:agent]}]"]
        parts << "[#{data[:phase]}]"
        parts << "duration=#{data[:duration]}ms" if data[:duration]
        parts << "error=#{data.dig(:error, :class)}" if data[:error]
        parts.join(" ")
      end

      def format_detailed(data)
        lines = ["=" * 60]
        lines << "Agent: #{data[:agent]}"
        lines << "Phase: #{data[:phase]}"
        lines << "Timestamp: #{data[:timestamp]}"
        lines << "Model: #{data[:model]}" if data[:model]
        lines << "Duration: #{data[:duration]}ms" if data[:duration]
        lines << "Tokens: #{data[:tokens]}" if data[:tokens]
        lines << "Input: #{data[:input]}" if data[:input]
        lines << "Output: #{data[:output]}" if data[:output]
        if data[:error]
          lines << "Error: #{data[:error][:class]}"
          lines << "Message: #{data[:error][:message]}"
        end
        lines << "=" * 60
        lines.join("\n")
      end

      def format_json(data)
        data.to_json
      end

      def logger
        @logger ||= if defined?(Rails) && Rails.respond_to?(:logger)
                      Rails.logger
                    else
                      require "logger"
                      Logger.new($stdout)
                    end
      end
    end
  end
end
