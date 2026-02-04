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
  #
  class UpgradeGenerator < ::Rails::Generators::Base
    include ::ActiveRecord::Generators::Migration

    source_root File.expand_path("templates", __dir__)

    def create_add_prompts_migration
      # Check if columns already exist
      if column_exists?(:ruby_llm_agents_executions, :system_prompt)
        say_status :skip, "system_prompt column already exists", :yellow
        return
      end

      migration_template(
        "add_prompts_migration.rb.tt",
        File.join(db_migrate_path, "add_prompts_to_ruby_llm_agents_executions.rb")
      )
    end

    def create_add_attempts_migration
      # Check if columns already exist
      if column_exists?(:ruby_llm_agents_executions, :attempts)
        say_status :skip, "attempts column already exists", :yellow
        return
      end

      migration_template(
        "add_attempts_migration.rb.tt",
        File.join(db_migrate_path, "add_attempts_to_ruby_llm_agents_executions.rb")
      )
    end

    def create_add_streaming_migration
      # Check if columns already exist
      if column_exists?(:ruby_llm_agents_executions, :streaming)
        say_status :skip, "streaming column already exists", :yellow
        return
      end

      migration_template(
        "add_streaming_migration.rb.tt",
        File.join(db_migrate_path, "add_streaming_to_ruby_llm_agents_executions.rb")
      )
    end

    def create_add_tracing_migration
      # Check if columns already exist
      if column_exists?(:ruby_llm_agents_executions, :trace_id)
        say_status :skip, "trace_id column already exists", :yellow
        return
      end

      migration_template(
        "add_tracing_migration.rb.tt",
        File.join(db_migrate_path, "add_tracing_to_ruby_llm_agents_executions.rb")
      )
    end

    def create_add_routing_migration
      # Check if columns already exist
      if column_exists?(:ruby_llm_agents_executions, :fallback_reason)
        say_status :skip, "fallback_reason column already exists", :yellow
        return
      end

      migration_template(
        "add_routing_migration.rb.tt",
        File.join(db_migrate_path, "add_routing_to_ruby_llm_agents_executions.rb")
      )
    end

    def create_add_finish_reason_migration
      # Check if columns already exist
      if column_exists?(:ruby_llm_agents_executions, :finish_reason)
        say_status :skip, "finish_reason column already exists", :yellow
        return
      end

      migration_template(
        "add_finish_reason_migration.rb.tt",
        File.join(db_migrate_path, "add_finish_reason_to_ruby_llm_agents_executions.rb")
      )
    end

    def create_add_caching_migration
      # Check if columns already exist
      if column_exists?(:ruby_llm_agents_executions, :cache_hit)
        say_status :skip, "cache_hit column already exists", :yellow
        return
      end

      migration_template(
        "add_caching_migration.rb.tt",
        File.join(db_migrate_path, "add_caching_to_ruby_llm_agents_executions.rb")
      )
    end

    def create_add_tool_calls_migration
      # Check if columns already exist
      if column_exists?(:ruby_llm_agents_executions, :tool_calls)
        say_status :skip, "tool_calls column already exists", :yellow
        return
      end

      migration_template(
        "add_tool_calls_migration.rb.tt",
        File.join(db_migrate_path, "add_tool_calls_to_ruby_llm_agents_executions.rb")
      )
    end

    def create_add_execution_type_migration
      # Check if columns already exist
      if column_exists?(:ruby_llm_agents_executions, :execution_type)
        say_status :skip, "execution_type column already exists", :yellow
        return
      end

      migration_template(
        "add_execution_type_migration.rb.tt",
        File.join(db_migrate_path, "add_execution_type_to_ruby_llm_agents_executions.rb")
      )
    end

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

    def show_post_upgrade_message
      say ""
      say "RubyLLM::Agents upgrade complete!", :green
      say ""
      say "Next steps:"
      say "  1. Run migrations: rails db:migrate"
      say "  2. Update class references in your controllers, views, and tests"
      say "  3. Run your test suite to find any broken references"
      say ""
    end

    private

    def migration_version
      "[#{::ActiveRecord::VERSION::STRING.to_f}]"
    end

    def db_migrate_path
      "db/migrate"
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
