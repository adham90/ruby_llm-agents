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

          # Find all descendants of all base classes
          agents = RubyLLM::Agents::Base.descendants.map(&:name).compact
          embedders = RubyLLM::Agents::Embedder.descendants.map(&:name).compact
          moderators = RubyLLM::Agents::Moderator.descendants.map(&:name).compact
          speakers = RubyLLM::Agents::Speaker.descendants.map(&:name).compact
          transcribers = RubyLLM::Agents::Transcriber.descendants.map(&:name).compact
          image_generators = RubyLLM::Agents::ImageGenerator.descendants.map(&:name).compact

          (agents + embedders + moderators + speakers + transcribers + image_generators).uniq
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
        # Uses the configured autoload paths from RubyLLM::Agents.configuration
        # to ensure agents are discovered in the correct directories.
        #
        # @return [void]
        def eager_load_agents!
          RubyLLM::Agents.configuration.all_autoload_paths.each do |relative_path|
            path = Rails.root.join(relative_path)
            next unless path.exist?

            Dir.glob(path.join("**", "*.rb")).each do |file|
              require_dependency file
            rescue LoadError, StandardError => e
              Rails.logger.error("[RubyLLM::Agents] Failed to load file #{file}: #{e.message}")
            end
          end
        end

        # Builds detailed info hash for an agent
        #
        # @param agent_type [String] The agent class name
        # @return [Hash] Agent info including config and stats
        def build_agent_info(agent_type)
          agent_class = find(agent_type)
          stats = fetch_stats(agent_type)

          # Detect the agent type (agent, embedder, moderator, speaker, transcriber, image_generator)
          detected_type = detect_agent_type(agent_class)

          {
            name: agent_type,
            class: agent_class,
            active: agent_class.present?,
            agent_type: detected_type,
            version: safe_call(agent_class, :version) || "N/A",
            description: safe_call(agent_class, :description),
            model: safe_call(agent_class, :model) || "N/A",
            temperature: safe_call(agent_class, :temperature),
            timeout: safe_call(agent_class, :timeout),
            cache_enabled: safe_call(agent_class, :cache_enabled?) || false,
            cache_ttl: safe_call(agent_class, :cache_ttl),
            params: safe_call(agent_class, :params) || {},
            execution_count: stats[:count],
            total_cost: stats[:total_cost],
            total_tokens: stats[:total_tokens],
            avg_duration_ms: stats[:avg_duration_ms],
            success_rate: stats[:success_rate],
            error_rate: stats[:error_rate],
            last_executed: last_execution_time(agent_type)
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

        # Detects the agent type from class hierarchy
        #
        # @param agent_class [Class, nil] The agent class
        # @return [String] "agent", "embedder", "moderator", "speaker", "transcriber", or "image_generator"
        def detect_agent_type(agent_class)
          return "agent" unless agent_class

          ancestors = agent_class.ancestors.map { |a| a.name.to_s }

          if ancestors.include?("RubyLLM::Agents::Embedder")
            "embedder"
          elsif ancestors.include?("RubyLLM::Agents::Moderator")
            "moderator"
          elsif ancestors.include?("RubyLLM::Agents::Speaker")
            "speaker"
          elsif ancestors.include?("RubyLLM::Agents::Transcriber")
            "transcriber"
          elsif ancestors.include?("RubyLLM::Agents::ImageGenerator")
            "image_generator"
          else
            "agent"
          end
        end
      end
    end
  end
end
