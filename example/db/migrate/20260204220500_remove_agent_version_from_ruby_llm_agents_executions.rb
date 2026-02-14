# frozen_string_literal: true

# Migration to remove agent_version column (deprecated in favor of content-based cache keys)
class RemoveAgentVersionFromRubyLLMAgentsExecutions < ActiveRecord::Migration[8.1]
  def change
    # Remove the composite index first (if it exists)
    remove_index :ruby_llm_agents_executions, [:agent_type, :agent_version],
                 if_exists: true

    # Remove the deprecated column
    remove_column :ruby_llm_agents_executions, :agent_version, :string, default: "1.0"
  end
end
