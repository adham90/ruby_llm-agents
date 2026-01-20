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
          # Ensure all agent and workflow classes are loaded
          eager_load_agents!

          # Find all descendants of all base classes
          agents = RubyLLM::Agents::Base.descendants.map(&:name).compact
          workflows = RubyLLM::Agents::Workflow.descendants.map(&:name).compact
          embedders = RubyLLM::Agents::Embedder.descendants.map(&:name).compact
          moderators = RubyLLM::Agents::Moderator.descendants.map(&:name).compact
          speakers = RubyLLM::Agents::Speaker.descendants.map(&:name).compact
          transcribers = RubyLLM::Agents::Transcriber.descendants.map(&:name).compact
          image_generators = RubyLLM::Agents::ImageGenerator.descendants.map(&:name).compact

          (agents + workflows + embedders + moderators + speakers + transcribers + image_generators).uniq
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

        # Eager loads all agent and workflow files to register descendants
        #
        # @return [void]
        def eager_load_agents!
          %w[agents workflows embedders moderators speakers transcribers image_generators].each do |dir|
            path = Rails.root.join("app", dir)
            next unless path.exist?

            Dir.glob(path.join("**", "*.rb")).each do |file|
              require_dependency file
            rescue LoadError, StandardError => e
              Rails.logger.error("[RubyLLM::Agents] Failed to load file #{file}: #{e.message}")
            end
          end
        end

        # Returns only regular agents (non-workflows)
        #
        # @return [Array<Hash>] Agent info hashes for non-workflow agents
        def agents_only
          all_with_details.reject { |a| a[:is_workflow] }
        end

        # Returns only workflows
        #
        # @return [Array<Hash>] Agent info hashes for workflows only
        def workflows_only
          all_with_details.select { |a| a[:is_workflow] }
        end

        # Returns workflows filtered by type
        #
        # @param type [String, Symbol] The workflow type (pipeline, parallel, router)
        # @return [Array<Hash>] Filtered workflow info hashes
        def workflows_by_type(type)
          workflows_only.select { |w| w[:workflow_type] == type.to_s }
        end

        # Builds detailed info hash for an agent
        #
        # @param agent_type [String] The agent class name
        # @return [Hash] Agent info including config and stats
        def build_agent_info(agent_type)
          agent_class = find(agent_type)
          stats = fetch_stats(agent_type)

          # Detect the agent type (agent, workflow, embedder, moderator, speaker, transcriber)
          detected_type = detect_agent_type(agent_class)

          # Check if this is a workflow class vs a regular agent
          is_workflow = detected_type == "workflow"

          # Determine specific workflow type and children
          workflow_type = is_workflow ? detect_workflow_type(agent_class) : nil
          workflow_children = is_workflow ? extract_workflow_children(agent_class) : []

          {
            name: agent_type,
            class: agent_class,
            active: agent_class.present?,
            agent_type: detected_type,
            is_workflow: is_workflow,
            workflow_type: workflow_type,
            workflow_children: workflow_children,
            version: safe_call(agent_class, :version) || "N/A",
            description: safe_call(agent_class, :description),
            model: safe_call(agent_class, :model) || (is_workflow ? "workflow" : "N/A"),
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

        # Detects the specific workflow type from class hierarchy
        #
        # @param agent_class [Class, nil] The agent class
        # @return [String, nil] "pipeline", "parallel", "router", or nil
        def detect_workflow_type(agent_class)
          return nil unless agent_class

          ancestors = agent_class.ancestors.map { |a| a.name.to_s }

          if ancestors.include?("RubyLLM::Agents::Workflow::Pipeline")
            "pipeline"
          elsif ancestors.include?("RubyLLM::Agents::Workflow::Parallel")
            "parallel"
          elsif ancestors.include?("RubyLLM::Agents::Workflow::Router")
            "router"
          end
        end

        # Detects the agent type from class hierarchy
        #
        # @param agent_class [Class, nil] The agent class
        # @return [String] "agent", "workflow", "embedder", "moderator", "speaker", "transcriber", or "image_generator"
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
          elsif ancestors.include?("RubyLLM::Agents::Workflow")
            "workflow"
          else
            "agent"
          end
        end

        # Extracts child agents from workflow DSL configuration
        #
        # @param agent_class [Class, nil] The workflow class
        # @return [Array<Hash>] Array of child info hashes with :name, :agent, :type, :optional keys
        def extract_workflow_children(agent_class)
          return [] unless agent_class

          children = []

          if agent_class.respond_to?(:steps) && agent_class.steps.any?
            # Pipeline workflow - extract steps
            agent_class.steps.each do |name, config|
              children << {
                name: name,
                agent: config[:agent]&.name,
                type: "step",
                optional: config[:continue_on_error] || false
              }
            end
          elsif agent_class.respond_to?(:branches) && agent_class.branches.any?
            # Parallel workflow - extract branches
            agent_class.branches.each do |name, config|
              children << {
                name: name,
                agent: config[:agent]&.name,
                type: "branch",
                optional: config[:optional] || false
              }
            end
          elsif agent_class.respond_to?(:routes) && agent_class.routes.any?
            # Router workflow - extract routes
            agent_class.routes.each do |name, config|
              children << {
                name: name,
                agent: config[:agent]&.name,
                type: "route",
                description: config[:description]
              }
            end
          end

          children
        rescue StandardError => e
          Rails.logger.error("[RubyLLM::Agents] Error extracting workflow children: #{e.message}")
          []
        end
      end
    end
  end
end
