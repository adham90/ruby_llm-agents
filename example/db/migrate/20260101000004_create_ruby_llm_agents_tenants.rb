# frozen_string_literal: true

class CreateRubyLLMAgentsTenants < ActiveRecord::Migration[8.1]
  def change
    create_table :ruby_llm_agents_tenants do |t|
      # Identity
      t.string :tenant_id, null: false
      t.string :name

      # Polymorphic association to user's tenant model (e.g., Organization, Account)
      t.string :tenant_record_type
      t.integer :tenant_record_id

      # Cost limits (in USD, 6 decimal precision)
      t.decimal :daily_limit, precision: 12, scale: 6
      t.decimal :monthly_limit, precision: 12, scale: 6

      # Token limits
      t.bigint :daily_token_limit
      t.bigint :monthly_token_limit

      # Execution/call limits
      t.bigint :daily_execution_limit
      t.bigint :monthly_execution_limit

      # Per-agent limits (JSON hash)
      t.json :per_agent_daily, null: false, default: {}
      t.json :per_agent_monthly, null: false, default: {}

      # Enforcement mode: "none", "soft", or "hard"
      t.string :enforcement, default: "soft"

      # Whether to inherit from global config for unset limits
      t.boolean :inherit_global_defaults, default: true

      # Status (for soft-delete/disable)
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

      # Last execution metadata
      t.datetime :last_execution_at
      t.string   :last_execution_status

      # Period tracking (for lazy reset)
      t.date :daily_reset_date
      t.date :monthly_reset_date

      # Extensible metadata (JSON)
      t.json :metadata, null: false, default: {}

      t.timestamps
    end

    add_index :ruby_llm_agents_tenants, :tenant_id, unique: true
    add_index :ruby_llm_agents_tenants, :name
    add_index :ruby_llm_agents_tenants, :active
    add_index :ruby_llm_agents_tenants,
              [:tenant_record_type, :tenant_record_id],
              name: "index_ruby_llm_agents_tenant_budgets_on_tenant_record"
  end
end
