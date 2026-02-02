# frozen_string_literal: true

require "rails/generators"
require "rails/generators/active_record"

module RubyLlmAgents
  # Install generator for ruby_llm-agents
  #
  # Usage:
  #   rails generate ruby_llm_agents:install
  #
  # This will:
  #   - Create the migration for ruby_llm_agents_executions table
  #   - Create the initializer at config/initializers/ruby_llm_agents.rb
  #   - Create app/agents/application_agent.rb base class
  #   - Create app/agents/concerns/ directory
  #   - Create app/workflows/application_workflow.rb base class
  #   - Optionally mount the dashboard engine in routes
  #
  class InstallGenerator < ::Rails::Generators::Base
    include ::ActiveRecord::Generators::Migration

    source_root File.expand_path("templates", __dir__)

    class_option :skip_migration, type: :boolean, default: false,
                 desc: "Skip generating the migration file"
    class_option :skip_initializer, type: :boolean, default: false,
                 desc: "Skip generating the initializer file"
    class_option :mount_dashboard, type: :boolean, default: true,
                 desc: "Mount the dashboard engine in routes"

    def create_migration_file
      return if options[:skip_migration]

      migration_template(
        "migration.rb.tt",
        File.join(db_migrate_path, "create_ruby_llm_agents_executions.rb")
      )
    end

    def create_execution_details_migration
      return if options[:skip_migration]

      migration_template(
        "create_execution_details_migration.rb.tt",
        File.join(db_migrate_path, "create_ruby_llm_agents_execution_details.rb")
      )
    end

    def create_initializer
      return if options[:skip_initializer]

      template "initializer.rb.tt", "config/initializers/ruby_llm_agents.rb"
    end

    def create_directory_structure
      say_status :create, "agents/ directory structure", :green

      # Create agents directory and subdirectories
      empty_directory "app/agents"
      empty_directory "app/agents/concerns"

      # Create workflows directory
      empty_directory "app/workflows"

      # Create tools directory
      empty_directory "app/tools"
    end

    def create_application_agent
      template "application_agent.rb.tt", "app/agents/application_agent.rb"
    end

    def create_application_workflow
      template "application_workflow.rb.tt", "app/workflows/application_workflow.rb"
    end

    def create_skill_files
      say_status :create, "skill documentation files", :green

      # Create agents skill file
      template "skills/AGENTS.md.tt", "app/agents/AGENTS.md"

      # Create workflows skill file
      template "skills/WORKFLOWS.md.tt", "app/workflows/WORKFLOWS.md"

      # Create tools skill file
      template "skills/TOOLS.md.tt", "app/tools/TOOLS.md"
    end

    def mount_dashboard_engine
      return unless options[:mount_dashboard]

      route_content = 'mount RubyLLM::Agents::Engine => "/agents"'

      if File.exist?(File.join(destination_root, "config/routes.rb"))
        inject_into_file(
          "config/routes.rb",
          "  #{route_content}\n",
          after: "Rails.application.routes.draw do\n"
        )
        say_status :route, route_content, :green
      end
    end

    def show_post_install_message
      say ""
      say "RubyLLM::Agents has been installed!", :green
      say ""
      say "Directory structure created:"
      say "  app/"
      say "  ├── agents/"
      say "  │   ├── application_agent.rb"
      say "  │   ├── concerns/"
      say "  │   └── AGENTS.md"
      say "  ├── workflows/"
      say "  │   ├── application_workflow.rb"
      say "  │   └── WORKFLOWS.md"
      say "  └── tools/"
      say "      └── TOOLS.md"
      say ""
      say "Skill files (*.md) help AI coding assistants understand how to use this gem."
      say ""
      say "Next steps:"
      say "  1. Run migrations: rails db:migrate"
      say "  2. Generate an agent: rails generate ruby_llm_agents:agent MyAgent query:required"
      say "  3. Access the dashboard at: /agents"
      say ""
      say "Generator commands:"
      say "  rails generate ruby_llm_agents:agent CustomerSupport query:required"
      say "  rails generate ruby_llm_agents:image_generator Product"
      say "  rails generate ruby_llm_agents:transcriber Meeting"
      say "  rails generate ruby_llm_agents:embedder Semantic"
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
