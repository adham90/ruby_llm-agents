# frozen_string_literal: true

module RubyLLM
  module Agents
    class Workflow
      # RubyLLM::Tool subclass injected into supervisor agents
      #
      # Lets the supervisor LLM delegate work to named sub-agents.
      # The tool receives the agent name and input, looks up the agent,
      # and calls it through the full middleware pipeline.
      #
      # @example LLM tool call
      #   delegate(agent: "researcher", input: "Find recent papers on AI safety")
      #
      class DelegateTool < RubyLLM::Tool
        description "Delegate a task to a specialized sub-agent. Use this to assign work to the appropriate agent."

        param :agent, desc: "Name of the agent to delegate to (e.g. 'researcher', 'writer')", required: true, type: :string
        param :input, desc: "The task or message to send to the agent", required: true, type: :string

        # Build a DelegateTool configured for specific agents
        #
        # @param agents [Hash{Symbol => Class}] agent name -> agent class mapping
        # @param context [WorkflowContext] shared workflow context
        # @param parent_execution_id [Integer, nil]
        # @param root_execution_id [Integer, nil]
        # @return [Class] configured DelegateTool subclass
        def self.for(agents:, context:, parent_execution_id: nil, root_execution_id: nil)
          captured_agents = agents
          captured_context = context
          captured_parent_id = parent_execution_id
          captured_root_id = root_execution_id

          Class.new(self) do
            define_method(:execute) do |agent:, input:|
              agent_name = agent.to_s.downcase.to_sym
              agent_class = captured_agents[agent_name]

              unless agent_class
                available = captured_agents.keys.join(", ")
                return "Unknown agent '#{agent}'. Available agents: #{available}"
              end

              begin
                call_params = {_ask_message: input}
                call_params[:parent_execution_id] = captured_parent_id if captured_parent_id
                call_params[:root_execution_id] = captured_root_id if captured_root_id

                result = agent_class.call(**call_params)

                # Store in context for aggregation
                delegation_key = :"delegate_#{agent_name}_#{captured_context.completed_step_count}"
                captured_context.store_step_result(delegation_key, result)

                content = result.respond_to?(:content) ? result.content : result
                case content
                when String then content
                when Hash then content.to_json
                when nil then "(no response)"
                else content.to_s
                end
              rescue => e
                "Error from #{agent}: #{e.message}"
              end
            end
          end
        end
      end
    end
  end
end
