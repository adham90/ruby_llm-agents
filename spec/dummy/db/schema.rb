# frozen_string_literal: true

# This file is auto-generated from the current state of the database.
# It represents the schema used for testing the gem.

ActiveRecord::Schema.define do
  create_table :ruby_llm_agents_executions, force: :cascade do |t|
    # Agent identification
    t.string :agent_type, null: false
    t.string :execution_type, null: false, default: "chat"

    # Model configuration
    t.string :model_id, null: false
    t.string :model_provider
    t.decimal :temperature, precision: 3, scale: 2
    t.string :chosen_model_id

    # Status
    t.string :status, null: false, default: "running"
    t.string :finish_reason
    t.string :error_class

    # Timing
    t.datetime :started_at, null: false
    t.datetime :completed_at
    t.integer :duration_ms

    # Token usage
    t.integer :input_tokens, default: 0
    t.integer :output_tokens, default: 0
    t.integer :total_tokens, default: 0
    t.integer :cached_tokens, default: 0

    # Costs (in dollars, 6 decimal precision)
    t.decimal :input_cost, precision: 12, scale: 6
    t.decimal :output_cost, precision: 12, scale: 6
    t.decimal :total_cost, precision: 12, scale: 6

    # Caching
    t.boolean :cache_hit, default: false

    # Streaming
    t.boolean :streaming, default: false

    # Retry / Fallback
    t.integer :attempts_count, default: 1, null: false

    # Tool calls
    t.integer :tool_calls_count, default: 0, null: false

    # Distributed tracing
    t.string :trace_id
    t.string :request_id

    # Execution hierarchy (self-join)
    t.bigint :parent_execution_id
    t.bigint :root_execution_id

    # Multi-tenancy
    t.string :tenant_id

    # Conversation context
    t.integer :messages_count, default: 0, null: false

    # Flexible storage (niche fields, trace context, custom tags)
    t.json :metadata, null: false, default: {}

    t.timestamps
  end

  # Indexes: only what's actually queried
  add_index :ruby_llm_agents_executions, [:agent_type, :created_at]
  add_index :ruby_llm_agents_executions, [:agent_type, :status]
  add_index :ruby_llm_agents_executions, :status
  add_index :ruby_llm_agents_executions, :created_at
  add_index :ruby_llm_agents_executions, [:tenant_id, :created_at]
  add_index :ruby_llm_agents_executions, [:tenant_id, :status]
  add_index :ruby_llm_agents_executions, :trace_id
  add_index :ruby_llm_agents_executions, :request_id
  add_index :ruby_llm_agents_executions, :parent_execution_id
  add_index :ruby_llm_agents_executions, :root_execution_id

  # Execution details table (large payloads)
  create_table :ruby_llm_agents_execution_details, force: :cascade do |t|
    t.references :execution, null: false,
                 foreign_key: { to_table: :ruby_llm_agents_executions, on_delete: :cascade },
                 index: { unique: true }

    t.text     :error_message
    t.text     :system_prompt
    t.text     :user_prompt
    t.json     :response,             default: {}
    t.json     :messages_summary,     default: {}, null: false
    t.json     :tool_calls,           default: [], null: false
    t.json     :attempts,             default: [], null: false
    t.json     :fallback_chain
    t.json     :parameters,           default: {}, null: false
    t.string   :routed_to
    t.json     :classification_result
    t.datetime :cached_at
    t.integer  :cache_creation_tokens, default: 0

    t.timestamps
  end

  # Tenants table (renamed from tenant_budgets)
  create_table :ruby_llm_agents_tenants, force: :cascade do |t|
    # Identity
    t.string :tenant_id, null: false
    t.string :name

    # Polymorphic association to user's tenant model
    # Uses string type for tenant_record_id to support both integer and UUID primary keys
    t.string :tenant_record_type
    t.string :tenant_record_id

    # Budget limits (cost in USD)
    t.decimal :daily_limit, precision: 12, scale: 6
    t.decimal :monthly_limit, precision: 12, scale: 6

    # Token limits
    t.bigint :daily_token_limit
    t.bigint :monthly_token_limit

    # Execution limits
    t.bigint :daily_execution_limit
    t.bigint :monthly_execution_limit

    # Per-agent limits
    t.json :per_agent_daily, null: false, default: {}
    t.json :per_agent_monthly, null: false, default: {}

    # Enforcement
    t.string :enforcement, default: "soft"
    t.boolean :inherit_global_defaults, default: true

    # Status
    t.boolean :active, default: true

    # Usage counter columns (DB-based budget tracking)
    t.decimal :daily_cost_spent,        precision: 12, scale: 6, default: 0, null: false
    t.decimal :monthly_cost_spent,      precision: 12, scale: 6, default: 0, null: false
    t.bigint :daily_tokens_used,        default: 0, null: false
    t.bigint :monthly_tokens_used,      default: 0, null: false
    t.bigint :daily_executions_count,   default: 0, null: false
    t.bigint :monthly_executions_count, default: 0, null: false
    t.bigint :daily_error_count,        default: 0, null: false
    t.bigint :monthly_error_count,      default: 0, null: false
    t.datetime :last_execution_at
    t.string   :last_execution_status
    t.date :daily_reset_date
    t.date :monthly_reset_date

    # Extensible metadata
    t.json :metadata, null: false, default: {}

    t.timestamps
  end

  add_index :ruby_llm_agents_tenants, :tenant_id, unique: true
  add_index :ruby_llm_agents_tenants, :name
  add_index :ruby_llm_agents_tenants, :active
  add_index :ruby_llm_agents_tenants, [:tenant_record_type, :tenant_record_id], name: "index_tenants_on_tenant_record"

end
