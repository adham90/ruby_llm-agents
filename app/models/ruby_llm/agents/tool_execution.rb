# frozen_string_literal: true

module RubyLLM
  module Agents
    # Tracks individual tool calls within an agent execution.
    #
    # Created in real-time as each tool runs (INSERT on start, UPDATE on complete),
    # enabling live dashboard views and queryable tool-level analytics.
    #
    # @example Querying tool executions
    #   execution.tool_executions.where(status: "error")
    #   ToolExecution.where(tool_name: "bash").where("duration_ms > ?", 10_000)
    #
    class ToolExecution < ::ActiveRecord::Base
      self.table_name = "ruby_llm_agents_tool_executions"

      VALID_STATUSES = %w[running success error timed_out cancelled].freeze

      belongs_to :execution, class_name: "RubyLLM::Agents::Execution"

      validates :tool_name, presence: true
      validates :status, presence: true, inclusion: {in: VALID_STATUSES}
    end
  end
end
