# frozen_string_literal: true

module RubyLLM
  module Agents
    module DSL
      # DSL module for declaring sub-agents on an agent class.
      #
      # Provides two forms — simple list for common cases, block for
      # per-agent configuration:
      #
      # @example Simple form
      #   agents [ModelsAgent, ViewsAgent], forward: [:workspace_path]
      #
      # @example Block form
      #   agents do
      #     use ModelsAgent, timeout: 180, description: "Build models"
      #     use ViewsAgent
      #     forward :workspace_path, :project_id
      #     parallel true
      #   end
      #
      module Agents
        # Declares sub-agents for this agent class.
        #
        # @param list [Array<Class>, nil] Agent classes (simple form)
        # @param options [Hash] Global options (simple form)
        # @yield Configuration block (block form)
        # @return [Array<Hash>] Agent entries
        def agents(list = nil, **options, &block)
          if block
            config = AgentsConfig.new
            config.instance_eval(&block)
            @agents_config = config
          elsif list
            config = AgentsConfig.new
            Array(list).each { |a| config.use(a) }
            options.each { |k, v| config.send(k, *Array(v)) }
            @agents_config = config
          end
          @agents_config&.agent_entries || []
        end

        # Returns the agents configuration object.
        #
        # @return [AgentsConfig] Configuration (empty if no agents declared)
        def agents_config
          @agents_config ||
            (superclass.respond_to?(:agents_config) ? superclass.agents_config : nil) ||
            AgentsConfig.new
        end
      end
    end

    # Configuration object for the `agents` DSL.
    #
    # Holds the list of agent entries and global options like
    # `parallel`, `forward`, `max_depth`, and `instructions`.
    #
    class AgentsConfig
      attr_reader :agent_entries

      def initialize
        @agent_entries = []
        @options = {
          parallel: true,
          timeout: nil,
          max_depth: 5,
          forward: [],
          instructions: nil
        }
      end

      # Registers an agent class with optional per-agent overrides.
      #
      # @param agent_class [Class] A BaseAgent subclass
      # @param timeout [Integer, nil] Per-agent timeout override
      # @param description [String, nil] Per-agent description override
      def use(agent_class, timeout: nil, description: nil)
        @agent_entries << {
          agent_class: agent_class,
          timeout: timeout,
          description: description
        }
      end

      # @!group Global Options

      def parallel(value = true)
        @options[:parallel] = value
      end

      def timeout(seconds)
        @options[:timeout] = seconds
      end

      def max_depth(depth)
        @options[:max_depth] = depth
      end

      def instructions(text)
        @options[:instructions] = text
      end

      def forward(*params)
        @options[:forward] = params.flatten
      end

      # @!endgroup

      # @!group Query Methods

      def parallel?
        @options[:parallel]
      end

      def timeout_for(agent_class)
        entry = @agent_entries.find { |e| e[:agent_class] == agent_class }
        entry&.dig(:timeout) || @options[:timeout]
      end

      def forwarded_params
        @options[:forward]
      end

      def max_depth_value
        @options[:max_depth]
      end

      def instructions_text
        @options[:instructions]
      end

      def description_for(agent_class)
        entry = @agent_entries.find { |e| e[:agent_class] == agent_class }
        entry&.dig(:description)
      end

      # @!endgroup
    end
  end
end
