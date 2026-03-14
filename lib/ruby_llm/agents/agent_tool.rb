# frozen_string_literal: true

module RubyLLM
  module Agents
    # Wraps an agent class as a RubyLLM::Tool so it can be used
    # in another agent's `tools` list. The LLM sees the sub-agent
    # as a callable tool and can invoke it with the agent's declared params.
    module AgentTool
      MAX_AGENT_TOOL_DEPTH = 5

      # Wraps an agent class as a RubyLLM::Tool subclass.
      #
      # @param agent_class [Class] A BaseAgent subclass
      # @param forwarded_params [Array<Symbol>] Params auto-injected from parent (excluded from LLM schema)
      # @param description_override [String, nil] Custom description for the tool
      # @param delegate [Boolean] Whether this tool represents an agent delegate (from `agents` DSL)
      # @return [Class] An anonymous RubyLLM::Tool subclass
      def self.for(agent_class, forwarded_params: [], description_override: nil, delegate: false)
        tool_name = derive_tool_name(agent_class)
        tool_desc = description_override || (agent_class.respond_to?(:description) ? agent_class.description : nil)
        agent_params = agent_class.respond_to?(:params) ? agent_class.params : {}
        captured_agent_class = agent_class
        captured_forwarded = Array(forwarded_params).map(&:to_sym)
        is_delegate = delegate

        Class.new(RubyLLM::Tool) do
          description tool_desc if tool_desc

          # Map agent params to tool params, excluding forwarded ones
          agent_params.each do |name, config|
            next if name.to_s.start_with?("_")
            next if captured_forwarded.include?(name.to_sym)

            param name,
              desc: config[:desc] || "#{name} parameter",
              required: config[:required] == true,
              type: AgentTool.map_type(config[:type])
          end

          # Store references on the class
          define_singleton_method(:agent_class) { captured_agent_class }
          define_singleton_method(:tool_name) { tool_name }
          define_singleton_method(:agent_delegate?) { is_delegate }
          define_singleton_method(:forwarded_params) { captured_forwarded }

          # Instance #name returns the derived tool name
          define_method(:name) { tool_name }

          define_method(:execute) do |**kwargs|
            depth = (Thread.current[:ruby_llm_agents_tool_depth] || 0) + 1
            if depth > MAX_AGENT_TOOL_DEPTH
              return "Error calling #{captured_agent_class.name}: Agent tool depth exceeded (max #{MAX_AGENT_TOOL_DEPTH})"
            end

            Thread.current[:ruby_llm_agents_tool_depth] = depth

            # Inject hierarchy context from thread-local (set by calling agent)
            caller_ctx = Thread.current[:ruby_llm_agents_caller_context]

            call_kwargs = kwargs.dup
            if caller_ctx
              call_kwargs[:_parent_execution_id] = caller_ctx.execution_id
              call_kwargs[:_root_execution_id] = caller_ctx.root_execution_id || caller_ctx.execution_id
              call_kwargs[:tenant] = caller_ctx.tenant_object if caller_ctx.tenant_id && !call_kwargs.key?(:tenant)

              # Inject forwarded params from the parent agent instance
              if captured_forwarded.any? && caller_ctx.agent_instance
                captured_forwarded.each do |param_name|
                  next if call_kwargs.key?(param_name)
                  if caller_ctx.agent_instance.respond_to?(param_name)
                    call_kwargs[param_name] = caller_ctx.agent_instance.send(param_name)
                  end
                end
              end
            end

            result = captured_agent_class.call(**call_kwargs)
            content = result.respond_to?(:content) ? result.content : result
            case content
            when String then content
            when Hash then content.to_json
            when nil then "(no response)"
            else content.to_s
            end
          rescue => e
            "Error calling #{captured_agent_class.name}: #{e.message}"
          ensure
            Thread.current[:ruby_llm_agents_tool_depth] = depth - 1
          end
        end
      end

      # Converts agent class name to tool name.
      #
      # @example
      #   ResearchAgent    -> "research"
      #   CodeReviewAgent  -> "code_review"
      #
      # @param agent_class [Class] The agent class
      # @return [String] Snake-cased tool name
      def self.derive_tool_name(agent_class)
        raw = agent_class.name.to_s.split("::").last
        raw.gsub(/([A-Z]+)([A-Z][a-z])/, '\1_\2')
          .gsub(/([a-z\d])([A-Z])/, '\1_\2')
          .downcase
          .sub(/_agent$/, "")
      end

      # Maps Ruby types to JSON Schema types for tool parameters.
      #
      # @param type [Class, Symbol, nil] Ruby type
      # @return [Symbol] JSON Schema type
      def self.map_type(type)
        case type
        when :integer then :integer
        when :number, :float then :number
        when :boolean then :boolean
        when :array then :array
        when :object then :object
        else
          # Handle class objects (Integer, Float, Array, Hash, etc.)
          if type.is_a?(Class)
            if type <= Integer
              :integer
            elsif type <= Float
              :number
            elsif type <= Array
              :array
            elsif type <= Hash
              :object
            elsif type == TrueClass || type == FalseClass
              :boolean
            else
              :string
            end
          else
            :string
          end
        end
      end
    end
  end
end
