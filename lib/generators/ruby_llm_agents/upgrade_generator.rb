# frozen_string_literal: true

require "rails/generators"
require "rails/generators/active_record"
require "fileutils"

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

    def create_add_workflow_migration
      # Check if columns already exist
      if column_exists?(:ruby_llm_agents_executions, :workflow_id)
        say_status :skip, "workflow_id column already exists", :yellow
        return
      end

      migration_template(
        "add_workflow_migration.rb.tt",
        File.join(db_migrate_path, "add_workflow_to_ruby_llm_agents_executions.rb")
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

    def migrate_agents_directory
      root_dir = RubyLLM::Agents.configuration.root_directory
      namespace = RubyLLM::Agents.configuration.root_namespace
      migrate_directory("agents", "#{root_dir}/agents", namespace)
    end

    def migrate_tools_directory
      root_dir = RubyLLM::Agents.configuration.root_directory
      namespace = RubyLLM::Agents.configuration.root_namespace
      migrate_directory("tools", "#{root_dir}/tools", namespace)
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

    def show_migration_summary
      namespace = RubyLLM::Agents.configuration.root_namespace
      root_dir = RubyLLM::Agents.configuration.root_directory

      return unless @agents_migrated || @tools_migrated

      say ""
      say "=" * 60
      say "  File Migration Summary", :green
      say "=" * 60
      say ""
      say "Your agents and tools have been migrated to the new structure:"
      say ""
      say "  app/agents/  →  app/#{root_dir}/agents/" if @agents_migrated
      say "  app/tools/   →  app/#{root_dir}/tools/" if @tools_migrated
      say ""
      say "Classes are now namespaced under #{namespace}::"
      say ""
      say "  Before: GeneralAgent.call(...)"
      say "  After:  #{namespace}::GeneralAgent.call(...)"
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

    def migrate_directory(old_dir, new_dir, namespace)
      source = Rails.root.join("app", old_dir)
      destination = Rails.root.join("app", new_dir)

      # Skip if source doesn't exist
      unless File.directory?(source)
        say_status :skip, "app/#{old_dir}/ does not exist", :yellow
        return
      end

      # Skip if source and destination are the same
      if source.to_s == destination.to_s
        say_status :skip, "app/#{old_dir}/ is already at destination", :yellow
        return
      end

      files_to_migrate = Dir.glob("#{source}/**/*.rb")
      if files_to_migrate.empty?
        say_status :skip, "app/#{old_dir}/ has no Ruby files to migrate", :yellow
        return
      end

      if options[:pretend]
        say_status :preview, "Would move #{files_to_migrate.size} files from app/#{old_dir}/ → app/#{new_dir}/", :yellow
        files_to_migrate.each do |file|
          relative = file.sub("#{source}/", "")
          say_status :would_move, relative, :cyan
        end
        return
      end

      # Create destination directory
      FileUtils.mkdir_p(destination)

      # Track conflicts and migrated files
      conflicts = []
      migrated = []

      files_to_migrate.each do |file|
        relative_path = file.sub("#{source}/", "")
        dest_file = File.join(destination, relative_path)

        # Skip if destination file already exists (conflict)
        if File.exist?(dest_file)
          conflicts << relative_path
          say_status :conflict, "app/#{new_dir}/#{relative_path} already exists, skipping", :red
          next
        end

        FileUtils.mkdir_p(File.dirname(dest_file))
        FileUtils.mv(file, dest_file)

        wrap_in_namespace(dest_file, namespace)
        say_status :migrated, "app/#{new_dir}/#{relative_path}", :green
        migrated << relative_path
      end

      # Cleanup empty source directory
      cleanup_empty_directory(source, old_dir)

      # Track that migration happened for summary
      instance_variable_set("@#{old_dir}_migrated", migrated.any?)

      { migrated: migrated, conflicts: conflicts }
    end

    def wrap_in_namespace(file, namespace)
      content = File.read(file)

      # Skip if already namespaced
      return if content.include?("module #{namespace}")

      # Wrap content in namespace with proper indentation
      indented = content.lines.map { |line| line.empty? || line.strip.empty? ? line : "  #{line}" }.join
      wrapped = "module #{namespace}\n#{indented}end\n"

      File.write(file, wrapped)
    end

    def cleanup_empty_directory(dir, dir_name)
      return unless File.directory?(dir)

      # Remove empty subdirectories first (deepest first)
      Dir.glob("#{dir}/**/", File::FNM_DOTMATCH).sort_by(&:length).reverse.each do |subdir|
        next if subdir.end_with?(".", "..")

        FileUtils.rmdir(subdir) if File.directory?(subdir) && Dir.empty?(subdir)
      rescue Errno::ENOTEMPTY, Errno::ENOENT
        # Directory not empty or already removed
      end

      # Remove main directory if empty
      if File.directory?(dir) && Dir.empty?(dir)
        FileUtils.rmdir(dir)
        say_status :removed, "app/#{dir_name}/ (empty)", :yellow
      end
    rescue Errno::ENOTEMPTY
      say_status :kept, "app/#{dir_name}/ (not empty)", :yellow
    end
  end
end
