# frozen_string_literal: true

require "rails/generators"
require "rails/generators/active_record"

module RubyLlmAgents
  # Multi-tenancy generator for ruby_llm-agents
  #
  # Usage:
  #   rails generate ruby_llm_agents:multi_tenancy
  #
  # This will create migrations for:
  #   - ruby_llm_agents_tenant_budgets table for per-tenant budget configuration
  #   - Adding tenant_id column to ruby_llm_agents_executions
  #
  class MultiTenancyGenerator < ::Rails::Generators::Base
    include ::ActiveRecord::Generators::Migration

    source_root File.expand_path("templates", __dir__)

    desc "Adds multi-tenancy support to RubyLLM::Agents"

    def create_tenant_budgets_migration
      if table_exists?(:ruby_llm_agents_tenant_budgets)
        say_status :skip, "ruby_llm_agents_tenant_budgets table already exists", :yellow
        return
      end

      migration_template(
        "create_tenant_budgets_migration.rb.tt",
        File.join(db_migrate_path, "create_ruby_llm_agents_tenant_budgets.rb")
      )
    end

    def create_add_tenant_to_executions_migration
      if column_exists?(:ruby_llm_agents_executions, :tenant_id)
        say_status :skip, "tenant_id column already exists", :yellow
        return
      end

      migration_template(
        "add_tenant_to_executions_migration.rb.tt",
        File.join(db_migrate_path, "add_tenant_id_to_ruby_llm_agents_executions.rb")
      )
    end

    def show_post_install_message
      say ""
      say "Multi-tenancy migrations created!", :green
      say ""
      say "Next steps:"
      say "  1. Run: rails db:migrate"
      say "  2. Configure multi-tenancy in your initializer:"
      say ""
      say "     RubyLLM::Agents.configure do |config|"
      say "       config.multi_tenancy_enabled = true"
      say "       config.tenant_resolver = -> { Current.tenant&.id }"
      say "     end"
      say ""
      say "  3. Set Current.tenant in your ApplicationController"
      say ""
      say "  4. Create tenant budgets:"
      say ""
      say "     RubyLLM::Agents::TenantBudget.create!("
      say "       tenant_id: 'acme_corp',"
      say "       daily_limit: 50.0,"
      say "       monthly_limit: 500.0,"
      say "       enforcement: 'hard'"
      say "     )"
      say ""
    end

    private

    def migration_version
      "[#{::ActiveRecord::VERSION::STRING.to_f}]"
    end

    def db_migrate_path
      "db/migrate"
    end

    def table_exists?(table)
      ActiveRecord::Base.connection.table_exists?(table)
    rescue StandardError
      false
    end

    def column_exists?(table, column)
      return false unless ActiveRecord::Base.connection.table_exists?(table)

      ActiveRecord::Base.connection.column_exists?(table, column)
    rescue StandardError
      false
    end
  end
end
