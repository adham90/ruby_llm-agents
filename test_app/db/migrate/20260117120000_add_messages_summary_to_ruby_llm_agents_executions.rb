# frozen_string_literal: true

# Migration to add conversation messages summary tracking to executions
#
# Stores a summary of conversation history (messages) passed to agents:
# - messages_count: Number of messages in the conversation
# - messages_summary: JSON summary with first/last messages (truncated)
#
# This provides visibility into conversation context without significant
# storage overhead compared to storing all messages.
#
# Run with: rails db:migrate
class AddMessagesSummaryToRubyLLMAgentsExecutions < ActiveRecord::Migration[8.1]
  def change
    # Add count of messages in the conversation
    add_column :ruby_llm_agents_executions, :messages_count, :integer, null: false, default: 0

    # Add summary JSON with first/last messages (truncated)
    # Structure: { "first": { "role": "user", "content": "..." }, "last": { "role": "assistant", "content": "..." } }
    add_column :ruby_llm_agents_executions, :messages_summary, :json, null: false, default: {}

    # Add index for filtering executions with conversation context
    add_index :ruby_llm_agents_executions, :messages_count
  end
end
