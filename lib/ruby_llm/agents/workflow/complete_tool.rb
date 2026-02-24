# frozen_string_literal: true

module RubyLLM
  module Agents
    class Workflow
      # RubyLLM::Tool subclass that signals workflow completion
      #
      # When the supervisor LLM calls this tool, the supervisor loop
      # terminates and returns the result. Uses a thread-local to
      # communicate the completion signal back to the runner.
      #
      # @example LLM tool call
      #   complete(result: "The research and draft are done. Here's the summary: ...")
      #
      class CompleteTool < RubyLLM::Tool
        description "Signal that the workflow is complete and provide the final result. Call this when all required work has been done."

        param :result, desc: "The final result or summary to return", required: true, type: :string

        def execute(result:)
          Thread.current[:workflow_supervisor_complete] = true
          Thread.current[:workflow_supervisor_result] = result
          "Workflow completed successfully."
        end
      end
    end
  end
end
