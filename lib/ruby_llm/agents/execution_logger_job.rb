# frozen_string_literal: true

module RubyLLM
  module Agents
    # Background job for logging agent executions to the database
    #
    # This job is called automatically after each agent execution to:
    # - Create an Execution record with all execution data
    # - Calculate costs based on token usage
    # - Log anomalies (expensive, slow, or failed executions)
    #
    # Configuration:
    #   RubyLLM::Agents.configure do |config|
    #     config.anomaly_cost_threshold = 5.00       # Log if cost > $5
    #     config.anomaly_duration_threshold = 10_000 # Log if duration > 10s
    #   end
    #
    class ExecutionLoggerJob < ActiveJob::Base
      queue_as :default

      # Retry with polynomial backoff
      retry_on StandardError, wait: :polynomially_longer, attempts: 3

      def perform(execution_data)
        execution = Execution.create!(execution_data)

        # Calculate costs if token data is available
        if execution.input_tokens && execution.output_tokens
          execution.calculate_costs!
          execution.save!
        end

        # Log if execution was anomalous
        log_anomaly(execution) if anomaly?(execution)
      end

      private

      def anomaly?(execution)
        config = RubyLLM::Agents.configuration

        (execution.total_cost && execution.total_cost > config.anomaly_cost_threshold) ||
          (execution.duration_ms && execution.duration_ms > config.anomaly_duration_threshold) ||
          execution.status_error?
      end

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
