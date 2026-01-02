# frozen_string_literal: true

module RubyLLM
  module Agents
    class Workflow
      # Instrumentation concern for workflow execution tracking
      #
      # Provides comprehensive workflow tracking including:
      # - Root execution record creation for the workflow
      # - Timing metrics (started_at, completed_at, duration_ms)
      # - Aggregate token usage and cost across all steps/branches
      # - Workflow-specific metadata (workflow_id, workflow_type)
      # - Error handling with proper status updates
      #
      # @api private
      module Instrumentation
        extend ActiveSupport::Concern

        included do
          # @!attribute [rw] execution_id
          #   The ID of the workflow's root execution record
          #   @return [Integer, nil]
          attr_accessor :execution_id
        end

        # Wraps workflow execution with comprehensive metrics tracking
        #
        # Creates a root execution record for the workflow and tracks
        # aggregate metrics from all child executions.
        #
        # @yield The block containing the workflow execution
        # @return [WorkflowResult] The workflow result
        def instrument_workflow(&block)
          started_at = Time.current
          @workflow_started_at = started_at

          # Create workflow execution record
          execution = create_workflow_execution(started_at)
          @execution_id = execution&.id
          @root_execution_id = execution&.id

          begin
            result = if self.class.timeout
                       Timeout.timeout(self.class.timeout) { yield }
                     else
                       yield
                     end

            complete_workflow_execution(
              execution,
              completed_at: Time.current,
              status: result.status,
              result: result
            )

            result
          rescue Timeout::Error => e
            complete_workflow_execution(
              execution,
              completed_at: Time.current,
              status: "timeout",
              error: e
            )
            raise
          rescue WorkflowCostExceededError => e
            complete_workflow_execution(
              execution,
              completed_at: Time.current,
              status: "error",
              error: e
            )
            raise
          rescue StandardError => e
            complete_workflow_execution(
              execution,
              completed_at: Time.current,
              status: "error",
              error: e
            )
            raise
          end
        end

        private

        # Creates the initial workflow execution record
        #
        # @param started_at [Time] When the workflow started
        # @return [RubyLLM::Agents::Execution, nil] The created record
        def create_workflow_execution(started_at)
          RubyLLM::Agents::Execution.create!(
            agent_type: self.class.name,
            agent_version: self.class.version,
            model_id: "workflow",
            temperature: nil,
            started_at: started_at,
            status: "running",
            parameters: Redactor.redact(options),
            metadata: workflow_metadata,
            workflow_id: workflow_id,
            workflow_type: workflow_type_name
          )
        rescue StandardError => e
          Rails.logger.error("[RubyLLM::Agents::Workflow] Failed to create workflow execution: #{e.message}")
          nil
        end

        # Updates the workflow execution record with completion data
        #
        # @param execution [Execution, nil] The execution record
        # @param completed_at [Time] When the workflow completed
        # @param status [String] Final status
        # @param result [WorkflowResult, nil] The workflow result
        # @param error [Exception, nil] The error if failed
        def complete_workflow_execution(execution, completed_at:, status:, result: nil, error: nil)
          return unless execution

          started_at = execution.started_at
          duration_ms = ((completed_at - started_at) * 1000).round

          update_data = {
            completed_at: completed_at,
            duration_ms: duration_ms,
            status: status
          }

          # Add aggregate metrics from result
          if result
            update_data.merge!(
              input_tokens: result.input_tokens,
              output_tokens: result.output_tokens,
              total_tokens: result.total_tokens,
              cached_tokens: result.cached_tokens,
              input_cost: result.input_cost,
              output_cost: result.output_cost,
              total_cost: result.total_cost
            )

            # Store step/branch results summary
            update_data[:response] = build_response_summary(result)
          end

          # Add error data if failed
          if error
            update_data.merge!(
              error_class: error.class.name,
              error_message: error.message.to_s.truncate(65535)
            )
          end

          execution.update!(update_data)
        rescue StandardError => e
          Rails.logger.error("[RubyLLM::Agents::Workflow] Failed to update workflow execution #{execution&.id}: #{e.message}")
          mark_workflow_failed!(execution, error: error || e)
        end

        # Emergency fallback to mark workflow as failed
        #
        # @param execution [Execution, nil] The execution record
        # @param error [Exception, nil] The error
        def mark_workflow_failed!(execution, error: nil)
          return unless execution&.id

          update_data = {
            status: "error",
            completed_at: Time.current,
            error_class: error&.class&.name || "UnknownError",
            error_message: error&.message&.to_s&.truncate(65535) || "Unknown error"
          }

          execution.class.where(id: execution.id, status: "running").update_all(update_data)
        rescue StandardError => e
          Rails.logger.error("[RubyLLM::Agents::Workflow] CRITICAL: Failed to mark workflow #{execution&.id} as failed: #{e.message}")
        end

        # Builds a summary of step/branch results for storage
        #
        # @param result [WorkflowResult] The workflow result
        # @return [Hash] Summary data
        def build_response_summary(result)
          summary = {
            workflow_type: result.workflow_type,
            status: result.status
          }

          if result.steps.any?
            summary[:steps] = result.steps.transform_values do |r|
              {
                status: r.respond_to?(:success?) ? (r.success? ? "success" : "error") : "unknown",
                total_cost: r.respond_to?(:total_cost) ? r.total_cost : 0,
                duration_ms: r.respond_to?(:duration_ms) ? r.duration_ms : nil
              }
            end
          end

          if result.branches.any?
            summary[:branches] = result.branches.transform_values do |r|
              next { status: "error" } if r.nil?

              {
                status: r.respond_to?(:success?) ? (r.success? ? "success" : "error") : "unknown",
                total_cost: r.respond_to?(:total_cost) ? r.total_cost : 0,
                duration_ms: r.respond_to?(:duration_ms) ? r.duration_ms : nil
              }
            end
          end

          if result.routed_to
            summary[:routed_to] = result.routed_to
            summary[:classification_cost] = result.classification_cost
          end

          summary
        end

        # Returns workflow-specific metadata
        #
        # @return [Hash] Workflow metadata
        def workflow_metadata
          base_metadata = {
            workflow_id: workflow_id,
            workflow_type: workflow_type_name
          }

          # Allow subclasses to add custom metadata
          if respond_to?(:execution_metadata, true)
            base_metadata.merge(execution_metadata)
          else
            base_metadata
          end
        end

        # Returns the workflow type name for storage
        #
        # @return [String] The workflow type (pipeline, parallel, router)
        def workflow_type_name
          case self
          when Workflow::Pipeline then "pipeline"
          when Workflow::Parallel then "parallel"
          when Workflow::Router then "router"
          else "workflow"
          end
        end

        # Hook for subclasses to add custom metadata
        #
        # @return [Hash] Custom metadata
        def execution_metadata
          {}
        end
      end
    end
  end
end
