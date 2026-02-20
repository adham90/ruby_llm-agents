# frozen_string_literal: true

require "rails/generators"
require "rails/generators/active_record"

module RubyLlmAgents
  # Generator for creating a migration to rename an agent in execution records
  #
  # Usage:
  #   rails generate ruby_llm_agents:rename_agent OldAgentName NewAgentName
  #
  # This creates a reversible migration that updates the agent_type column
  # in the ruby_llm_agents_executions table.
  #
  class RenameAgentGenerator < ::Rails::Generators::Base
    include ::ActiveRecord::Generators::Migration

    source_root File.expand_path("templates", __dir__)

    argument :old_name, type: :string, desc: "The current (old) agent class name"
    argument :new_name, type: :string, desc: "The new agent class name"

    def validate_names
      if old_name == new_name
        raise Thor::Error, "Old and new agent names must be different"
      end
    end

    def create_migration_file
      migration_template(
        "rename_agent_migration.rb.tt",
        File.join(db_migrate_path, "rename_#{old_name.underscore}_to_#{new_name.underscore}.rb")
      )
    end

    def show_message
      say ""
      say "Created migration to rename #{old_name} -> #{new_name}", :green
      say "Run `rails db:migrate` to apply."
      say ""
    end

    private

    def migration_version
      "[#{::ActiveRecord::VERSION::STRING.to_f}]"
    end

    def db_migrate_path
      "db/migrate"
    end
  end
end
