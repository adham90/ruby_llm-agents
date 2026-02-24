# frozen_string_literal: true

require_relative "workflow/step"
require_relative "workflow/context"
require_relative "workflow/flow_graph"
require_relative "workflow/dsl"
require_relative "workflow/runner"
require_relative "workflow/parallel_runner"
require_relative "workflow/dispatch"
require_relative "workflow/result"

module RubyLLM
  module Agents
    # Base class for composing agents into workflows
    #
    # Workflow is a standalone class (not a BaseAgent subclass) that
    # orchestrates multiple agents through a declarative DSL, similar
    # to ImagePipeline but for general-purpose agent composition.
    #
    # @example Sequential pipeline
    #   class ContentWorkflow < RubyLLM::Agents::Workflow
    #     description "Research, draft, and edit content"
    #
    #     step :research, ResearchAgent
    #     step :draft,    DraftAgent,  after: :research
    #     step :edit,     EditAgent,   after: :draft
    #
    #     pass :research, to: :draft, as: { notes: :content }
    #     pass :draft,    to: :edit,  as: { content: :content }
    #   end
    #
    #   result = ContentWorkflow.call(topic: "AI safety")
    #   result.success?    # => true
    #   result.total_cost  # => 0.0082
    #   result.step(:edit) # => the edit agent's Result
    #
    # @example Flow DSL
    #   class Pipeline < RubyLLM::Agents::Workflow
    #     step :a, AgentA
    #     step :b, AgentB
    #     step :c, AgentC
    #
    #     flow :a >> :b >> :c
    #   end
    #
    class Workflow
      extend DSL

      class << self
        # Execute the workflow with the given parameters
        #
        # @param params [Hash] Parameters passed to the workflow context
        # @return [WorkflowResult] Aggregated result
        def call(**params)
          new(**params).call
        end

        # Ensure subclasses inherit DSL settings
        def inherited(subclass)
          super
          subclass.instance_variable_set(:@steps, @steps&.map(&:dup) || [])
          subclass.instance_variable_set(:@pass_definitions, @pass_definitions&.dup || [])
          subclass.instance_variable_set(:@description, @description)
          subclass.instance_variable_set(:@on_failure, @on_failure)
          subclass.instance_variable_set(:@budget_limit, @budget_limit)
          subclass.instance_variable_set(:@tenant, @tenant)
          subclass.instance_variable_set(:@dispatches, @dispatches&.dup || [])
        end
      end

      attr_reader :options, :context

      # @param options [Hash] Workflow parameters
      def initialize(**options)
        @options = options
        @context = nil
      end

      # Execute the workflow
      #
      # @return [WorkflowResult]
      def call
        @started_at = Time.current
        @context = WorkflowContext.new(**@options)

        graph = FlowGraph.new(self.class.steps)

        runner = build_runner(graph)
        step_timings = runner.run

        build_result(step_timings)
      rescue => e
        build_error_result(e)
      end

      private

      def build_runner(graph)
        parent_id = record_parent_execution

        ParallelRunner.new(
          workflow_class: self.class,
          graph: graph,
          context: @context,
          on_failure: self.class.on_failure,
          parent_execution_id: parent_id,
          root_execution_id: parent_id
        )
      end

      def build_result(step_timings)
        result = WorkflowResult.new(
          step_results: @context.step_results.dup,
          step_timings: step_timings,
          errors: @context.errors.dup,
          started_at: @started_at,
          completed_at: Time.current,
          workflow_class: self.class.name,
          context_snapshot: @context.to_h
        )

        record_execution(result) if execution_tracking_enabled?
        result
      end

      def build_error_result(error)
        result = WorkflowResult.new(
          step_results: @context&.step_results&.dup || {},
          step_timings: {},
          errors: @context&.errors&.dup || {},
          started_at: @started_at || Time.current,
          completed_at: Time.current,
          workflow_class: self.class.name,
          context_snapshot: @context&.to_h || {},
          error_class: error.class.name,
          error_message: error.message
        )

        record_failed_execution(error) if execution_tracking_enabled?
        result
      end

      # Execution tracking

      def execution_tracking_enabled?
        config.track_executions
      rescue
        false
      end

      def record_parent_execution
        return nil unless execution_tracking_enabled?

        execution = RubyLLM::Agents::Execution.create!(
          agent_type: self.class.name,
          execution_type: "workflow",
          model_id: "workflow",
          status: "running",
          started_at: @started_at,
          metadata: {
            workflow_type: "sequential",
            step_count: self.class.steps.size,
            step_names: self.class.steps.map(&:name)
          }
        )
        execution.id
      rescue => e
        log_error("Failed to record parent execution: #{e.message}")
        nil
      end

      def record_execution(result)
        attrs = {
          agent_type: self.class.name,
          execution_type: "workflow",
          model_id: result.primary_model_id || "workflow",
          status: result.success? ? "success" : "error",
          input_tokens: result.input_tokens,
          output_tokens: result.output_tokens,
          total_cost: result.total_cost,
          duration_ms: result.duration_ms,
          started_at: result.started_at,
          completed_at: result.completed_at,
          metadata: {
            workflow_type: "sequential",
            step_count: result.step_count,
            successful_steps: result.successful_step_count,
            failed_steps: result.failed_step_count,
            step_names: result.step_names
          }
        }

        if config.async_logging && defined?(ExecutionLoggerJob)
          ExecutionLoggerJob.perform_later(attrs)
        else
          execution = RubyLLM::Agents::Execution.create!(attrs)
          result.execution_id = execution.id
        end
      rescue => e
        log_error("Failed to record workflow execution: #{e.message}")
      end

      def record_failed_execution(error)
        attrs = {
          agent_type: self.class.name,
          execution_type: "workflow",
          model_id: "workflow",
          status: "error",
          input_tokens: 0,
          output_tokens: 0,
          total_cost: 0,
          duration_ms: ((@started_at ? (Time.current - @started_at) : 0) * 1000).round,
          started_at: @started_at || Time.current,
          completed_at: Time.current,
          error_class: error.class.name,
          error_message: error.message.truncate(1000),
          metadata: {
            workflow_type: "sequential",
            step_count: self.class.steps.size
          }
        }

        if config.async_logging && defined?(ExecutionLoggerJob)
          ExecutionLoggerJob.perform_later(attrs)
        else
          RubyLLM::Agents::Execution.create!(attrs)
        end
      rescue => e
        log_error("Failed to record failed workflow execution: #{e.message}")
      end

      def config
        RubyLLM::Agents.configuration
      end

      def log_error(message)
        if defined?(Rails)
          Rails.logger.error("[RubyLLM::Agents::Workflow] #{message}")
        end
      end
    end
  end
end
