# frozen_string_literal: true

module RubyLLM
  module Agents
    # Service for discovering and listing available agents
    #
    # Combines two sources to ensure complete agent discovery:
    # 1. File system - Classes inheriting from ApplicationAgent in app/agents/
    # 2. Execution history - Agent types that have execution records
    #
    # This ensures visibility of both current agents and deleted agents
    # that still have execution history.
    #
    # @example Getting all agent names
    #   AgentRegistry.all #=> ["SearchAgent", "SummaryAgent"]
    #
    # @example Getting detailed info
    #   AgentRegistry.all_with_details.each do |agent|
    #     puts "#{agent[:name]}: #{agent[:execution_count]} executions"
    #   end
    #
    # @api public
    class AgentRegistry
      class << self
        # Returns all unique agent type names
        #
        # @return [Array<String>] Sorted list of agent class names
        def all
          (file_system_agents + execution_agents).uniq.sort
        end

        # Finds an agent class by type name
        #
        # @param agent_type [String] The agent class name
        # @return [Class, nil] The agent class, or nil if not found
        def find(agent_type)
          agent_type.safe_constantize
        end

        # Checks if an agent class is currently defined
        #
        # @param agent_type [String] The agent class name
        # @return [Boolean] true if the class exists
        def exists?(agent_type)
          find(agent_type).present?
        end

        # Returns detailed info about all agents
        #
        # @return [Array<Hash>] Agent info hashes with configuration and stats
        def all_with_details
          all.map do |agent_type|
            build_agent_info(agent_type)
          end
        end

        private

        # Finds agent classes from the file system
        #
        # @return [Array<String>] Agent class names
        def file_system_agents
          # Ensure all agent classes are loaded
          eager_load_agents!

          # Find all descendants of the base class
          base_class = RubyLLM::Agents::Base
          base_class.descendants.map(&:name).compact
        rescue StandardError => e
          Rails.logger.error("[RubyLLM::Agents] Error loading agents from file system: #{e.message}")
          []
        end

        # Finds agent types from execution history
        #
        # @return [Array<String>] Agent class names with execution records
        def execution_agents
          Execution.distinct.pluck(:agent_type).compact
        rescue StandardError => e
          Rails.logger.error("[RubyLLM::Agents] Error loading agents from executions: #{e.message}")
          []
        end

        # Eager loads all agent files to register descendants
        #
        # @return [void]
        def eager_load_agents!
          agents_path = Rails.root.join("app", "agents")
          return unless agents_path.exist?

          Dir.glob(agents_path.join("**", "*.rb")).each do |file|
            require_dependency file
          rescue LoadError, StandardError => e
            Rails.logger.error("[RubyLLM::Agents] Failed to load agent file #{file}: #{e.message}")
          end
        end

        # Builds detailed info hash for an agent
        #
        # @param agent_type [String] The agent class name
        # @return [Hash] Agent info including config and stats
        def build_agent_info(agent_type)
          agent_class = find(agent_type)
          stats = fetch_stats(agent_type)

          {
            name: agent_type,
            class: agent_class,
            active: agent_class.present?,
            version: agent_class&.version || "N/A",
            model: agent_class&.model || "N/A",
            temperature: agent_class&.temperature,
            timeout: agent_class&.timeout,
            cache_enabled: agent_class&.cache_enabled? || false,
            cache_ttl: agent_class&.cache_ttl,
            params: agent_class&.params || {},
            execution_count: stats[:count],
            total_cost: stats[:total_cost],
            total_tokens: stats[:total_tokens],
            avg_duration_ms: stats[:avg_duration_ms],
            success_rate: stats[:success_rate],
            error_rate: stats[:error_rate],
            last_executed: last_execution_time(agent_type)
          }
        end

        # Fetches statistics for an agent
        #
        # @param agent_type [String] The agent class name
        # @return [Hash] Statistics hash
        def fetch_stats(agent_type)
          Execution.stats_for(agent_type, period: :all_time)
        rescue StandardError
          { count: 0, total_cost: 0, total_tokens: 0, avg_duration_ms: 0, success_rate: 0, error_rate: 0 }
        end

        # Gets the timestamp of the last execution for an agent
        #
        # @param agent_type [String] The agent class name
        # @return [Time, nil] Last execution time or nil
        def last_execution_time(agent_type)
          Execution.by_agent(agent_type).order(created_at: :desc).first&.created_at
        rescue StandardError
          nil
        end
      end
    end
  end
end
