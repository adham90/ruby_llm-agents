# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.1].define(version: 2026_02_14_000001) do
  create_table "organizations", force: :cascade do |t|
    t.boolean "active", default: true
    t.string "anthropic_api_key"
    t.datetime "created_at", null: false
    t.integer "employee_count"
    t.string "gemini_api_key"
    t.string "industry"
    t.string "name", null: false
    t.string "openai_api_key"
    t.string "plan", default: "free"
    t.string "slug", null: false
    t.datetime "updated_at", null: false
    t.index ["active"], name: "index_organizations_on_active"
    t.index ["plan"], name: "index_organizations_on_plan"
    t.index ["slug"], name: "index_organizations_on_slug", unique: true
  end

  create_table "ruby_llm_agents_execution_details", force: :cascade do |t|
    t.json "attempts", default: [], null: false
    t.integer "cache_creation_tokens", default: 0
    t.datetime "cached_at"
    t.json "classification_result"
    t.datetime "created_at", null: false
    t.text "error_message"
    t.integer "execution_id", null: false
    t.json "fallback_chain"
    t.json "messages_summary", default: {}, null: false
    t.json "parameters", default: {}, null: false
    t.json "response", default: {}
    t.string "routed_to"
    t.text "system_prompt"
    t.json "tool_calls", default: [], null: false
    t.datetime "updated_at", null: false
    t.text "user_prompt"
    t.index ["execution_id"], name: "index_ruby_llm_agents_execution_details_on_execution_id", unique: true
  end

  create_table "ruby_llm_agents_executions", force: :cascade do |t|
    t.string "agent_type", null: false
    t.integer "attempts_count", default: 0, null: false
    t.boolean "cache_hit", default: false
    t.integer "cached_tokens", default: 0
    t.string "chosen_model_id"
    t.datetime "completed_at"
    t.datetime "created_at", null: false
    t.integer "duration_ms"
    t.string "error_class"
    t.string "execution_type", default: "chat"
    t.string "finish_reason"
    t.decimal "input_cost", precision: 12, scale: 6
    t.integer "input_tokens"
    t.integer "messages_count", default: 0, null: false
    t.json "metadata", default: {}, null: false
    t.string "model_id", null: false
    t.string "model_provider"
    t.decimal "output_cost", precision: 12, scale: 6
    t.integer "output_tokens"
    t.bigint "parent_execution_id"
    t.string "request_id"
    t.bigint "root_execution_id"
    t.datetime "started_at", null: false
    t.string "status", default: "success", null: false
    t.boolean "streaming", default: false
    t.decimal "temperature", precision: 3, scale: 2
    t.string "tenant_id"
    t.integer "tool_calls_count", default: 0, null: false
    t.decimal "total_cost", precision: 12, scale: 6
    t.integer "total_tokens"
    t.string "trace_id"
    t.datetime "updated_at", null: false
    t.index ["agent_type", "created_at"], name: "index_ruby_llm_agents_executions_on_agent_type_and_created_at"
    t.index ["agent_type", "status"], name: "index_ruby_llm_agents_executions_on_agent_type_and_status"
    t.index ["created_at"], name: "index_ruby_llm_agents_executions_on_created_at"
    t.index ["parent_execution_id"], name: "index_ruby_llm_agents_executions_on_parent_execution_id"
    t.index ["request_id"], name: "index_ruby_llm_agents_executions_on_request_id"
    t.index ["root_execution_id"], name: "index_ruby_llm_agents_executions_on_root_execution_id"
    t.index ["status"], name: "index_ruby_llm_agents_executions_on_status"
    t.index ["tenant_id", "agent_type"], name: "index_ruby_llm_agents_executions_on_tenant_id_and_agent_type"
    t.index ["tenant_id", "created_at"], name: "index_ruby_llm_agents_executions_on_tenant_id_and_created_at"
    t.index ["tenant_id", "status"], name: "index_ruby_llm_agents_executions_on_tenant_id_and_status"
    t.index ["trace_id"], name: "index_ruby_llm_agents_executions_on_trace_id"
  end

  create_table "ruby_llm_agents_tenants", force: :cascade do |t|
    t.boolean "active", default: true
    t.datetime "created_at", null: false
    t.decimal "daily_cost_spent", precision: 12, scale: 6, default: "0.0", null: false
    t.bigint "daily_error_count", default: 0, null: false
    t.bigint "daily_execution_limit"
    t.bigint "daily_executions_count", default: 0, null: false
    t.decimal "daily_limit", precision: 12, scale: 6
    t.date "daily_reset_date"
    t.bigint "daily_token_limit"
    t.bigint "daily_tokens_used", default: 0, null: false
    t.string "enforcement", default: "soft"
    t.boolean "inherit_global_defaults", default: true
    t.datetime "last_execution_at"
    t.string "last_execution_status"
    t.json "metadata", default: {}, null: false
    t.decimal "monthly_cost_spent", precision: 12, scale: 6, default: "0.0", null: false
    t.bigint "monthly_error_count", default: 0, null: false
    t.bigint "monthly_execution_limit"
    t.bigint "monthly_executions_count", default: 0, null: false
    t.decimal "monthly_limit", precision: 12, scale: 6
    t.date "monthly_reset_date"
    t.bigint "monthly_token_limit"
    t.bigint "monthly_tokens_used", default: 0, null: false
    t.string "name"
    t.json "per_agent_daily", default: {}, null: false
    t.json "per_agent_monthly", default: {}, null: false
    t.string "tenant_id", null: false
    t.integer "tenant_record_id"
    t.string "tenant_record_type"
    t.datetime "updated_at", null: false
    t.index ["active"], name: "index_ruby_llm_agents_tenants_on_active"
    t.index ["name"], name: "index_ruby_llm_agents_tenants_on_name"
    t.index ["tenant_id"], name: "index_ruby_llm_agents_tenants_on_tenant_id", unique: true
    t.index ["tenant_record_type", "tenant_record_id"], name: "index_ruby_llm_agents_tenant_budgets_on_tenant_record"
  end

  add_foreign_key "ruby_llm_agents_execution_details", "ruby_llm_agents_executions", column: "execution_id", on_delete: :cascade
  add_foreign_key "ruby_llm_agents_executions", "ruby_llm_agents_executions", column: "parent_execution_id", on_delete: :nullify
  add_foreign_key "ruby_llm_agents_executions", "ruby_llm_agents_executions", column: "root_execution_id", on_delete: :nullify
end
