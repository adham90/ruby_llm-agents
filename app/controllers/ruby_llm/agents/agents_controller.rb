# frozen_string_literal: true

module RubyLLM
  module Agents
    # Controller for viewing agent details and per-agent analytics
    #
    # Provides an overview of all registered agents and detailed views
    # for individual agents including configuration, execution history,
    # and performance metrics.
    #
    # @see AgentRegistry For agent discovery
    # @see Paginatable For pagination implementation
    # @see Filterable For filter parsing and validation
    # @api private
    class AgentsController < ApplicationController
      include Paginatable
      include Filterable

      # Allowed sort columns for the agents list (in-memory sorting)
      AGENT_SORTABLE_COLUMNS = %w[name agent_type model execution_count total_cost success_rate last_executed].freeze
      DEFAULT_AGENT_SORT_COLUMN = "name"
      DEFAULT_AGENT_SORT_DIRECTION = "asc"

      # Lists all registered agents with their details
      #
      # Uses AgentRegistry to discover agents from both file system
      # and execution history, ensuring deleted agents with history
      # are still visible. Separates agents and workflows for tabbed display.
      # Deleted agents are shown in a separate tab.
      #
      # @return [void]
      def index
        all_items = AgentRegistry.all_with_details

        # Filter to only agents (not workflows)
        all_agents = all_items.reject { |a| a[:is_workflow] }

        # Separate active and deleted agents
        @agents = all_agents.select { |a| a[:active] }
        @deleted_agents = all_agents.reject { |a| a[:active] }

        # Parse and apply sorting to both lists
        @sort_params = parse_agent_sort_params
        @agents = sort_agents(@agents)
        @deleted_agents = sort_agents(@deleted_agents)

        # Group active agents by type for sub-tabs
        @agents_by_type = {
          agent: @agents.select { |a| a[:agent_type] == "agent" },
          embedder: @agents.select { |a| a[:agent_type] == "embedder" },
          speaker: @agents.select { |a| a[:agent_type] == "speaker" },
          transcriber: @agents.select { |a| a[:agent_type] == "transcriber" },
          image_generator: @agents.select { |a| a[:agent_type] == "image_generator" },
          router: @agents.select { |a| a[:agent_type] == "router" }
        }

        @agent_count = @agents.size
        @deleted_count = @deleted_agents.size
      rescue => e
        Rails.logger.error("[RubyLLM::Agents] Error loading agents: #{e.message}")
        @agents = []
        @deleted_agents = []
        @agents_by_type = {agent: [], embedder: [], speaker: [], transcriber: [], image_generator: [], router: []}
        @agent_count = 0
        @deleted_count = 0
        @sort_params = {column: DEFAULT_AGENT_SORT_COLUMN, direction: DEFAULT_AGENT_SORT_DIRECTION}
        flash.now[:alert] = "Error loading agents list"
      end

      # Shows detailed view for a specific agent
      #
      # Loads agent configuration (if class exists), statistics,
      # filtered executions, and chart data for visualization.
      # Works for both active agents and deleted agents with history.
      #
      # @return [void]
      def show
        @agent_type = CGI.unescape(params[:id])
        @agent_class = AgentRegistry.find(@agent_type)
        @agent_active = @agent_class.present?

        load_agent_stats
        load_filter_options
        load_filtered_executions
        load_chart_data

        if @agent_class
          load_agent_config
          # Load circuit breaker status for agents that support reliability
          load_circuit_breaker_status if @agent_type_kind.in?(%w[agent router])
        end
      rescue => e
        Rails.logger.error("[RubyLLM::Agents] Error loading agent #{@agent_type}: #{e.message}")
        redirect_to ruby_llm_agents.agents_path, alert: "Error loading agent details"
      end

      # Saves dashboard overrides for an agent's overridable settings
      #
      # Only persists values for fields the agent has declared as
      # `overridable: true` in its DSL. Ignores all other fields.
      #
      # @return [void]
      def update
        @agent_type = CGI.unescape(params[:id])
        @agent_class = AgentRegistry.find(@agent_type)

        unless @agent_class
          redirect_to ruby_llm_agents.agents_path, alert: "Agent not found"
          return
        end

        allowed = @agent_class.overridable_fields.map(&:to_s)
        if allowed.empty?
          redirect_to agent_path(@agent_type), alert: "This agent has no overridable fields"
          return
        end

        # Build settings hash from permitted params, only for overridable fields
        settings = {}
        allowed.each do |field|
          next unless params.dig(:override, field).present?

          raw = params[:override][field]
          settings[field] = coerce_override_value(field, raw)
        end

        override = AgentOverride.find_or_initialize_by(agent_type: @agent_type)

        if settings.empty?
          # No overrides left — delete the record
          override.destroy if override.persisted?
          redirect_to agent_path(@agent_type), notice: "Overrides cleared"
        else
          override.settings = settings
          if override.save
            redirect_to agent_path(@agent_type), notice: "Overrides saved"
          else
            redirect_to agent_path(@agent_type), alert: "Failed to save overrides"
          end
        end
      end

      # Removes all dashboard overrides for an agent
      #
      # @return [void]
      def reset_overrides
        @agent_type = CGI.unescape(params[:id])
        override = AgentOverride.find_by(agent_type: @agent_type)
        override&.destroy
        redirect_to agent_path(@agent_type), notice: "Overrides cleared"
      end

      private

      # Loads all-time and today's statistics for the agent
      #
      # @return [void]
      def load_agent_stats
        base = tenant_scoped_executions
        @stats = base.stats_for(@agent_type, period: :all_time)
        @stats_today = base.stats_for(@agent_type, period: :today)

        # Additional stats for new schema fields
        agent_scope = base.by_agent(@agent_type)
        @cache_hit_rate = agent_scope.cache_hit_rate
        @streaming_rate = agent_scope.streaming_rate
        @avg_ttft = agent_scope.avg_time_to_first_token
      end

      # Loads available filter options from execution history
      #
      # Uses a single optimized query to fetch all filter values
      # (versions, models, temperatures) avoiding N+1 queries.
      #
      # @return [void]
      def load_filter_options
        # Single query to get all filter options (fixes N+1)
        base = tenant_scoped_executions.by_agent(@agent_type)
        filter_data = base
          .where.not(model_id: nil)
          .or(base.where.not(temperature: nil))
          .pluck(:model_id, :temperature)

        @models = filter_data.map(&:first).compact.uniq.sort
        @temperatures = filter_data.map(&:last).compact.uniq.sort
      end

      # Loads paginated and filtered executions with statistics
      #
      # Sets @executions, @pagination, and @filter_stats for the view.
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

      # Builds a filtered scope for the current agent's executions
      #
      # Applies filters in order: status, model, temperature, time.
      # Each filter is optional and only applied if values are provided.
      #
      # @return [ActiveRecord::Relation] Filtered execution scope
      def build_filtered_scope
        scope = tenant_scoped_executions.by_agent(@agent_type)

        # Apply status filter with validation
        statuses = parse_array_param(:statuses)
        scope = apply_status_filter(scope, statuses) if statuses.any?

        # Apply model filter
        models = parse_array_param(:models)
        scope = scope.where(model_id: models) if models.any?

        # Apply temperature filter
        temperatures = parse_array_param(:temperatures)
        scope = scope.where(temperature: temperatures) if temperatures.any?

        # Apply time range filter with validation
        days = parse_days_param
        apply_time_filter(scope, days)
      end

      # Loads chart data for agent performance visualization
      #
      # Fetches 30-day trend analysis and status/finish_reason distribution for charts.
      #
      # @return [void]
      def load_chart_data
        base = tenant_scoped_executions
        @trend_data = base.trend_analysis(agent_type: @agent_type, days: 30)
        @status_distribution = base.by_agent(@agent_type).group(:status).count
        @finish_reason_distribution = base.by_agent(@agent_type).finish_reason_distribution
      end

      # Loads the current agent class configuration
      #
      # Extracts DSL-configured values from the agent class for display.
      # Only called if the agent class still exists.
      # Detects agent type and loads appropriate config.
      #
      # @return [void]
      # Loads agent configuration using AgentRegistry
      def load_agent_config
        @agent_type_kind = AgentRegistry.send(:detect_agent_type, @agent_class)
        @config = AgentRegistry.config_for(@agent_class)
      end

      # Loads circuit breaker status for the agent's models
      #
      # Checks the primary model and any fallback models configured.
      # Only returns data if reliability features are enabled.
      #
      # @return [void]
      def load_circuit_breaker_status
        return unless @agent_class.respond_to?(:reliability_config)

        config = begin
          @agent_class.reliability_config
        rescue
          nil
        end
        return unless config

        # Collect all models: primary + fallbacks
        models_to_check = [@agent_class.model]
        models_to_check.concat(config[:fallback_models]) if config[:fallback_models].present?
        models_to_check = models_to_check.compact.uniq

        return if models_to_check.empty?

        breaker_config = config[:circuit_breaker] || {}
        errors_threshold = breaker_config[:errors] || 10
        window = breaker_config[:within] || 60
        cooldown = breaker_config[:cooldown] || 300

        @circuit_breaker_status = {}

        models_to_check.each do |model_id|
          breaker = CircuitBreaker.new(
            @agent_type,
            model_id,
            errors: errors_threshold,
            within: window,
            cooldown: cooldown
          )

          status = {
            open: breaker.open?,
            threshold: errors_threshold
          }

          # Get additional details
          if breaker.open?
            # Calculate remaining cooldown (approximate)
            status[:cooldown_remaining] = cooldown
          else
            # Get current failure count if available
            status[:failure_count] = breaker.failure_count
          end

          @circuit_breaker_status[model_id] = status
        end
      rescue => e
        Rails.logger.debug("[RubyLLM::Agents] Could not load circuit breaker status: #{e.message}")
        @circuit_breaker_status = {}
      end

      # Parses and validates sort parameters for agents list
      #
      # @return [Hash] Contains :column and :direction keys
      def parse_agent_sort_params
        column = params[:sort].to_s
        direction = params[:direction].to_s.downcase

        {
          column: AGENT_SORTABLE_COLUMNS.include?(column) ? column : DEFAULT_AGENT_SORT_COLUMN,
          direction: %w[asc desc].include?(direction) ? direction : DEFAULT_AGENT_SORT_DIRECTION
        }
      end

      # Sorts agents array based on sort params
      #
      # @param agents [Array<Hash>] Array of agent hashes
      # @return [Array<Hash>] Sorted array
      def sort_agents(agents)
        column = @sort_params[:column].to_sym
        direction = @sort_params[:direction]

        sorted = agents.sort_by do |agent|
          value = agent[column]
          # Handle nil values - put them at the end
          case column
          when :last_executed
            value || Time.at(0)
          when :execution_count, :total_cost, :success_rate
            value || 0
          else
            value.to_s.downcase
          end
        end

        (direction == "desc") ? sorted.reverse : sorted
      end

      # Coerces an override value from the form string to the appropriate Ruby type
      #
      # @param field [String] The field name
      # @param raw [String] The raw string value from the form
      # @return [Object] The coerced value
      def coerce_override_value(field, raw)
        case field
        when "temperature"
          raw.to_f
        when "timeout"
          raw.to_i
        when "streaming"
          ActiveModel::Type::Boolean.new.cast(raw)
        else
          raw.to_s
        end
      end
    end
  end
end
