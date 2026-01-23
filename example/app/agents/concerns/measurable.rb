# frozen_string_literal: true

module Concerns
  # Measurable - Tracks execution metrics and performance
  #
  # This concern provides execution methods for measuring and recording
  # performance metrics during agent execution.
  #
  # Example usage:
  #   class MyAgent < ApplicationAgent
  #     include Concerns::Measurable::Execution
  #
  #     def call
  #       measure_execution do
  #         record_metric(:input_length, user_prompt.length)
  #         # ... perform work ...
  #         result
  #       end
  #     end
  #   end
  #
  #   agent = MyAgent.new(query: "test")
  #   result = agent.call
  #   agent.execution_metrics
  #   # => { duration_ms: 1234, input_length: 4, ... }
  #
  module Measurable
    # Execution module - instance-level metrics methods
    module Execution
      # Wrap execution with timing measurement
      # @yield The block to measure
      # @return [Object] The result of the block
      def measure_execution
        @execution_metrics ||= {}
        @execution_started_at = current_time

        record_metric(:started_at, @execution_started_at.iso8601)
        record_metric(:agent_class, self.class.name)

        result = yield

        @execution_ended_at = current_time
        record_metric(:ended_at, @execution_ended_at.iso8601)
        record_metric(:duration_ms, calculate_duration_ms)
        record_metric(:success, true)

        result
      rescue StandardError => e
        @execution_ended_at = current_time
        record_metric(:ended_at, @execution_ended_at.iso8601)
        record_metric(:duration_ms, calculate_duration_ms)
        record_metric(:success, false)
        record_metric(:error_class, e.class.name)
        record_metric(:error_message, e.message)

        raise
      end

      # Record a named metric with optional tags
      # @param name [Symbol, String] The metric name
      # @param value [Object] The metric value
      # @param tags [Hash] Optional tags for the metric
      def record_metric(name, value, tags = {})
        @execution_metrics ||= {}

        metric_data = if tags.empty?
                        value
                      else
                        { value: value, tags: tags }
                      end

        @execution_metrics[name.to_sym] = metric_data

        # Also record to external metrics system if available
        publish_metric(name, value, tags)
      end

      # Get all collected metrics
      # @return [Hash] The collected metrics
      def execution_metrics
        @execution_metrics ||= {}
        @execution_metrics.dup
      end

      # Check if metrics have been collected
      # @return [Boolean]
      def metrics_collected?
        @execution_metrics&.any? || false
      end

      # Clear all collected metrics
      def clear_metrics!
        @execution_metrics = {}
        @execution_started_at = nil
        @execution_ended_at = nil
      end

      # Get execution duration in milliseconds
      # @return [Float, nil] Duration in milliseconds or nil if not measured
      def execution_duration_ms
        calculate_duration_ms
      end

      # Record token usage metrics
      # @param input_tokens [Integer] Number of input tokens
      # @param output_tokens [Integer] Number of output tokens
      # @param model [String] The model used
      def record_token_usage(input_tokens:, output_tokens:, model: nil)
        record_metric(:input_tokens, input_tokens)
        record_metric(:output_tokens, output_tokens)
        record_metric(:total_tokens, input_tokens + output_tokens)
        record_metric(:model, model) if model
      end

      # Record cache metrics
      # @param hit [Boolean] Whether it was a cache hit
      # @param key [String] The cache key (optional)
      def record_cache_metric(hit:, key: nil)
        record_metric(:cache_hit, hit)
        record_metric(:cache_key, key) if key
      end

      # Get a summary of execution performance
      # @return [Hash] Performance summary
      def performance_summary
        metrics = execution_metrics

        {
          agent: metrics[:agent_class],
          duration_ms: metrics[:duration_ms],
          success: metrics[:success],
          tokens: {
            input: metrics[:input_tokens],
            output: metrics[:output_tokens],
            total: metrics[:total_tokens]
          }.compact,
          cache_hit: metrics[:cache_hit],
          error: metrics[:success] == false ? metrics[:error_class] : nil
        }.compact
      end

      private

      def calculate_duration_ms
        return nil unless @execution_started_at && @execution_ended_at

        ((@execution_ended_at - @execution_started_at) * 1000).round(2)
      end

      # Hook for publishing metrics to external systems
      # Override this method to integrate with StatsD, Prometheus, etc.
      def publish_metric(name, value, tags)
        # Default implementation does nothing
        # Override in your ApplicationAgent or specific agents:
        #
        # def publish_metric(name, value, tags)
        #   StatsD.gauge("agents.#{self.class.name.underscore}.#{name}", value, tags: tags)
        # end
        #
        # Or with Prometheus:
        #
        # def publish_metric(name, value, tags)
        #   AGENT_METRICS.set(value, labels: { agent: self.class.name, metric: name, **tags })
        # end
      end

      # Hook for setting up metrics collection
      # Called when metrics are first initialized
      def setup_metrics
        @execution_metrics = {}
      end

      # Get current time, using Rails Time.current if available
      def current_time
        if defined?(Time.current)
          Time.current
        else
          Time.now
        end
      end
    end
  end
end
