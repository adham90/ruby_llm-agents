# frozen_string_literal: true

# Schema definitions for each gem version
#
# Each method creates the schema that existed at that version,
# using raw SQL to avoid ActiveRecord model dependencies.
#
# The methods are named to match the migration steps and can be
# applied incrementally to simulate version upgrades.
module SchemaBuilder
  class << self
    # Version 0.1.0 - Initial executions table with basic fields
    #
    # This is the minimal schema that existed in the initial release.
    def v0_1_0_base
      connection = ActiveRecord::Base.connection

      connection.create_table :ruby_llm_agents_executions, force: false, if_not_exists: true do |t|
        # Agent identification
        t.string :agent_type, null: false

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

        # Costs (in dollars, 6 decimal precision)
        t.decimal :input_cost, precision: 12, scale: 6
        t.decimal :output_cost, precision: 12, scale: 6
        t.decimal :total_cost, precision: 12, scale: 6

        # Data (JSON)
        t.json :parameters, null: false, default: {}
        t.json :response, default: {}
        t.json :metadata, null: false, default: {}

        # Error tracking
        t.string :error_class
        t.text :error_message

        t.timestamps
      end

      # Basic indexes
      connection.add_index :ruby_llm_agents_executions, :agent_type, if_not_exists: true
      connection.add_index :ruby_llm_agents_executions, :status, if_not_exists: true
      connection.add_index :ruby_llm_agents_executions, :created_at, if_not_exists: true
      connection.add_index :ruby_llm_agents_executions, [:agent_type, :created_at], if_not_exists: true
      connection.add_index :ruby_llm_agents_executions, [:agent_type, :status], if_not_exists: true
      connection.add_index :ruby_llm_agents_executions, :duration_ms, if_not_exists: true
      connection.add_index :ruby_llm_agents_executions, :total_cost, if_not_exists: true
    end

    # Rollback for v0_1_0_base
    def v0_1_0_base_down
      connection = ActiveRecord::Base.connection
      connection.drop_table :ruby_llm_agents_executions, if_exists: true
    end

    # Version 0.2.3 - Added streaming, tracing, routing, caching, prompts
    def v0_2_3_streaming_tracing_caching
      connection = ActiveRecord::Base.connection
      table_name = :ruby_llm_agents_executions

      # Streaming and finish
      add_column_if_missing(connection, table_name, :streaming, :boolean, default: false)
      add_column_if_missing(connection, table_name, :time_to_first_token_ms, :integer)
      add_column_if_missing(connection, table_name, :finish_reason, :string)

      # Distributed tracing
      add_column_if_missing(connection, table_name, :request_id, :string)
      add_column_if_missing(connection, table_name, :trace_id, :string)
      add_column_if_missing(connection, table_name, :span_id, :string)
      add_column_if_missing(connection, table_name, :parent_execution_id, :bigint)
      add_column_if_missing(connection, table_name, :root_execution_id, :bigint)

      # Routing and retries
      add_column_if_missing(connection, table_name, :fallback_reason, :string)
      add_column_if_missing(connection, table_name, :retryable, :boolean)
      add_column_if_missing(connection, table_name, :rate_limited, :boolean)

      # Caching
      add_column_if_missing(connection, table_name, :cache_hit, :boolean, default: false)
      add_column_if_missing(connection, table_name, :response_cache_key, :string)
      add_column_if_missing(connection, table_name, :cached_at, :datetime)
      add_column_if_missing(connection, table_name, :cached_tokens, :integer, default: 0)
      add_column_if_missing(connection, table_name, :cache_creation_tokens, :integer, default: 0)

      # Prompts
      add_column_if_missing(connection, table_name, :system_prompt, :text)
      add_column_if_missing(connection, table_name, :user_prompt, :text)

      # Tracing indexes
      connection.add_index table_name, :request_id, if_not_exists: true
      connection.add_index table_name, :trace_id, if_not_exists: true
      connection.add_index table_name, :parent_execution_id, if_not_exists: true
      connection.add_index table_name, :root_execution_id, if_not_exists: true

      # Caching index
      connection.add_index table_name, :response_cache_key, if_not_exists: true
    end

    # Rollback for v0_2_3
    def v0_2_3_streaming_tracing_caching_down
      connection = ActiveRecord::Base.connection
      table_name = :ruby_llm_agents_executions

      columns_to_remove = %i[
        streaming time_to_first_token_ms finish_reason
        request_id trace_id span_id parent_execution_id root_execution_id
        fallback_reason retryable rate_limited
        cache_hit response_cache_key cached_at cached_tokens cache_creation_tokens
        system_prompt user_prompt
      ]

      columns_to_remove.each do |column|
        remove_column_if_exists(connection, table_name, column)
      end
    end

    # Version 0.3.3 - Added tool_calls
    def v0_3_3_tool_calls
      connection = ActiveRecord::Base.connection
      table_name = :ruby_llm_agents_executions

      # Tool calls tracking
      add_column_if_missing(connection, table_name, :tool_calls, :json, null: false, default: [])
      add_column_if_missing(connection, table_name, :tool_calls_count, :integer, null: false, default: 0)

      # Workflow orchestration
      add_column_if_missing(connection, table_name, :workflow_id, :string)
      add_column_if_missing(connection, table_name, :workflow_type, :string)
      add_column_if_missing(connection, table_name, :workflow_step, :string)
      add_column_if_missing(connection, table_name, :routed_to, :string)
      add_column_if_missing(connection, table_name, :classification_result, :json)

      # Tool calls index
      connection.add_index table_name, :tool_calls_count, if_not_exists: true

      # Workflow indexes
      connection.add_index table_name, :workflow_id, if_not_exists: true
      connection.add_index table_name, :workflow_type, if_not_exists: true
      add_composite_index_if_missing(connection, table_name, [:workflow_id, :workflow_step])
    end

    # Rollback for v0_3_3
    def v0_3_3_tool_calls_down
      connection = ActiveRecord::Base.connection
      table_name = :ruby_llm_agents_executions

      columns_to_remove = %i[
        tool_calls tool_calls_count
        workflow_id workflow_type workflow_step routed_to classification_result
      ]

      columns_to_remove.each do |column|
        remove_column_if_exists(connection, table_name, column)
      end
    end

    # Version 0.4.0 - Added reliability features (attempts, fallback_chain)
    def v0_4_0_reliability
      connection = ActiveRecord::Base.connection
      table_name = :ruby_llm_agents_executions

      # Attempts tracking
      add_column_if_missing(connection, table_name, :attempts, :json, null: false, default: [])
      add_column_if_missing(connection, table_name, :attempts_count, :integer, null: false, default: 0)
      add_column_if_missing(connection, table_name, :chosen_model_id, :string)
      add_column_if_missing(connection, table_name, :fallback_chain, :json, null: false, default: [])

      # Indexes
      connection.add_index table_name, :attempts_count, if_not_exists: true
      connection.add_index table_name, :chosen_model_id, if_not_exists: true
    end

    # Rollback for v0_4_0 reliability
    def v0_4_0_reliability_down
      connection = ActiveRecord::Base.connection
      table_name = :ruby_llm_agents_executions

      columns_to_remove = %i[attempts attempts_count chosen_model_id fallback_chain]

      columns_to_remove.each do |column|
        remove_column_if_exists(connection, table_name, column)
      end
    end

    # Version 0.4.0 - Create tenant_budgets table
    def v0_4_0_tenant_budgets
      connection = ActiveRecord::Base.connection

      connection.create_table :ruby_llm_agents_tenant_budgets, force: false, if_not_exists: true do |t|
        t.string :tenant_id, null: false
        t.decimal :daily_limit, precision: 12, scale: 6
        t.decimal :monthly_limit, precision: 12, scale: 6
        t.json :per_agent_daily, null: false, default: {}
        t.json :per_agent_monthly, null: false, default: {}
        t.string :enforcement, default: "soft"
        t.boolean :inherit_global_defaults, default: true

        t.timestamps
      end

      connection.add_index :ruby_llm_agents_tenant_budgets, :tenant_id, unique: true, if_not_exists: true
    end

    # Rollback for v0_4_0 tenant_budgets
    def v0_4_0_tenant_budgets_down
      connection = ActiveRecord::Base.connection
      connection.drop_table :ruby_llm_agents_tenant_budgets, if_exists: true
    end

    # Version 0.4.0 - Add tenant_id to executions
    def v0_4_0_tenant_id
      connection = ActiveRecord::Base.connection
      table_name = :ruby_llm_agents_executions

      add_column_if_missing(connection, table_name, :tenant_id, :string)

      connection.add_index table_name, :tenant_id, if_not_exists: true
      add_composite_index_if_missing(connection, table_name, [:tenant_id, :created_at])
      add_composite_index_if_missing(connection, table_name, [:tenant_id, :agent_type])
      add_composite_index_if_missing(connection, table_name, [:tenant_id, :status])
    end

    # Rollback for v0_4_0 tenant_id
    def v0_4_0_tenant_id_down
      connection = ActiveRecord::Base.connection
      table_name = :ruby_llm_agents_executions

      remove_column_if_exists(connection, table_name, :tenant_id)
    end

    # Version 0.4.0 - Add messages_summary to executions
    def v0_4_0_messages_summary
      connection = ActiveRecord::Base.connection
      table_name = :ruby_llm_agents_executions

      add_column_if_missing(connection, table_name, :messages_count, :integer, null: false, default: 0)
      add_column_if_missing(connection, table_name, :messages_summary, :json, null: false, default: {})

      connection.add_index table_name, :messages_count, if_not_exists: true
    end

    # Rollback for v0_4_0 messages_summary
    def v0_4_0_messages_summary_down
      connection = ActiveRecord::Base.connection
      table_name = :ruby_llm_agents_executions

      columns_to_remove = %i[messages_count messages_summary]

      columns_to_remove.each do |column|
        remove_column_if_exists(connection, table_name, column)
      end
    end

    # Version 0.4.0 - Add name to tenant_budgets
    def v0_4_0_tenant_name
      connection = ActiveRecord::Base.connection
      table_name = :ruby_llm_agents_tenant_budgets

      return unless connection.table_exists?(table_name)

      add_column_if_missing(connection, table_name, :name, :string)

      connection.add_index table_name, :name, if_not_exists: true
    end

    # Rollback for v0_4_0 tenant_name
    def v0_4_0_tenant_name_down
      connection = ActiveRecord::Base.connection
      table_name = :ruby_llm_agents_tenant_budgets

      return unless connection.table_exists?(table_name)

      remove_column_if_exists(connection, table_name, :name)
    end

    # Version 0.4.0 - Add token limits to tenant_budgets
    def v0_4_0_token_limits
      connection = ActiveRecord::Base.connection
      table_name = :ruby_llm_agents_tenant_budgets

      return unless connection.table_exists?(table_name)

      add_column_if_missing(connection, table_name, :daily_token_limit, :bigint)
      add_column_if_missing(connection, table_name, :monthly_token_limit, :bigint)
    end

    # Rollback for v0_4_0 token_limits
    def v0_4_0_token_limits_down
      connection = ActiveRecord::Base.connection
      table_name = :ruby_llm_agents_tenant_budgets

      return unless connection.table_exists?(table_name)

      columns_to_remove = %i[daily_token_limit monthly_token_limit]

      columns_to_remove.each do |column|
        remove_column_if_exists(connection, table_name, column)
      end
    end

    # Version 2.0.0 - Create execution_details table
    def v2_0_0_execution_details
      connection = ActiveRecord::Base.connection

      connection.create_table :ruby_llm_agents_execution_details, force: false, if_not_exists: true do |t|
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
    end

    # Rollback for v2_0_0 execution_details
    def v2_0_0_execution_details_down
      connection = ActiveRecord::Base.connection
      connection.drop_table :ruby_llm_agents_execution_details, if_exists: true
    end

    # Version 2.0.0 - Rename tenant_budgets to tenants
    def v2_0_0_rename_tenants
      connection = ActiveRecord::Base.connection

      return unless connection.table_exists?(:ruby_llm_agents_tenant_budgets)
      return if connection.table_exists?(:ruby_llm_agents_tenants)

      connection.rename_table :ruby_llm_agents_tenant_budgets, :ruby_llm_agents_tenants

      add_column_if_missing(connection, :ruby_llm_agents_tenants, :active, :boolean, default: true)
      add_column_if_missing(connection, :ruby_llm_agents_tenants, :metadata, :json, null: false, default: {})

      connection.add_index :ruby_llm_agents_tenants, :active, if_not_exists: true
    end

    # Rollback for v2_0_0 rename_tenants
    def v2_0_0_rename_tenants_down
      connection = ActiveRecord::Base.connection

      return unless connection.table_exists?(:ruby_llm_agents_tenants)

      remove_column_if_exists(connection, :ruby_llm_agents_tenants, :active)
      remove_column_if_exists(connection, :ruby_llm_agents_tenants, :metadata)

      connection.rename_table :ruby_llm_agents_tenants, :ruby_llm_agents_tenant_budgets
    end

    # Version 2.0.0 - Remove agent_version column
    def v2_0_0_remove_agent_version
      connection = ActiveRecord::Base.connection
      table_name = :ruby_llm_agents_executions

      return unless connection.column_exists?(table_name, :agent_version)

      if connection.index_exists?(table_name, [:agent_type, :agent_version])
        connection.remove_index table_name, [:agent_type, :agent_version]
      end

      connection.remove_column table_name, :agent_version
    end

    # Rollback for v2_0_0 remove_agent_version
    def v2_0_0_remove_agent_version_down
      connection = ActiveRecord::Base.connection
      table_name = :ruby_llm_agents_executions

      add_column_if_missing(connection, table_name, :agent_version, :string, default: "1.0")
    end

    # Version 2.0.0 - Remove workflow columns
    def v2_0_0_remove_workflow_columns
      connection = ActiveRecord::Base.connection
      table_name = :ruby_llm_agents_executions

      return unless connection.column_exists?(table_name, :workflow_id)

      # Remove indexes first
      if connection.index_exists?(table_name, [:workflow_id, :workflow_step])
        connection.remove_index table_name, [:workflow_id, :workflow_step]
      end
      if connection.index_exists?(table_name, :workflow_id)
        connection.remove_index table_name, :workflow_id
      end
      if connection.index_exists?(table_name, :workflow_type)
        connection.remove_index table_name, :workflow_type
      end

      # Remove the columns
      %i[workflow_id workflow_type workflow_step].each do |column|
        remove_column_if_exists(connection, table_name, column)
      end
    end

    # Rollback for v2_0_0 remove_workflow_columns
    def v2_0_0_remove_workflow_columns_down
      connection = ActiveRecord::Base.connection
      table_name = :ruby_llm_agents_executions

      add_column_if_missing(connection, table_name, :workflow_id, :string)
      add_column_if_missing(connection, table_name, :workflow_type, :string)
      add_column_if_missing(connection, table_name, :workflow_step, :string)

      connection.add_index table_name, :workflow_id, if_not_exists: true
      connection.add_index table_name, :workflow_type, if_not_exists: true
      add_composite_index_if_missing(connection, table_name, [:workflow_id, :workflow_step])
    end

    private

    # Add a column only if it doesn't exist
    def add_column_if_missing(connection, table_name, column_name, type, **options)
      return if connection.column_exists?(table_name, column_name)

      connection.add_column(table_name, column_name, type, **options)
    end

    # Remove a column only if it exists
    def remove_column_if_exists(connection, table_name, column_name)
      return unless connection.column_exists?(table_name, column_name)

      connection.remove_column(table_name, column_name)
    end

    # Add composite index only if it doesn't exist
    def add_composite_index_if_missing(connection, table_name, columns, unique: false)
      return if connection.index_exists?(table_name, columns)

      connection.add_index(table_name, columns, unique: unique)
    end
  end
end
