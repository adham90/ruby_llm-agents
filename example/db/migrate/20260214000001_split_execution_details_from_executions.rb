# frozen_string_literal: true

# Migration to clean up old detail columns from executions table.
#
# The execution_details table was created but old columns were not removed
# from executions. This migration:
# - Backfills any data from old columns to execution_details
# - Removes old detail columns from executions
# - Removes deprecated niche columns (now in metadata JSON)
# - Removes deprecated tenant_record polymorphic (access via Tenant model)
# - Ensures all required columns exist
class SplitExecutionDetailsFromExecutions < ActiveRecord::Migration[8.1]
  # Columns that belong on execution_details, not executions
  DETAIL_COLUMNS = %i[
    error_message system_prompt user_prompt response messages_summary
    tool_calls attempts fallback_chain parameters routed_to
    classification_result cached_at cache_creation_tokens
  ].freeze

  # Niche columns moved to metadata JSON
  NICHE_COLUMNS = %i[
    span_id response_cache_key time_to_first_token_ms
    retryable rate_limited fallback_reason
  ].freeze

  # Polymorphic tenant columns removed from executions (access via Tenant model)
  TENANT_RECORD_COLUMNS = %i[tenant_record_type tenant_record_id].freeze

  def up
    backfill_and_remove_old_columns
    remove_niche_columns
    remove_tenant_record_columns
    ensure_required_columns
    cleanup_indexes
  end

  def down
    raise ActiveRecord::IrreversibleMigration,
          "This migration cannot be reversed. Use rails db:schema:load to restore."
  end

  private

  def backfill_and_remove_old_columns
    columns_present = DETAIL_COLUMNS.select { |col| column_exists?(:ruby_llm_agents_executions, col) }
    return if columns_present.empty?

    say_with_time "Backfilling execution_details from executions" do
      backfill_execution_details(columns_present)
    end

    columns_present.each do |col|
      remove_column :ruby_llm_agents_executions, col
    end
  end

  def backfill_execution_details(columns_present)
    batch_size = 1000
    count = 0
    has_data_conditions = columns_present.map { |col| "e.#{col} IS NOT NULL" }.join(" OR ")

    loop do
      ids = exec_query(<<~SQL).rows.flatten
        SELECT e.id FROM ruby_llm_agents_executions e
        LEFT JOIN ruby_llm_agents_execution_details d ON d.execution_id = e.id
        WHERE d.id IS NULL AND (#{has_data_conditions})
        ORDER BY e.id
        LIMIT #{batch_size}
      SQL

      break if ids.empty?

      detail_cols = %w[execution_id created_at updated_at] + columns_present.map(&:to_s)
      select_exprs = %w[id created_at updated_at] + columns_present.map { |col|
        case col
        when :messages_summary then "COALESCE(messages_summary, '{}')"
        when :tool_calls then "COALESCE(tool_calls, '[]')"
        when :attempts then "COALESCE(attempts, '[]')"
        when :parameters then "COALESCE(parameters, '{}')"
        else col.to_s
        end
      }

      execute <<~SQL
        INSERT INTO ruby_llm_agents_execution_details (#{detail_cols.join(', ')})
        SELECT #{select_exprs.join(', ')}
        FROM ruby_llm_agents_executions
        WHERE id IN (#{ids.join(',')})
      SQL

      count += ids.size
    end

    count
  end

  def remove_niche_columns
    NICHE_COLUMNS.each do |col|
      if column_exists?(:ruby_llm_agents_executions, col)
        remove_column :ruby_llm_agents_executions, col
      end
    end
  end

  def remove_tenant_record_columns
    remove_index :ruby_llm_agents_executions, column: TENANT_RECORD_COLUMNS,
                 name: "index_executions_on_tenant_record", if_exists: true

    TENANT_RECORD_COLUMNS.each do |col|
      if column_exists?(:ruby_llm_agents_executions, col)
        remove_column :ruby_llm_agents_executions, col
      end
    end
  end

  def ensure_required_columns
    unless column_exists?(:ruby_llm_agents_executions, :messages_count)
      add_column :ruby_llm_agents_executions, :messages_count, :integer, default: 0, null: false
    end
    unless column_exists?(:ruby_llm_agents_executions, :cached_tokens)
      add_column :ruby_llm_agents_executions, :cached_tokens, :integer, default: 0
    end
  end

  def cleanup_indexes
    %i[duration_ms total_cost messages_count attempts_count tool_calls_count
       chosen_model_id execution_type response_cache_key agent_type tenant_id].each do |col|
      remove_index :ruby_llm_agents_executions, col, if_exists: true
    end

    unless index_exists?(:ruby_llm_agents_executions, [:tenant_id, :created_at])
      add_index :ruby_llm_agents_executions, [:tenant_id, :created_at]
    end
    unless index_exists?(:ruby_llm_agents_executions, [:tenant_id, :status])
      add_index :ruby_llm_agents_executions, [:tenant_id, :status]
    end
  end
end
