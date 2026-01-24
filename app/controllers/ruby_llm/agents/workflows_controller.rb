# frozen_string_literal: true

module RubyLLM
  module Agents
    # Controller for viewing workflow details and per-workflow analytics
    #
    # Provides detailed views for individual workflows including structure
    # visualization, per-step/branch performance, route distribution,
    # and execution history.
    #
    # @see AgentRegistry For workflow discovery
    # @see Paginatable For pagination implementation
    # @see Filterable For filter parsing and validation
    # @api private
    class WorkflowsController < ApplicationController
      include Paginatable
      include Filterable

      # Lists all registered workflows with their details
      #
      # Uses AgentRegistry to discover workflows from both file system
      # and execution history. Separates workflows by type for sub-tabs.
      #
      # @return [void]
      def index
        all_items = AgentRegistry.all_with_details
        @workflows = all_items.select { |a| a[:is_workflow] }
      rescue StandardError => e
        Rails.logger.error("[RubyLLM::Agents] Error loading workflows: #{e.message}")
        @workflows = []
        flash.now[:alert] = "Error loading workflows list"
      end

      # Shows detailed view for a specific workflow
      #
      # Loads workflow configuration (if class exists), statistics,
      # filtered executions, chart data, and step-level analytics.
      # Works for both active workflows and deleted workflows with history.
      #
      # @return [void]
      def show
        @workflow_type = CGI.unescape(params[:id])
        @workflow_class = AgentRegistry.find(@workflow_type)
        @workflow_active = @workflow_class.present?

        # Determine workflow type from class or execution history
        @workflow_type_kind = detect_workflow_type_kind

        load_workflow_stats
        load_filter_options
        load_filtered_executions
        load_chart_data
        load_step_stats

        if @workflow_class
          load_workflow_config
        end
      rescue StandardError => e
        Rails.logger.error("[RubyLLM::Agents] Error loading workflow #{@workflow_type}: #{e.message}")
        redirect_to ruby_llm_agents.workflows_path, alert: "Error loading workflow details"
      end

      private

      # Detects the workflow type kind (pipeline, parallel, router, dsl)
      #
      # DSL workflows are those that use the new step/parallel DSL directly
      # on the Workflow base class without inheriting from Pipeline/Parallel/Router.
      #
      # @return [String, nil] The workflow type kind
      def detect_workflow_type_kind
        if @workflow_class
          ancestors = @workflow_class.ancestors.map { |a| a.name.to_s }

          # Check for legacy workflow types first
          if ancestors.include?("RubyLLM::Agents::Workflow::Pipeline")
            "pipeline"
          elsif ancestors.include?("RubyLLM::Agents::Workflow::Parallel")
            "parallel"
          elsif ancestors.include?("RubyLLM::Agents::Workflow::Router")
            "router"
          elsif @workflow_class.respond_to?(:step_configs) && @workflow_class.step_configs.any?
            # New DSL-based workflow
            "dsl"
          end
        else
          # Fallback to execution history
          Execution.by_agent(@workflow_type)
                   .where.not(workflow_type: nil)
                   .pluck(:workflow_type)
                   .first
        end
      end

      # Loads all-time and today's statistics for the workflow
      #
      # @return [void]
      def load_workflow_stats
        @stats = Execution.stats_for(@workflow_type, period: :all_time)
        @stats_today = Execution.stats_for(@workflow_type, period: :today)

        # Additional stats for new schema fields
        workflow_scope = Execution.by_agent(@workflow_type)
        @cache_hit_rate = workflow_scope.cache_hit_rate
        @streaming_rate = workflow_scope.streaming_rate
        @avg_ttft = workflow_scope.avg_time_to_first_token
      end

      # Loads available filter options from execution history
      #
      # @return [void]
      def load_filter_options
        filter_data = Execution.by_agent(@workflow_type)
                               .where.not(agent_version: nil)
                               .or(Execution.by_agent(@workflow_type).where.not(model_id: nil))
                               .or(Execution.by_agent(@workflow_type).where.not(temperature: nil))
                               .pluck(:agent_version, :model_id, :temperature)

        @versions = filter_data.map(&:first).compact.uniq.sort.reverse
        @models = filter_data.map { |d| d[1] }.compact.uniq.sort
        @temperatures = filter_data.map(&:last).compact.uniq.sort
      end

      # Loads paginated and filtered executions with statistics
      #
      # @return [void]
      def load_filtered_executions
        base_scope = build_filtered_scope
        result = paginate(base_scope)
        @executions = result[:records]
        @pagination = result[:pagination]

        @filter_stats = {
          total_count: result[:pagination][:total_count],
          total_cost: base_scope.sum(:total_cost),
          total_tokens: base_scope.sum(:total_tokens)
        }
      end

      # Builds a filtered scope for the current workflow's executions
      #
      # @return [ActiveRecord::Relation] Filtered execution scope
      def build_filtered_scope
        scope = Execution.by_agent(@workflow_type)

        # Apply status filter with validation
        statuses = parse_array_param(:statuses)
        scope = apply_status_filter(scope, statuses) if statuses.any?

        # Apply version filter
        versions = parse_array_param(:versions)
        scope = scope.where(agent_version: versions) if versions.any?

        # Apply model filter
        models = parse_array_param(:models)
        scope = scope.where(model_id: models) if models.any?

        # Apply temperature filter
        temperatures = parse_array_param(:temperatures)
        scope = scope.where(temperature: temperatures) if temperatures.any?

        # Apply time range filter with validation
        days = parse_days_param
        scope = apply_time_filter(scope, days)

        scope
      end

      # Loads chart data for workflow performance visualization
      #
      # @return [void]
      def load_chart_data
        @trend_data = Execution.trend_analysis(agent_type: @workflow_type, days: 30)
        @status_distribution = Execution.by_agent(@workflow_type).group(:status).count
        @finish_reason_distribution = Execution.by_agent(@workflow_type).finish_reason_distribution
      end

      # Loads per-step/branch statistics for workflow analytics
      #
      # @return [void]
      def load_step_stats
        @step_stats = calculate_step_stats
        @route_distribution = calculate_route_distribution if @workflow_type_kind == "router"
      end

      # Calculates per-step/branch performance statistics
      #
      # @return [Array<Hash>] Array of step stats hashes
      def calculate_step_stats
        # Get root workflow executions
        root_executions = Execution.by_agent(@workflow_type)
                                   .root_executions
                                   .where("created_at > ?", 30.days.ago)
                                   .pluck(:id)

        return [] if root_executions.empty?

        # Aggregate child execution stats by workflow_step
        child_stats = Execution.where(parent_execution_id: root_executions)
                               .group(:workflow_step)
                               .select(
                                 "workflow_step",
                                 "COUNT(*) as execution_count",
                                 "AVG(duration_ms) as avg_duration_ms",
                                 "SUM(total_cost) as total_cost",
                                 "AVG(total_cost) as avg_cost",
                                 "SUM(total_tokens) as total_tokens",
                                 "AVG(total_tokens) as avg_tokens",
                                 "SUM(CASE WHEN status = 'success' THEN 1 ELSE 0 END) as success_count",
                                 "SUM(CASE WHEN status = 'error' THEN 1 ELSE 0 END) as error_count"
                               )

        # Get agent type mappings for each step
        step_agent_map = Execution.where(parent_execution_id: root_executions)
                                  .where.not(workflow_step: nil)
                                  .group(:workflow_step)
                                  .pluck(:workflow_step, Arel.sql("MAX(agent_type)"))
                                  .to_h

        child_stats.map do |row|
          next if row.workflow_step.blank?

          execution_count = row.execution_count.to_i
          success_count = row.success_count.to_i
          success_rate = execution_count > 0 ? (success_count.to_f / execution_count * 100).round(1) : 0

          {
            name: row.workflow_step,
            agent_type: step_agent_map[row.workflow_step],
            execution_count: execution_count,
            success_rate: success_rate,
            avg_duration_ms: row.avg_duration_ms.to_f.round(0),
            total_cost: row.total_cost.to_f.round(4),
            avg_cost: row.avg_cost.to_f.round(6),
            total_tokens: row.total_tokens.to_i,
            avg_tokens: row.avg_tokens.to_f.round(0)
          }
        end.compact
      end

      # Calculates route distribution for router workflows
      #
      # @return [Hash] Route distribution data
      def calculate_route_distribution
        # Get route distribution from routed_to field
        distribution = Execution.by_agent(@workflow_type)
                                .where("created_at > ?", 30.days.ago)
                                .where.not(routed_to: nil)
                                .group(:routed_to)
                                .count

        total = distribution.values.sum
        return {} if total.zero?

        # Add percentage and sorting
        distribution.transform_values do |count|
          {
            count: count,
            percentage: (count.to_f / total * 100).round(1)
          }
        end.sort_by { |_k, v| -v[:count] }.to_h
      end

      # Loads the current workflow class configuration
      #
      # @return [void]
      def load_workflow_config
        @config = {
          # Basic configuration
          version: safe_call(@workflow_class, :version),
          description: safe_call(@workflow_class, :description),
          timeout: safe_call(@workflow_class, :timeout),
          max_cost: safe_call(@workflow_class, :max_cost)
        }

        # Load unified workflow structure for all types
        load_unified_workflow_config
      end

      # Loads unified workflow configuration for all workflow types
      # Normalizes pipeline, parallel, router, and DSL workflows to a common format
      #
      # @return [void]
      def load_unified_workflow_config
        @parallel_groups = []
        @input_schema_fields = {}

        case @workflow_type_kind
        when "pipeline"
          @steps = extract_steps(@workflow_class)
          @config[:steps_count] = @steps.size
        when "parallel"
          branches = extract_branches(@workflow_class)
          # Convert parallel branches to steps in a parallel group
          @steps = branches.map do |branch|
            branch.merge(parallel: true, parallel_group: :main)
          end
          @parallel_groups = [{ name: :main, step_names: branches.map { |b| b[:name] }, fail_fast: safe_call(@workflow_class, :fail_fast?) }]
          @config[:branches_count] = branches.size
          @config[:fail_fast] = safe_call(@workflow_class, :fail_fast?)
        when "router"
          routes = extract_routes(@workflow_class)
          # Convert router to a classify step followed by routing step
          @steps = [
            { name: :classify, agent: "Classifier", routing: false, description: "Classifies input to determine route" },
            { name: :route, agent: nil, routing: true, routes: routes, description: "Routes to specialized agent" }
          ]
          @config[:routes_count] = routes.size
          @config[:routes] = routes
          @config[:classifier_model] = safe_call(@workflow_class, :classifier_model)
          @config[:classifier_temperature] = safe_call(@workflow_class, :classifier_temperature)
        else
          # DSL-based workflow (default)
          @steps = extract_dsl_steps(@workflow_class)
          @parallel_groups = extract_parallel_groups(@workflow_class)
          @config[:steps_count] = @steps.size
          @config[:parallel_groups_count] = @parallel_groups.size
          @config[:has_routing] = @steps.any? { |s| s[:routing] }
          @config[:has_input_schema] = @workflow_class.respond_to?(:input_schema) && @workflow_class.input_schema.present?

          if @config[:has_input_schema]
            @input_schema_fields = @workflow_class.input_schema.fields.transform_values(&:to_h)
          end
        end
      end

      # Extracts steps from a pipeline workflow class
      #
      # @param klass [Class] The workflow class
      # @return [Array<Hash>] Array of step hashes
      def extract_steps(klass)
        return [] unless klass.respond_to?(:steps)

        klass.steps.map do |name, config|
          {
            name: name,
            agent: config[:agent]&.name,
            optional: config[:continue_on_error] || false
          }
        end
      end

      # Extracts steps from a DSL-based workflow class
      #
      # @param klass [Class] The workflow class
      # @return [Array<Hash>] Array of step hashes with DSL metadata
      def extract_dsl_steps(klass)
        return [] unless klass.respond_to?(:step_metadata)

        klass.step_metadata.map do |meta|
          {
            name: meta[:name],
            agent: meta[:agent],
            description: meta[:description],
            ui_label: meta[:ui_label],
            optional: meta[:optional],
            timeout: meta[:timeout],
            routing: meta[:routing],
            parallel: meta[:parallel],
            parallel_group: meta[:parallel_group]
          }
        end
      end

      # Extracts parallel groups from a DSL-based workflow class
      #
      # @param klass [Class] The workflow class
      # @return [Array<Hash>] Array of parallel group hashes
      def extract_parallel_groups(klass)
        return [] unless klass.respond_to?(:parallel_groups)

        klass.parallel_groups.map(&:to_h)
      end

      # Extracts branches from a parallel workflow class
      #
      # @param klass [Class] The workflow class
      # @return [Array<Hash>] Array of branch hashes
      def extract_branches(klass)
        return [] unless klass.respond_to?(:branches)

        klass.branches.map do |name, config|
          {
            name: name,
            agent: config[:agent]&.name,
            optional: config[:optional] || false
          }
        end
      end

      # Extracts routes from a router workflow class
      #
      # @param klass [Class] The workflow class
      # @return [Array<Hash>] Array of route hashes
      def extract_routes(klass)
        return [] unless klass.respond_to?(:routes)

        klass.routes.map do |name, config|
          {
            name: name,
            agent: config[:agent]&.name,
            description: config[:description],
            default: config[:default] || false
          }
        end
      end

      # Safely calls a method on a class, returning nil if method doesn't exist
      #
      # @param klass [Class, nil] The class to call the method on
      # @param method_name [Symbol] The method to call
      # @return [Object, nil] The result or nil
      def safe_call(klass, method_name)
        return nil unless klass
        return nil unless klass.respond_to?(method_name)

        klass.public_send(method_name)
      rescue StandardError
        nil
      end
    end
  end
end
