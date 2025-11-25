# frozen_string_literal: true

# This file is auto-generated from the current state of the database.
# It represents the schema used for testing the gem.

ActiveRecord::Schema.define do
  create_table :ruby_llm_agents_executions, force: :cascade do |t|
    # Agent identification
    t.string :agent_type, null: false
    t.string :agent_version, default: "1.0"

    # Model configuration
    t.string :model_id, null: false
    t.string :model_provider
    t.decimal :temperature, precision: 3, scale: 2

    # Timing
    t.datetime :started_at, null: false
    t.datetime :completed_at
    t.integer :duration_ms

    # Status
    t.string :status, default: "success", null: false

    # Token usage
    t.integer :input_tokens
    t.integer :output_tokens
    t.integer :total_tokens
    t.integer :cached_tokens, default: 0
    t.integer :cache_creation_tokens, default: 0

    # Costs (in dollars, 6 decimal precision)
    t.decimal :input_cost, precision: 12, scale: 6
    t.decimal :output_cost, precision: 12, scale: 6
    t.decimal :total_cost, precision: 12, scale: 6

    # Data (JSON for SQLite)
    t.json :parameters, null: false, default: {}
    t.json :response, default: {}
    t.json :metadata, null: false, default: {}

    # Error tracking
    t.string :error_class
    t.text :error_message

    t.timestamps
  end

  add_index :ruby_llm_agents_executions, :agent_type
  add_index :ruby_llm_agents_executions, :status
  add_index :ruby_llm_agents_executions, :created_at
  add_index :ruby_llm_agents_executions, [:agent_type, :created_at]
  add_index :ruby_llm_agents_executions, [:agent_type, :status]
  add_index :ruby_llm_agents_executions, [:agent_type, :agent_version]
  add_index :ruby_llm_agents_executions, :duration_ms
  add_index :ruby_llm_agents_executions, :total_cost
end
