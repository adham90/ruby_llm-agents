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

ActiveRecord::Schema[8.1].define(version: 2026_01_17_130001) do
  create_table "ruby_llm_agents_api_configurations", force: :cascade do |t|
    t.text "anthropic_api_key_ciphertext"
    t.text "bedrock_api_key_ciphertext"
    t.string "bedrock_region"
    t.text "bedrock_secret_key_ciphertext"
    t.text "bedrock_session_token_ciphertext"
    t.datetime "created_at", null: false
    t.text "deepseek_api_key_ciphertext"
    t.string "default_embedding_model"
    t.string "default_image_model"
    t.string "default_model"
    t.string "default_moderation_model"
    t.string "gemini_api_base"
    t.text "gemini_api_key_ciphertext"
    t.string "gpustack_api_base"
    t.text "gpustack_api_key_ciphertext"
    t.string "http_proxy"
    t.boolean "inherit_global_defaults", default: true
    t.integer "max_retries"
    t.text "mistral_api_key_ciphertext"
    t.string "ollama_api_base"
    t.text "ollama_api_key_ciphertext"
    t.string "openai_api_base"
    t.text "openai_api_key_ciphertext"
    t.string "openai_organization_id"
    t.string "openai_project_id"
    t.text "openrouter_api_key_ciphertext"
    t.text "perplexity_api_key_ciphertext"
    t.integer "request_timeout"
    t.decimal "retry_backoff_factor", precision: 5, scale: 2
    t.decimal "retry_interval", precision: 5, scale: 2
    t.decimal "retry_interval_randomness", precision: 5, scale: 2
    t.string "scope_id"
    t.string "scope_type", default: "global", null: false
    t.datetime "updated_at", null: false
    t.text "vertexai_credentials_ciphertext"
    t.string "vertexai_location"
    t.string "vertexai_project_id"
    t.string "xai_api_base"
    t.text "xai_api_key_ciphertext"
    t.index ["scope_id"], name: "idx_api_configs_scope_id"
    t.index ["scope_type", "scope_id"], name: "idx_api_configs_scope", unique: true
  end

  create_table "ruby_llm_agents_executions", force: :cascade do |t|
    t.string "agent_type", null: false
    t.string "agent_version", default: "1.0"
    t.json "attempts", default: [], null: false
    t.integer "attempts_count", default: 0, null: false
    t.integer "cache_creation_tokens", default: 0
    t.boolean "cache_hit", default: false
    t.datetime "cached_at"
    t.integer "cached_tokens", default: 0
    t.string "chosen_model_id"
    t.json "classification_result"
    t.datetime "completed_at"
    t.datetime "created_at", null: false
    t.integer "duration_ms"
    t.string "error_class"
    t.text "error_message"
    t.json "fallback_chain", default: [], null: false
    t.string "fallback_reason"
    t.string "finish_reason"
    t.decimal "input_cost", precision: 12, scale: 6
    t.integer "input_tokens"
    t.integer "messages_count", default: 0, null: false
    t.json "messages_summary", default: {}, null: false
    t.json "metadata", default: {}, null: false
    t.string "model_id", null: false
    t.string "model_provider"
    t.decimal "output_cost", precision: 12, scale: 6
    t.integer "output_tokens"
    t.json "parameters", default: {}, null: false
    t.bigint "parent_execution_id"
    t.boolean "rate_limited"
    t.string "request_id"
    t.json "response", default: {}
    t.string "response_cache_key"
    t.boolean "retryable"
    t.bigint "root_execution_id"
    t.string "routed_to"
    t.string "span_id"
    t.datetime "started_at", null: false
    t.string "status", default: "success", null: false
    t.boolean "streaming", default: false
    t.text "system_prompt"
    t.decimal "temperature", precision: 3, scale: 2
    t.string "tenant_id"
    t.integer "time_to_first_token_ms"
    t.json "tool_calls", default: [], null: false
    t.integer "tool_calls_count", default: 0, null: false
    t.decimal "total_cost", precision: 12, scale: 6
    t.integer "total_tokens"
    t.string "trace_id"
    t.datetime "updated_at", null: false
    t.text "user_prompt"
    t.string "workflow_id"
    t.string "workflow_step"
    t.string "workflow_type"
    t.index ["agent_type", "agent_version"], name: "idx_on_agent_type_agent_version_6719e42ac5"
    t.index ["agent_type", "created_at"], name: "index_ruby_llm_agents_executions_on_agent_type_and_created_at"
    t.index ["agent_type", "status"], name: "index_ruby_llm_agents_executions_on_agent_type_and_status"
    t.index ["agent_type"], name: "index_ruby_llm_agents_executions_on_agent_type"
    t.index ["attempts_count"], name: "index_ruby_llm_agents_executions_on_attempts_count"
    t.index ["chosen_model_id"], name: "index_ruby_llm_agents_executions_on_chosen_model_id"
    t.index ["created_at"], name: "index_ruby_llm_agents_executions_on_created_at"
    t.index ["duration_ms"], name: "index_ruby_llm_agents_executions_on_duration_ms"
    t.index ["messages_count"], name: "index_ruby_llm_agents_executions_on_messages_count"
    t.index ["parent_execution_id"], name: "index_ruby_llm_agents_executions_on_parent_execution_id"
    t.index ["request_id"], name: "index_ruby_llm_agents_executions_on_request_id"
    t.index ["response_cache_key"], name: "index_ruby_llm_agents_executions_on_response_cache_key"
    t.index ["root_execution_id"], name: "index_ruby_llm_agents_executions_on_root_execution_id"
    t.index ["status"], name: "index_ruby_llm_agents_executions_on_status"
    t.index ["tenant_id", "agent_type"], name: "index_ruby_llm_agents_executions_on_tenant_id_and_agent_type"
    t.index ["tenant_id", "created_at"], name: "index_ruby_llm_agents_executions_on_tenant_id_and_created_at"
    t.index ["tenant_id", "status"], name: "index_ruby_llm_agents_executions_on_tenant_id_and_status"
    t.index ["tenant_id"], name: "index_ruby_llm_agents_executions_on_tenant_id"
    t.index ["tool_calls_count"], name: "index_ruby_llm_agents_executions_on_tool_calls_count"
    t.index ["total_cost"], name: "index_ruby_llm_agents_executions_on_total_cost"
    t.index ["trace_id"], name: "index_ruby_llm_agents_executions_on_trace_id"
    t.index ["workflow_id", "workflow_step"], name: "idx_on_workflow_id_workflow_step_85a6d10aef"
    t.index ["workflow_id"], name: "index_ruby_llm_agents_executions_on_workflow_id"
    t.index ["workflow_type"], name: "index_ruby_llm_agents_executions_on_workflow_type"
  end

  create_table "ruby_llm_agents_tenant_budgets", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.decimal "daily_limit", precision: 12, scale: 6
    t.bigint "daily_token_limit"
    t.string "enforcement", default: "soft"
    t.boolean "inherit_global_defaults", default: true
    t.decimal "monthly_limit", precision: 12, scale: 6
    t.bigint "monthly_token_limit"
    t.string "name"
    t.json "per_agent_daily", default: {}, null: false
    t.json "per_agent_monthly", default: {}, null: false
    t.string "tenant_id", null: false
    t.datetime "updated_at", null: false
    t.index ["name"], name: "index_ruby_llm_agents_tenant_budgets_on_name"
    t.index ["tenant_id"], name: "index_ruby_llm_agents_tenant_budgets_on_tenant_id", unique: true
  end

  add_foreign_key "ruby_llm_agents_executions", "ruby_llm_agents_executions", column: "parent_execution_id", on_delete: :nullify
  add_foreign_key "ruby_llm_agents_executions", "ruby_llm_agents_executions", column: "root_execution_id", on_delete: :nullify
end
