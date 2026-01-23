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
      #
      # @return [void]
      def index
        all_items = AgentRegistry.all_with_details

        # Filter to only agents (not workflows)
        @agents = all_items.reject { |a| a[:is_workflow] }

        # Parse and apply sorting
        @sort_params = parse_agent_sort_params
        @agents = sort_agents(@agents)

        # Group agents by type for sub-tabs
        @agents_by_type = {
          agent: @agents.select { |a| a[:agent_type] == "agent" },
          embedder: @agents.select { |a| a[:agent_type] == "embedder" },
          moderator: @agents.select { |a| a[:agent_type] == "moderator" },
          speaker: @agents.select { |a| a[:agent_type] == "speaker" },
          transcriber: @agents.select { |a| a[:agent_type] == "transcriber" },
          image_generator: @agents.select { |a| a[:agent_type] == "image_generator" }
        }

        @agent_count = @agents.size
      rescue StandardError => e
        Rails.logger.error("[RubyLLM::Agents] Error loading agents: #{e.message}")
        @agents = []
        @agents_by_type = { agent: [], embedder: [], moderator: [], speaker: [], transcriber: [], image_generator: [] }
        @agent_count = 0
        @sort_params = { column: DEFAULT_AGENT_SORT_COLUMN, direction: DEFAULT_AGENT_SORT_DIRECTION }
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
          # Only load circuit breaker status for base agents
          load_circuit_breaker_status if @agent_type_kind == "agent"
        end
      rescue StandardError => e
        Rails.logger.error("[RubyLLM::Agents] Error loading agent #{@agent_type}: #{e.message}")
        redirect_to ruby_llm_agents.agents_path, alert: "Error loading agent details"
      end

      private

      # Loads all-time and today's statistics for the agent
      #
      # @return [void]
      def load_agent_stats
        @stats = Execution.stats_for(@agent_type, period: :all_time)
        @stats_today = Execution.stats_for(@agent_type, period: :today)

        # Additional stats for new schema fields
        agent_scope = Execution.by_agent(@agent_type)
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
        filter_data = Execution.by_agent(@agent_type)
                               .where.not(agent_version: nil)
                               .or(Execution.by_agent(@agent_type).where.not(model_id: nil))
                               .or(Execution.by_agent(@agent_type).where.not(temperature: nil))
                               .pluck(:agent_version, :model_id, :temperature)

        @versions = filter_data.map(&:first).compact.uniq.sort.reverse
        @models = filter_data.map { |d| d[1] }.compact.uniq.sort
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
      # Applies filters in order: status, version, model, temperature, time.
      # Each filter is optional and only applied if values are provided.
      #
      # @return [ActiveRecord::Relation] Filtered execution scope
      def build_filtered_scope
        scope = Execution.by_agent(@agent_type)

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

      # Loads chart data for agent performance visualization
      #
      # Fetches 30-day trend analysis and status/finish_reason distribution for charts.
      #
      # @return [void]
      def load_chart_data
        @trend_data = Execution.trend_analysis(agent_type: @agent_type, days: 30)
        @status_distribution = Execution.by_agent(@agent_type).group(:status).count
        @finish_reason_distribution = Execution.by_agent(@agent_type).finish_reason_distribution
        load_version_comparison
      end

      # Loads version comparison data if multiple versions exist
      #
      # Includes trend data for sparkline charts.
      #
      # @return [void]
      def load_version_comparison
        return unless @versions.size >= 2

        # Default to comparing two most recent versions
        v1 = params[:compare_v1] || @versions[0]
        v2 = params[:compare_v2] || @versions[1]

        comparison_data = Execution.compare_versions(@agent_type, v1, v2, period: :this_month)

        # Fetch trend data for sparklines
        v1_trend = Execution.version_trend_data(@agent_type, v1, days: 14)
        v2_trend = Execution.version_trend_data(@agent_type, v2, days: 14)

        @version_comparison = {
          v1: v1,
          v2: v2,
          data: comparison_data,
          v1_trend: v1_trend,
          v2_trend: v2_trend
        }
      rescue StandardError => e
        Rails.logger.debug("[RubyLLM::Agents] Version comparison error: #{e.message}")
        @version_comparison = nil
      end

      # Loads the current agent class configuration
      #
      # Extracts DSL-configured values from the agent class for display.
      # Only called if the agent class still exists.
      # Detects agent type and loads appropriate config.
      #
      # @return [void]
      def load_agent_config
        @agent_type_kind = AgentRegistry.send(:detect_agent_type, @agent_class)

        # Common config for all types
        @config = {
          model: safe_config_call(:model),
          version: safe_config_call(:version) || "N/A",
          description: safe_config_call(:description)
        }

        # Type-specific config
        case @agent_type_kind
        when "embedder"
          load_embedder_config
        when "moderator"
          load_moderator_config
        when "speaker"
          load_speaker_config
        when "transcriber"
          load_transcriber_config
        when "image_generator"
          load_image_generator_config
        else
          load_base_agent_config
        end
      end

      # Loads configuration specific to Base agents
      #
      # @return [void]
      def load_base_agent_config
        @config.merge!(
          temperature: safe_config_call(:temperature),
          timeout: safe_config_call(:timeout),
          cache_enabled: safe_config_call(:cache_enabled?) || false,
          cache_ttl: safe_config_call(:cache_ttl),
          params: safe_config_call(:params) || {},
          retries: safe_config_call(:retries),
          fallback_models: safe_config_call(:fallback_models),
          total_timeout: safe_config_call(:total_timeout),
          circuit_breaker: safe_config_call(:circuit_breaker_config)
        )
      end

      # Loads configuration specific to Embedders
      #
      # @return [void]
      def load_embedder_config
        @config.merge!(
          dimensions: safe_config_call(:dimensions),
          batch_size: safe_config_call(:batch_size),
          cache_enabled: safe_config_call(:cache_enabled?) || false,
          cache_ttl: safe_config_call(:cache_ttl)
        )
      end

      # Loads configuration specific to Moderators
      #
      # @return [void]
      def load_moderator_config
        @config.merge!(
          threshold: safe_config_call(:threshold),
          categories: safe_config_call(:categories)
        )
      end

      # Loads configuration specific to Speakers
      #
      # @return [void]
      def load_speaker_config
        @config.merge!(
          provider: safe_config_call(:provider),
          voice: safe_config_call(:voice),
          voice_id: safe_config_call(:voice_id),
          speed: safe_config_call(:speed),
          output_format: safe_config_call(:output_format),
          streaming: safe_config_call(:streaming?),
          ssml_enabled: safe_config_call(:ssml_enabled?),
          cache_enabled: safe_config_call(:cache_enabled?) || false,
          cache_ttl: safe_config_call(:cache_ttl)
        )
      end

      # Loads configuration specific to Transcribers
      #
      # @return [void]
      def load_transcriber_config
        @config.merge!(
          language: safe_config_call(:language),
          output_format: safe_config_call(:output_format),
          include_timestamps: safe_config_call(:include_timestamps),
          cache_enabled: safe_config_call(:cache_enabled?) || false,
          cache_ttl: safe_config_call(:cache_ttl),
          fallback_models: safe_config_call(:fallback_models)
        )
      end

      # Loads configuration specific to ImageGenerators
      #
      # @return [void]
      def load_image_generator_config
        @config.merge!(
          size: safe_config_call(:size),
          quality: safe_config_call(:quality),
          style: safe_config_call(:style),
          content_policy: safe_config_call(:content_policy),
          template: safe_config_call(:template_string),
          negative_prompt: safe_config_call(:negative_prompt),
          seed: safe_config_call(:seed),
          guidance_scale: safe_config_call(:guidance_scale),
          steps: safe_config_call(:steps),
          cache_enabled: safe_config_call(:cache_enabled?) || false,
          cache_ttl: safe_config_call(:cache_ttl)
        )
      end

      # Safely calls a method on the agent class, returning nil on error
      #
      # @param method [Symbol] The method to call
      # @return [Object, nil] The result or nil if error
      def safe_config_call(method)
        return nil unless @agent_class&.respond_to?(method)
        @agent_class.public_send(method)
      rescue StandardError
        nil
      end

      # Loads circuit breaker status for the agent's models
      #
      # Checks the primary model and any fallback models configured.
      # Only returns data if reliability features are enabled.
      #
      # @return [void]
      def load_circuit_breaker_status
        return unless @agent_class.respond_to?(:reliability_config)

        config = @agent_class.reliability_config rescue nil
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
      rescue StandardError => e
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

        direction == "desc" ? sorted.reverse : sorted
      end
    end
  end
end
