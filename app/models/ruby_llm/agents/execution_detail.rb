# frozen_string_literal: true

module RubyLLM
  module Agents
    # Stores large payload data for an execution (prompts, responses, tool calls, etc.)
    #
    # Separated from {Execution} to keep the main table lean for analytics queries.
    # Only created when there is detail data to store.
    #
    # @see Execution
    # @api public
    class ExecutionDetail < ::ActiveRecord::Base
      self.table_name = "ruby_llm_agents_execution_details"

      belongs_to :execution, class_name: "RubyLLM::Agents::Execution"
    end
  end
end
