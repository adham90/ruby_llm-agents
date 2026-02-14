# frozen_string_literal: true

require "rails/generators"
require "rails/generators/active_record"
module RubyLlmAgents
  # Upgrade generator for ruby_llm-agents
  #
  # Usage:
  #   rails generate ruby_llm_agents:upgrade
  #
  # This will create any missing migrations for upgrading from older versions.
  # It handles all upgrade scenarios:
  #
  # - v0.x/v1.x -> v2.0: Splits detail columns from executions to execution_details,
  #   removes deprecated columns, renames tenant_budgets to tenants
  # - v2.0 -> latest: No-ops safely if already up to date
  #
  class UpgradeGenerator < ::Rails::Generators::Base
    include ::ActiveRecord::Generators::Migration

    source_root File.expand_path("templates", __dir__)

    # Main upgrade: split execution_details from executions table
    #
    # This single migration handles ALL schema transitions:
    # - Creates execution_details table if missing
    # - Migrates data from old columns on executions to execution_details
    # - Removes deprecated columns (detail, niche, workflow, agent_version)
    # - Adds any missing columns that should stay on executions
    def create_split_execution_details_migration
      if already_split?
        say_status :skip, "execution_details already split from executions", :yellow
        return
      end

      migration_template(
        "split_execution_details_migration.rb.tt",
        File.join(db_migrate_path, "split_execution_details_from_executions.rb")
      )
    end

    # Rename tenant_budgets to tenants (v1.x -> v2.0 upgrade)
    def create_rename_tenant_budgets_migration
      # Skip if already using new table name
      if table_exists?(:ruby_llm_agents_tenants)
        say_status :skip, "ruby_llm_agents_tenants table already exists", :yellow
        return
      end

      # Only run if old table exists (needs upgrade)
      unless table_exists?(:ruby_llm_agents_tenant_budgets)
        say_status :skip, "No tenant_budgets table to upgrade", :yellow
        return
      end

      say_status :upgrade, "Renaming tenant_budgets to tenants", :blue
      migration_template(
        "rename_tenant_budgets_to_tenants_migration.rb.tt",
        File.join(db_migrate_path, "rename_tenant_budgets_to_tenants.rb")
      )
    end

    def suggest_config_consolidation
      ruby_llm_initializer = File.join(destination_root, "config/initializers/ruby_llm.rb")
      agents_initializer = File.join(destination_root, "config/initializers/ruby_llm_agents.rb")

      return unless File.exist?(ruby_llm_initializer) && File.exist?(agents_initializer)

      say ""
      say "Optional: You can now consolidate your API key configuration.", :yellow
      say ""
      say "Move your API keys from config/initializers/ruby_llm.rb"
      say "into config/initializers/ruby_llm_agents.rb:"
      say ""
      say "  RubyLLM::Agents.configure do |config|"
      say "    config.openai_api_key = ENV['OPENAI_API_KEY']"
      say "    config.anthropic_api_key = ENV['ANTHROPIC_API_KEY']"
      say "    # ... rest of your agent config"
      say "  end"
      say ""
      say "Then delete config/initializers/ruby_llm.rb if it only contained API keys."
      say ""
    end

    def show_post_upgrade_message
      say ""
      say "RubyLLM::Agents upgrade complete!", :green
      say ""
      say "Next steps:"
      say "  1. Run migrations: rails db:migrate"
      say "  2. Run your test suite to verify everything works"
      say ""
    end

    private

    def migration_version
      "[#{::ActiveRecord::VERSION::STRING.to_f}]"
    end

    def db_migrate_path
      "db/migrate"
    end

    # Check if the split has already been completed:
    # - execution_details table exists
    # - No detail columns remain on executions
    # - No deprecated columns remain on executions
    def already_split?
      return false unless table_exists?(:ruby_llm_agents_execution_details)
      return false if has_detail_columns_on_executions?
      return false if has_deprecated_columns_on_executions?

      true
    end

    # Detail columns that should only exist on execution_details, not executions
    DETAIL_COLUMNS = %i[
      error_message system_prompt user_prompt response messages_summary
      tool_calls attempts fallback_chain parameters routed_to
      classification_result cached_at cache_creation_tokens
    ].freeze

    # Niche columns that should be in metadata JSON, not separate columns
    NICHE_COLUMNS = %i[
      span_id response_cache_key time_to_first_token_ms
      retryable rate_limited fallback_reason
    ].freeze

    # Deprecated columns
    DEPRECATED_COLUMNS = %i[
      agent_version workflow_id workflow_type workflow_step
      tenant_record_type tenant_record_id
    ].freeze

    def has_detail_columns_on_executions?
      DETAIL_COLUMNS.any? { |col| column_exists?(:ruby_llm_agents_executions, col) }
    end

    def has_deprecated_columns_on_executions?
      (NICHE_COLUMNS + DEPRECATED_COLUMNS).any? { |col| column_exists?(:ruby_llm_agents_executions, col) }
    end

    def column_exists?(table, column)
      return false unless ActiveRecord::Base.connection.table_exists?(table)

      ActiveRecord::Base.connection.column_exists?(table, column)
    rescue StandardError
      false
    end

    def table_exists?(table)
      ActiveRecord::Base.connection.table_exists?(table)
    rescue StandardError
      false
    end
  end
end
