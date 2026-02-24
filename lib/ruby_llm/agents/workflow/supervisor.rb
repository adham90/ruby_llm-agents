# frozen_string_literal: true

module RubyLLM
  module Agents
    class Workflow
      # Supervisor loop execution logic
      #
      # A supervisor is an orchestrator agent that loops, delegating
      # to sub-agents via DelegateTool until CompleteTool is called
      # or max_turns is reached.
      #
      # @example DSL usage
      #   class ResearchWorkflow < RubyLLM::Agents::Workflow
      #     supervisor OrchestratorAgent, max_turns: 10
      #
      #     delegate :researcher, ResearchAgent
      #     delegate :writer,     WriterAgent
      #   end
      #
      module Supervisor
        # Execute the supervisor loop
        #
        # @param workflow_class [Class] The workflow class
        # @param context [WorkflowContext] Shared context
        # @param parent_execution_id [Integer, nil]
        # @param root_execution_id [Integer, nil]
        # @return [Hash] Step timings from delegated calls
        def self.run(workflow_class:, context:, parent_execution_id: nil, root_execution_id: nil)
          config = workflow_class.supervisor_config
          return {} unless config

          supervisor_agent = config[:agent_class]
          max_turns = config[:max_turns] || 10
          delegates = workflow_class.delegate_agents

          # Build the delegate tool with the configured agents
          delegate_tool = DelegateTool.for(
            agents: delegates,
            context: context,
            parent_execution_id: parent_execution_id,
            root_execution_id: root_execution_id
          )

          step_timings = {}
          started_at = Time.current

          # Clear thread-local completion signal
          Thread.current[:workflow_supervisor_complete] = false
          Thread.current[:workflow_supervisor_result] = nil

          begin
            # Build a single chat session for the supervisor
            tools = [delegate_tool, CompleteTool]

            # Inject tools into the supervisor agent's options
            # The supervisor uses .ask() with the initial prompt
            initial_prompt = build_initial_prompt(context, delegates)

            max_turns.times do |turn|
              break if Thread.current[:workflow_supervisor_complete]

              result = supervisor_agent.ask(
                initial_prompt,
                tools: tools,
                parent_execution_id: parent_execution_id,
                root_execution_id: root_execution_id
              )

              context.store_step_result(:"supervisor_turn_#{turn}", result)
              step_timings[:"supervisor_turn_#{turn}"] = {
                started_at: started_at,
                completed_at: Time.current,
                duration_ms: ((Time.current - started_at) * 1000).round
              }

              # If the supervisor called complete, we're done
              break if Thread.current[:workflow_supervisor_complete]

              # Update prompt for next turn with accumulated context
              initial_prompt = "Continue with the task. Previous results are in context."
            end

            # Store the final result
            if Thread.current[:workflow_supervisor_result]
              context[:supervisor_final_result] = Thread.current[:workflow_supervisor_result]
            end
          ensure
            Thread.current[:workflow_supervisor_complete] = nil
            Thread.current[:workflow_supervisor_result] = nil
          end

          step_timings
        end

        def self.build_initial_prompt(context, delegates)
          agent_list = delegates.keys.map { |name| "- #{name}" }.join("\n")
          params_desc = context.params.map { |k, v| "#{k}: #{v}" }.join(", ")

          <<~PROMPT
            You are a supervisor orchestrating a team of specialized agents.

            Available agents:
            #{agent_list}

            Task parameters: #{params_desc}

            Use the delegate tool to assign work to agents, then use the complete tool when all work is done.
          PROMPT
        end
      end
    end
  end
end
