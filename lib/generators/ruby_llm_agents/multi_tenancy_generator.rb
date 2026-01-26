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
  #   - ruby_llm_agents_tenants table for per-tenant configuration
  #   - Adding tenant columns to ruby_llm_agents_executions
  #
  # For users upgrading from an older version:
  #   - Renames ruby_llm_agents_tenant_budgets to ruby_llm_agents_tenants
  #
  class MultiTenancyGenerator < ::Rails::Generators::Base
    include ::ActiveRecord::Generators::Migration

    source_root File.expand_path("templates", __dir__)

    desc "Adds multi-tenancy support to RubyLLM::Agents"

    def create_tenants_migration
      if table_exists?(:ruby_llm_agents_tenants)
        say_status :skip, "ruby_llm_agents_tenants table already exists", :yellow
        return
      end

      if table_exists?(:ruby_llm_agents_tenant_budgets)
        # Upgrade path: rename existing table
        say_status :upgrade, "Renaming tenant_budgets to tenants", :blue
        migration_template(
          "rename_tenant_budgets_to_tenants_migration.rb.tt",
          File.join(db_migrate_path, "rename_tenant_budgets_to_tenants.rb")
        )
      else
        # Fresh install: create new table
        migration_template(
          "create_tenants_migration.rb.tt",
          File.join(db_migrate_path, "create_ruby_llm_agents_tenants.rb")
        )
      end
    end

    def create_add_tenant_to_executions_migration
      if column_exists?(:ruby_llm_agents_executions, :tenant_id)
        say_status :skip, "tenant_id column already exists on executions", :yellow
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
      say "  2. Add llm_tenant to your tenant model:"
      say ""
      say "     class Organization < ApplicationRecord"
      say "       include RubyLLM::Agents::LLMTenant"
      say ""
      say "       llm_tenant id: :id,            # Method for tenant_id"
      say "                  budget: true,       # Auto-create budget on creation"
      say "                  limits: {           # Optional default limits"
      say "                    daily_cost: 100,"
      say "                    monthly_cost: 1000"
      say "                  },"
      say "                  enforcement: :hard  # :none, :soft, or :hard"
      say "     end"
      say ""
      say "  3. Pass tenant to agents:"
      say ""
      say "     MyAgent.call(prompt, tenant: current_organization)"
      say ""
      say "  4. Query usage:"
      say ""
      say "     tenant = RubyLLM::Agents::Tenant.for(organization)"
      say "     tenant.cost_today        # => 12.34"
      say "     tenant.tokens_this_month # => 50000"
      say "     tenant.usage_summary     # => { cost: ..., tokens: ..., ... }"
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
