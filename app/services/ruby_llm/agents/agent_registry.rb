# frozen_string_literal: true

module RubyLLM
  module Agents
    # Service for discovering and listing available agents
    #
    # Combines two sources:
    # 1. File system - Classes inheriting from ApplicationAgent in app/agents/
    # 2. Execution history - Agent types that have execution records
    #
    # This ensures all agents are visible, including:
    # - Agents that have never been executed
    # - Deleted agents that still have execution history
    #
    class AgentRegistry
      class << self
        # Returns all unique agent type names (sorted)
        def all
          (file_system_agents + execution_agents).uniq.sort
        end

        # Returns agent class if it exists, nil if only in execution history
        def find(agent_type)
          agent_type.safe_constantize
        end

        # Check if an agent class is currently defined
        def exists?(agent_type)
          find(agent_type).present?
        end

        # Get detailed info about all agents
        def all_with_details
          all.map do |agent_type|
            build_agent_info(agent_type)
          end
        end

        private

        # Find agent classes defined in the file system
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

        # Find agent types from execution history
        def execution_agents
          Execution.distinct.pluck(:agent_type).compact
        rescue StandardError => e
          Rails.logger.error("[RubyLLM::Agents] Error loading agents from executions: #{e.message}")
          []
        end

        # Eager load all agent files to ensure descendants are registered
        def eager_load_agents!
          agents_path = Rails.root.join("app", "agents")
          return unless agents_path.exist?

          Dir.glob(agents_path.join("**", "*.rb")).each do |file|
            require_dependency file
          rescue LoadError, StandardError => e
            Rails.logger.error("[RubyLLM::Agents] Failed to load agent file #{file}: #{e.message}")
          end
        end

        # Build detailed info hash for an agent
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

        def fetch_stats(agent_type)
          Execution.stats_for(agent_type, period: :all_time)
        rescue StandardError
          { count: 0, total_cost: 0, total_tokens: 0, avg_duration_ms: 0, success_rate: 0, error_rate: 0 }
        end

        def last_execution_time(agent_type)
          Execution.by_agent(agent_type).order(created_at: :desc).first&.created_at
        rescue StandardError
          nil
        end
      end
    end
  end
end
