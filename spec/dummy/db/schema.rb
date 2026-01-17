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

    # Streaming and finish
    t.boolean :streaming, default: false
    t.integer :time_to_first_token_ms
    t.string :finish_reason

    # Distributed tracing
    t.string :request_id
    t.string :trace_id
    t.string :span_id
    t.bigint :parent_execution_id
    t.bigint :root_execution_id

    # Routing and retries
    t.string :fallback_reason
    t.boolean :retryable
    t.boolean :rate_limited

    # Caching
    t.boolean :cache_hit, default: false
    t.string :response_cache_key
    t.datetime :cached_at

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

    # Prompts (for history/changelog)
    t.text :system_prompt
    t.text :user_prompt

    # Reliability features
    t.json :fallback_chain, default: []
    t.json :attempts, default: []
    t.integer :attempts_count, default: 0
    t.string :chosen_model_id

    # Tool calls tracking
    t.json :tool_calls, null: false, default: []
    t.integer :tool_calls_count, null: false, default: 0

    # Workflow support
    t.string :workflow_id
    t.string :workflow_type
    t.string :workflow_step
    t.string :routed_to
    t.json :classification_result

    # Multi-tenancy
    t.string :tenant_id

    # Messages summary for conversation context
    t.integer :messages_count, null: false, default: 0
    t.json :messages_summary, null: false, default: {}

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

  # Tracing indexes
  add_index :ruby_llm_agents_executions, :request_id
  add_index :ruby_llm_agents_executions, :trace_id
  add_index :ruby_llm_agents_executions, :parent_execution_id
  add_index :ruby_llm_agents_executions, :root_execution_id

  # Caching index
  add_index :ruby_llm_agents_executions, :response_cache_key

  # Tool calls index
  add_index :ruby_llm_agents_executions, :tool_calls_count

  # Multi-tenancy index
  add_index :ruby_llm_agents_executions, [:tenant_id, :agent_type]

  # Messages summary index
  add_index :ruby_llm_agents_executions, :messages_count

  # Tenant budgets table
  create_table :ruby_llm_agents_tenant_budgets, force: :cascade do |t|
    t.string :tenant_id, null: false
    t.string :name
    t.decimal :daily_limit, precision: 12, scale: 6
    t.decimal :monthly_limit, precision: 12, scale: 6
    t.bigint :daily_token_limit
    t.bigint :monthly_token_limit
    t.json :per_agent_daily, null: false, default: {}
    t.json :per_agent_monthly, null: false, default: {}
    t.string :enforcement, default: "soft"
    t.boolean :inherit_global_defaults, default: true

    t.timestamps
  end

  add_index :ruby_llm_agents_tenant_budgets, :tenant_id, unique: true
  add_index :ruby_llm_agents_tenant_budgets, :name

  # API configurations table for storing encrypted API keys and settings
  create_table :ruby_llm_agents_api_configurations, force: :cascade do |t|
    # Scope: 'global' or 'tenant'
    t.string :scope_type, null: false, default: "global"
    t.string :scope_id

    # Encrypted API Keys (Rails encrypts stores in same-named columns)
    t.text :openai_api_key
    t.text :anthropic_api_key
    t.text :gemini_api_key
    t.text :deepseek_api_key
    t.text :mistral_api_key
    t.text :perplexity_api_key
    t.text :openrouter_api_key
    t.text :gpustack_api_key
    t.text :xai_api_key
    t.text :ollama_api_key

    # AWS Bedrock
    t.text :bedrock_api_key
    t.text :bedrock_secret_key
    t.text :bedrock_session_token
    t.string :bedrock_region

    # Google Vertex AI
    t.text :vertexai_credentials
    t.string :vertexai_project_id
    t.string :vertexai_location

    # Custom Endpoints
    t.string :openai_api_base
    t.string :gemini_api_base
    t.string :ollama_api_base
    t.string :gpustack_api_base
    t.string :xai_api_base

    # OpenAI Options
    t.string :openai_organization_id
    t.string :openai_project_id

    # Default Models
    t.string :default_model
    t.string :default_embedding_model
    t.string :default_image_model
    t.string :default_moderation_model

    # Connection Settings
    t.integer :request_timeout
    t.integer :max_retries
    t.decimal :retry_interval, precision: 10, scale: 2
    t.decimal :retry_backoff_factor, precision: 10, scale: 2
    t.decimal :retry_interval_randomness, precision: 10, scale: 2
    t.string :http_proxy

    # Inheritance flag (for tenant configs)
    t.boolean :inherit_global_defaults, default: true

    t.timestamps
  end

  add_index :ruby_llm_agents_api_configurations, [:scope_type, :scope_id], unique: true
end
