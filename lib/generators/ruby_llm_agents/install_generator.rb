# frozen_string_literal: true

require "rails/generators"
require "rails/generators/active_record"

module RubyLlmAgents
  # Install generator for ruby_llm-agents
  #
  # Usage:
  #   rails generate ruby_llm_agents:install
  #   rails generate ruby_llm_agents:install --root=ai
  #
  # This will:
  #   - Create the migration for ruby_llm_agents_executions table
  #   - Create the initializer at config/initializers/ruby_llm_agents.rb
  #   - Create app/{root}/agents/application_agent.rb base class
  #   - Create app/{root}/text/embedders/application_embedder.rb base class
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
    class_option :root,
                 type: :string,
                 default: nil,
                 desc: "Root directory name (default: uses config or 'llm')"
    class_option :namespace,
                 type: :string,
                 default: nil,
                 desc: "Root namespace (default: camelized root or config)"

    def create_migration_file
      return if options[:skip_migration]

      migration_template(
        "migration.rb.tt",
        File.join(db_migrate_path, "create_ruby_llm_agents_executions.rb")
      )
    end

    def create_initializer
      return if options[:skip_initializer]

      template "initializer.rb.tt", "config/initializers/ruby_llm_agents.rb"
    end

    def create_directory_structure
      say_status :create, "#{root_directory}/ directory structure", :green

      # Create agents directory
      empty_directory "app/#{root_directory}/agents"

      # Create text/embedders directory
      empty_directory "app/#{root_directory}/text/embedders"
    end

    def create_application_agent
      @root_namespace = root_namespace
      template "application_agent.rb.tt", "app/#{root_directory}/agents/application_agent.rb"
    end

    def create_application_embedder
      @root_namespace = root_namespace
      @text_namespace = "#{root_namespace}::Text"
      template "application_embedder.rb.tt", "app/#{root_directory}/text/embedders/application_embedder.rb"
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
      say "  app/#{root_directory}/"
      say "  ├── agents/"
      say "  │   └── application_agent.rb"
      say "  └── text/"
      say "      └── embedders/"
      say "          └── application_embedder.rb"
      say ""
      say "Namespace: #{root_namespace}::"
      say ""
      say "Next steps:"
      say "  1. Run migrations: rails db:migrate"
      say "  2. Generate an agent: rails generate ruby_llm_agents:agent MyAgent query:required"
      say "  3. Access the dashboard at: /agents"
      say ""
    end

    private

    def migration_version
      "[#{::ActiveRecord::VERSION::STRING.to_f}]"
    end

    def db_migrate_path
      "db/migrate"
    end

    def root_directory
      @root_directory ||= options[:root] || RubyLLM::Agents.configuration.root_directory
    end

    def root_namespace
      @root_namespace ||= options[:namespace] || camelize(root_directory)
    end

    def camelize(str)
      # Handle special cases for common abbreviations
      return "AI" if str.downcase == "ai"
      return "ML" if str.downcase == "ml"
      return "LLM" if str.downcase == "llm"

      # Standard camelization
      str.split(/[-_]/).map(&:capitalize).join
    end
  end
end
