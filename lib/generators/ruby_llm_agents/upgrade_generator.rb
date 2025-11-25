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

    def show_post_upgrade_message
      say ""
      say "RubyLLM::Agents upgrade migration created!", :green
      say ""
      say "Next steps:"
      say "  1. Run migrations: rails db:migrate"
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
  end
end
