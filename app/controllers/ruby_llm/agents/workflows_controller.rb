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
      # Supports sorting by various columns.
      #
      # @return [void]
      def index
        all_items = AgentRegistry.all_with_details
        @workflows = all_items.select { |a| a[:is_workflow] }
        @sort_params = parse_sort_params
        @workflows = sort_workflows(@workflows)
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

      # Detects the workflow type kind
      #
      # All workflows now use the DSL and return "workflow" type.
      #
      # @return [String, nil] The workflow type kind
      def detect_workflow_type_kind
        if @workflow_class
          if @workflow_class.respond_to?(:step_configs) && @workflow_class.step_configs.any?
            "workflow"
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
      #
      # @return [void]
      def load_unified_workflow_config
        @parallel_groups = []
        @input_schema_fields = {}
        @lifecycle_hooks = {}

        # All workflows use DSL
        @steps = extract_dsl_steps(@workflow_class)
        @parallel_groups = extract_parallel_groups(@workflow_class)
        @lifecycle_hooks = extract_lifecycle_hooks(@workflow_class)

        @config[:steps_count] = @steps.size
        @config[:parallel_groups_count] = @parallel_groups.size
        @config[:has_routing] = @steps.any? { |s| s[:routing] }
        @config[:has_conditions] = @steps.any? { |s| s[:if_condition] || s[:unless_condition] }
        @config[:has_retries] = @steps.any? { |s| s[:retry_config] }
        @config[:has_fallbacks] = @steps.any? { |s| s[:fallbacks]&.any? }
        @config[:has_lifecycle_hooks] = @lifecycle_hooks.values.any? { |v| v.to_i > 0 }
        @config[:has_input_schema] = @workflow_class.respond_to?(:input_schema) && @workflow_class.input_schema.present?

        if @config[:has_input_schema]
          @input_schema_fields = @workflow_class.input_schema.fields.transform_values(&:to_h)
        end
      end

      # Extracts steps from a DSL-based workflow class with full configuration
      #
      # @param klass [Class] The workflow class
      # @return [Array<Hash>] Array of step hashes with full DSL metadata
      def extract_dsl_steps(klass)
        return [] unless klass.respond_to?(:step_metadata) && klass.respond_to?(:step_configs)

        step_configs = klass.step_configs

        klass.step_metadata.map do |meta|
          config = step_configs[meta[:name]]
          step_hash = {
            name: meta[:name],
            agent: meta[:agent],
            description: meta[:description],
            ui_label: meta[:ui_label],
            optional: meta[:optional],
            timeout: meta[:timeout],
            routing: meta[:routing],
            parallel: meta[:parallel],
            parallel_group: meta[:parallel_group],
            custom_block: config&.custom_block?,
            # New composition features
            workflow: meta[:workflow],
            iteration: meta[:iteration],
            iteration_concurrency: meta[:iteration_concurrency]
          }

          # Add extended configuration from StepConfig
          if config
            step_hash.merge!(
              retry_config: extract_retry_config(config),
              fallbacks: config.fallbacks.map(&:name),
              if_condition: describe_condition(config.if_condition),
              unless_condition: describe_condition(config.unless_condition),
              has_input_mapper: config.input_mapper.present?,
              pick_fields: config.pick_fields,
              pick_from: config.pick_from,
              default_value: config.default_value,
              routes: extract_routes(config),
              # Iteration error handling
              iteration_fail_fast: config.iteration_fail_fast?,
              continue_on_error: config.continue_on_error?
            )

            # Add sub-workflow metadata for nested workflow steps
            if config.workflow? && config.agent
              step_hash[:sub_workflow] = extract_sub_workflow_metadata(config.agent)
            end
          end

          step_hash.compact
        end
      end

      # Extracts retry configuration in a display-friendly format
      #
      # @param config [StepConfig] The step configuration
      # @return [Hash, nil] Retry config hash or nil
      def extract_retry_config(config)
        retry_cfg = config.retry_config
        return nil unless retry_cfg && retry_cfg[:max].to_i > 0

        {
          max: retry_cfg[:max],
          backoff: retry_cfg[:backoff],
          delay: retry_cfg[:delay]
        }
      end

      # Describes a condition for display
      #
      # @param condition [Symbol, Proc, nil] The condition
      # @return [String, nil] Human-readable description
      def describe_condition(condition)
        return nil if condition.nil?

        case condition
        when Symbol then condition.to_s
        when Proc then "lambda"
        else condition.to_s
        end
      end

      # Extracts routes from a routing step
      #
      # @param config [StepConfig] The step configuration
      # @return [Array<Hash>, nil] Array of route hashes or nil
      def extract_routes(config)
        return nil unless config.routing? && config.block

        builder = RubyLLM::Agents::Workflow::DSL::RouteBuilder.new
        config.block.call(builder)

        routes = builder.routes.map do |name, route_config|
          {
            name: name.to_s,
            agent: route_config[:agent]&.name,
            timeout: extract_timeout_value(route_config[:options][:timeout]),
            fallback: Array(route_config[:options][:fallback]).first&.then { |f| f.respond_to?(:name) ? f.name : f.to_s },
            has_input_mapper: route_config[:options][:input].present?,
            if_condition: describe_condition(route_config[:options][:if]),
            default: false
          }.compact
        end

        # Add default route
        if builder.default
          routes << {
            name: "default",
            agent: builder.default[:agent]&.name,
            timeout: extract_timeout_value(builder.default[:options][:timeout]),
            has_input_mapper: builder.default[:options][:input].present?,
            default: true
          }.compact
        end

        routes
      rescue StandardError => e
        Rails.logger.debug "[RubyLLM::Agents] Could not extract routes: #{e.message}"
        nil
      end

      # Extracts timeout value handling ActiveSupport::Duration
      #
      # @param timeout [Integer, ActiveSupport::Duration, nil] The timeout value
      # @return [Integer, nil] Timeout in seconds or nil
      def extract_timeout_value(timeout)
        return nil if timeout.nil?

        timeout.respond_to?(:to_i) ? timeout.to_i : timeout
      end

      # Extracts metadata for a nested sub-workflow
      #
      # @param workflow_class [Class] The sub-workflow class
      # @return [Hash] Sub-workflow metadata including steps preview and budget info
      def extract_sub_workflow_metadata(workflow_class)
        return nil unless workflow_class.respond_to?(:step_metadata)

        {
          name: workflow_class.name,
          description: safe_call(workflow_class, :description),
          timeout: safe_call(workflow_class, :timeout),
          max_cost: safe_call(workflow_class, :max_cost),
          max_recursion_depth: safe_call(workflow_class, :max_recursion_depth),
          steps_count: workflow_class.step_configs.size,
          steps_preview: extract_sub_workflow_steps_preview(workflow_class)
        }.compact
      rescue StandardError => e
        Rails.logger.debug "[RubyLLM::Agents] Could not extract sub-workflow metadata: #{e.message}"
        nil
      end

      # Extracts a simplified steps preview for sub-workflow display
      #
      # @param workflow_class [Class] The sub-workflow class
      # @return [Array<Hash>] Simplified step hashes for preview
      def extract_sub_workflow_steps_preview(workflow_class)
        return [] unless workflow_class.respond_to?(:step_metadata)

        workflow_class.step_metadata.map do |meta|
          {
            name: meta[:name],
            agent: meta[:agent]&.gsub(/Agent$/, "")&.gsub(/Workflow$/, ""),
            routing: meta[:routing],
            iteration: meta[:iteration],
            workflow: meta[:workflow],
            parallel: meta[:parallel]
          }.compact
        end
      rescue StandardError
        []
      end

      # Extracts parallel groups from a DSL-based workflow class
      #
      # @param klass [Class] The workflow class
      # @return [Array<Hash>] Array of parallel group hashes
      def extract_parallel_groups(klass)
        return [] unless klass.respond_to?(:parallel_groups)

        klass.parallel_groups.map(&:to_h)
      end

      # Extracts lifecycle hooks from a workflow class
      #
      # @param klass [Class] The workflow class
      # @return [Hash] Hash of hook types to counts
      def extract_lifecycle_hooks(klass)
        return {} unless klass.respond_to?(:lifecycle_hooks)

        hooks = klass.lifecycle_hooks
        {
          before_workflow: hooks[:before_workflow]&.size || 0,
          after_workflow: hooks[:after_workflow]&.size || 0,
          on_step_error: hooks[:on_step_error]&.size || 0
        }
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

      # Parses and validates sort parameters from request
      #
      # @return [Hash] Hash with :column and :direction keys
      def parse_sort_params
        allowed_columns = %w[name workflow_type execution_count total_cost success_rate last_executed]
        column = params[:sort]
        direction = params[:direction]

        {
          column: allowed_columns.include?(column) ? column : "name",
          direction: %w[asc desc].include?(direction) ? direction : "asc"
        }
      end

      # Sorts workflows array by the specified column and direction
      #
      # @param workflows [Array<Hash>] Array of workflow hashes
      # @return [Array<Hash>] Sorted array
      def sort_workflows(workflows)
        column = @sort_params[:column].to_sym
        direction = @sort_params[:direction]

        sorted = workflows.sort_by do |w|
          value = w[column]
          case column
          when :name
            value.to_s.downcase
          when :last_executed
            value || Time.at(0)
          else
            value || 0
          end
        end

        direction == "desc" ? sorted.reverse : sorted
      end
    end
  end
end
