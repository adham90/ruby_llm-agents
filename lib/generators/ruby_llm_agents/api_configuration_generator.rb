# frozen_string_literal: true

require "rails/generators"
require "rails/generators/active_record"

module RubyLlmAgents
  # API Configuration generator for ruby_llm-agents
  #
  # Usage:
  #   rails generate ruby_llm_agents:api_configuration
  #
  # This will create migrations for:
  #   - ruby_llm_agents_api_configurations table for storing API keys and settings
  #
  # API keys are encrypted at rest using Rails encrypted attributes.
  # Supports both global configuration and per-tenant overrides.
  #
  class ApiConfigurationGenerator < ::Rails::Generators::Base
    include ::ActiveRecord::Generators::Migration

    source_root File.expand_path("templates", __dir__)

    desc "Adds database-backed API configuration support to RubyLLM::Agents"

    def create_api_configurations_migration
      if table_exists?(:ruby_llm_agents_api_configurations)
        say_status :skip, "ruby_llm_agents_api_configurations table already exists", :yellow
        return
      end

      migration_template(
        "create_api_configurations_migration.rb.tt",
        File.join(db_migrate_path, "create_ruby_llm_agents_api_configurations.rb")
      )
    end

    def show_post_install_message
      say ""
      say "API Configuration migration created!", :green
      say ""
      say "Next steps:"
      say "  1. Ensure Rails encryption is configured (if not already):"
      say ""
      say "     bin/rails db:encryption:init"
      say ""
      say "     Then add the generated keys to your credentials or environment."
      say ""
      say "  2. Run the migration:"
      say ""
      say "     rails db:migrate"
      say ""
      say "  3. Access the API Configuration UI:"
      say ""
      say "     Navigate to /agents/api_configuration in your browser"
      say ""
      say "  4. (Optional) Configure API keys programmatically:"
      say ""
      say "     # Set global configuration"
      say "     config = RubyLLM::Agents::ApiConfiguration.global"
      say "     config.update!("
      say "       openai_api_key: 'sk-...',"
      say "       anthropic_api_key: 'sk-ant-...'"
      say "     )"
      say ""
      say "     # Set tenant-specific configuration"
      say "     tenant_config = RubyLLM::Agents::ApiConfiguration.for_tenant!('acme_corp')"
      say "     tenant_config.update!("
      say "       openai_api_key: 'sk-tenant-specific-key',"
      say "       inherit_global_defaults: true"
      say "     )"
      say ""
      say "Configuration Resolution Priority:"
      say "  1. Per-tenant database configuration (if multi-tenancy enabled)"
      say "  2. Global database configuration"
      say "  3. RubyLLM.configure block settings"
      say ""
      say "Security Notes:"
      say "  - API keys are encrypted at rest using Rails encrypted attributes"
      say "  - Keys are masked in the UI (e.g., sk-ab****wxyz)"
      say "  - Dashboard authentication inherits from your authenticate_dashboard! method"
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
  end
end
