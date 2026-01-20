# frozen_string_literal: true

module RubyLLM
  module Agents
    # Background job for logging agent executions to the database
    #
    # Called automatically after each agent execution to create records,
    # calculate costs, and detect anomalies.
    #
    # @example Configuration
    #   RubyLLM::Agents.configure do |config|
    #     config.anomaly_cost_threshold = 5.00       # Log if cost > $5
    #     config.anomaly_duration_threshold = 10_000 # Log if duration > 10s
    #   end
    #
    # @see RubyLLM::Agents::Instrumentation
    # @api private
    class ExecutionLoggerJob < ActiveJob::Base
      queue_as :default

      retry_on StandardError, wait: :polynomially_longer, attempts: 3

      # Creates execution record and performs post-processing
      #
      # @param execution_data [Hash] Execution attributes from instrumentation
      # @return [void]
      def perform(execution_data)
        # Filter to only known attributes to prevent schema mismatches
        filtered_data = filter_known_attributes(execution_data)
        execution = Execution.create!(filtered_data)

        # Calculate costs if token data is available
        if execution.input_tokens && execution.output_tokens
          execution.calculate_costs!
          execution.save!
        end

        # Log if execution was anomalous
        log_anomaly(execution) if anomaly?(execution)
      end

      private

      # Filters data to only include attributes that exist on the Execution model
      #
      # This provides a safety net against schema mismatches, such as when
      # tenant_id is passed but the column doesn't exist in the database.
      #
      # @param data [Hash] The raw execution data
      # @return [Hash] Filtered data with only known attributes
      def filter_known_attributes(data)
        return data unless defined?(Execution) && Execution.respond_to?(:column_names)

        known_columns = Execution.column_names
        data.select { |key, _| known_columns.include?(key.to_s) }
      end

      # Checks if execution should be flagged as anomalous
      #
      # @param execution [Execution] The execution to check
      # @return [Boolean] true if cost/duration exceeds thresholds or status is error
      def anomaly?(execution)
        config = RubyLLM::Agents.configuration

        (execution.total_cost && execution.total_cost > config.anomaly_cost_threshold) ||
          (execution.duration_ms && execution.duration_ms > config.anomaly_duration_threshold) ||
          execution.status_error?
      end

      # Logs a warning about an anomalous execution
      #
      # @param execution [Execution] The anomalous execution
      # @return [void]
      def log_anomaly(execution)
        Rails.logger.warn(
          "[RubyLLM::Agents] Execution anomaly detected: " \
          "agent=#{execution.agent_type} " \
          "id=#{execution.id} " \
          "cost=$#{execution.total_cost} " \
          "duration_ms=#{execution.duration_ms} " \
          "status=#{execution.status}"
        )
      end
    end
  end
end
