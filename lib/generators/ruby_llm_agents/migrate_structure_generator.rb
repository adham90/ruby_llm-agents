# frozen_string_literal: true

require "rails/generators"
require "fileutils"

module RubyLlmAgents
  # Migration generator for moving from old directory structure to new
  #
  # Migrates from:
  #   app/{root}/agents/
  #   app/{root}/image/generators/
  #   app/{root}/audio/speakers/
  #   app/{root}/text/embedders/
  #   app/{root}/workflows/
  #
  # To:
  #   app/agents/
  #   app/agents/images/
  #   app/agents/audio/
  #   app/agents/embedders/
  #   app/workflows/
  #
  # Usage:
  #   rails generate ruby_llm_agents:migrate_structure
  #   rails generate ruby_llm_agents:migrate_structure --dry-run
  #   rails generate ruby_llm_agents:migrate_structure --source-root=ai
  #
  class MigrateStructureGenerator < ::Rails::Generators::Base
    source_root File.expand_path("templates", __dir__)

    class_option :source_root,
      type: :string,
      default: nil,
      desc: "Source root directory to migrate from (default: auto-detect or 'llm')"

    class_option :dry_run,
      type: :boolean,
      default: false,
      desc: "Show what would be done without making changes"

    class_option :skip_namespace_update,
      type: :boolean,
      default: false,
      desc: "Skip updating namespaces in Ruby files"

    class_option :use_git,
      type: :boolean,
      default: true,
      desc: "Use git mv when in a git repository"

    # Maps old paths to new paths
    # Format: old_subpath => new_path (relative to app/)
    PATH_MAPPING = {
      # Task agents
      "agents" => "agents",

      # Image agents (flatten operation types)
      "image/generators" => "agents/images",
      "image/analyzers" => "agents/images",
      "image/editors" => "agents/images",
      "image/upscalers" => "agents/images",
      "image/variators" => "agents/images",
      "image/transformers" => "agents/images",
      "image/background_removers" => "agents/images",
      "image/pipelines" => "agents/images",

      # Audio agents
      "audio/speakers" => "agents/audio",
      "audio/transcribers" => "agents/audio",

      # Text operations
      "text/embedders" => "agents/embedders",
      "text/moderators" => "agents/moderators",

      # Workflows
      "workflows" => "workflows",

      # Tools
      "tools" => "tools"
    }.freeze

    # Namespace transformations
    # Format: old_namespace_pattern => new_namespace
    NAMESPACE_MAPPING = {
      # Remove root namespace from task agents
      /\A(\w+)::(\w+Agent)\z/ => '\2',

      # Image namespaces
      /\A(\w+)::Image::(\w+)\z/ => 'Images::\2',

      # Audio namespaces
      /\A(\w+)::Audio::(\w+)\z/ => 'Audio::\2',

      # Text namespaces -> Embedders/Moderators
      /\A(\w+)::Text::(\w+Embedder)\z/ => 'Embedders::\2',
      /\A(\w+)::Text::(\w+Moderator)\z/ => 'Moderators::\2',

      # Workflows (remove root namespace)
      /\A(\w+)::(\w+Workflow)\z/ => '\2'
    }.freeze

    def check_prerequisites
      @source_root_dir = detect_source_root

      if @source_root_dir.nil?
        say_status :skip, "No old structure detected. Nothing to migrate.", :yellow
        say ""
        say "If you have an existing structure, specify the source root:"
        say "  rails generate ruby_llm_agents:migrate_structure --source-root=llm"
        raise Thor::Error, "Migration aborted: no source found"
      end

      say_status :found, "Old structure at app/#{@source_root_dir}/", :green
    end

    def show_migration_plan
      say ""
      say "=" * 60
      say "Migration Plan", :bold
      say "=" * 60
      say ""
      say "Source: app/#{@source_root_dir}/"
      say "Target: app/agents/ and app/workflows/"
      say ""

      @files_to_migrate = []

      PATH_MAPPING.each do |old_subpath, new_path|
        old_full_path = Rails.root.join("app", @source_root_dir, old_subpath)
        next unless File.directory?(old_full_path)

        files = Dir.glob("#{old_full_path}/**/*.rb")
        next if files.empty?

        files.each do |file|
          relative = file.sub("#{old_full_path}/", "")
          new_file = Rails.root.join("app", new_path, relative)
          @files_to_migrate << {
            old: file,
            new: new_file.to_s,
            old_display: "app/#{@source_root_dir}/#{old_subpath}/#{relative}",
            new_display: "app/#{new_path}/#{relative}"
          }
        end
      end

      if @files_to_migrate.empty?
        say_status :skip, "No Ruby files found to migrate", :yellow
        return
      end

      say "Files to migrate (#{@files_to_migrate.size}):"
      @files_to_migrate.each do |f|
        say "  #{f[:old_display]}"
        say "    -> #{f[:new_display]}", :green
      end
      say ""
    end

    def create_new_directories
      return if @files_to_migrate.nil? || @files_to_migrate.empty?

      say_status :create, "Creating new directory structure", :green

      directories = @files_to_migrate.map { |f| File.dirname(f[:new]) }.uniq

      directories.each do |dir|
        if options[:dry_run]
          say_status :dry_run, "Would create #{dir.sub(Rails.root.to_s + '/', '')}", :yellow
        else
          FileUtils.mkdir_p(dir)
          say_status :mkdir, dir.sub(Rails.root.to_s + "/", ""), :green
        end
      end
    end

    def move_files
      return if @files_to_migrate.nil? || @files_to_migrate.empty?

      say ""
      say_status :move, "Moving files to new locations", :green

      @files_to_migrate.each do |f|
        if options[:dry_run]
          say_status :dry_run, "Would move #{f[:old_display]} -> #{f[:new_display]}", :yellow
        else
          move_file(f[:old], f[:new])
          say_status :moved, f[:new_display], :green
        end
      end
    end

    def update_namespaces
      return if options[:skip_namespace_update]
      return if @files_to_migrate.nil? || @files_to_migrate.empty?

      say ""
      say_status :update, "Updating namespaces in Ruby files", :green

      @files_to_migrate.each do |f|
        file_path = options[:dry_run] ? f[:old] : f[:new]
        next unless File.exist?(file_path)

        if options[:dry_run]
          say_status :dry_run, "Would update namespaces in #{f[:new_display]}", :yellow
        else
          update_file_namespaces(f[:new])
        end
      end
    end

    def update_base_classes
      return if options[:skip_namespace_update]
      return if @files_to_migrate.nil? || @files_to_migrate.empty?

      say ""
      say_status :update, "Updating base class references", :green

      @files_to_migrate.each do |f|
        file_path = options[:dry_run] ? f[:old] : f[:new]
        next unless File.exist?(file_path)

        if options[:dry_run]
          say_status :dry_run, "Would update base classes in #{f[:new_display]}", :yellow
        else
          update_file_base_classes(f[:new])
        end
      end
    end

    def cleanup_old_directories
      return if @files_to_migrate.nil? || @files_to_migrate.empty?

      say ""
      say_status :cleanup, "Cleaning up old directories", :green

      # Collect all old directories
      old_dirs = PATH_MAPPING.keys.map do |old_subpath|
        Rails.root.join("app", @source_root_dir, old_subpath)
      end.select { |d| File.directory?(d) }

      # Sort by depth (deepest first) for proper cleanup
      old_dirs.sort_by { |d| -d.to_s.count("/") }.each do |dir|
        cleanup_directory(dir)
      end

      # Try to remove the root directory if empty
      root_dir = Rails.root.join("app", @source_root_dir)
      if File.directory?(root_dir)
        cleanup_directory(root_dir)
      end
    end

    def show_completion_message
      say ""
      say "=" * 60
      say ""

      if options[:dry_run]
        say "Dry run complete! No changes were made.", :yellow
        say ""
        say "To perform the actual migration, run:"
        say "  rails generate ruby_llm_agents:migrate_structure"
      else
        say "Migration complete!", :green
        say ""
        say "Your app now uses the new directory structure:"
        say ""
        say "  app/"
        say "  ├── agents/"
        say "  │   ├── application_agent.rb"
        say "  │   ├── your_agent.rb"
        say "  │   ├── images/"
        say "  │   ├── audio/"
        say "  │   ├── embedders/"
        say "  │   └── moderators/"
        say "  └── workflows/"
        say ""
        say "Next steps:"
        say "  1. Update class references in your code:"
        say "     - Llm::Image::ProductGenerator -> Images::ProductGenerator"
        say "     - Llm::Audio::MeetingTranscriber -> Audio::MeetingTranscriber"
        say "     - Llm::Text::SemanticEmbedder -> Embedders::SemanticEmbedder"
        say "  2. Run your test suite: bundle exec rspec"
        say "  3. Commit the changes: git add -A && git commit -m 'Migrate to new agent structure'"
      end

      say ""
      say "=" * 60
    end

    private

    def detect_source_root
      # Check for explicitly provided source root
      if options[:source_root]
        path = Rails.root.join("app", options[:source_root])
        return options[:source_root] if File.directory?(path)
        say_status :warning, "Specified source root 'app/#{options[:source_root]}/' not found", :yellow
        return nil
      end

      # Try to get from configuration
      if defined?(RubyLLM::Agents) && RubyLLM::Agents.respond_to?(:configuration)
        config_root = RubyLLM::Agents.configuration.root_directory
        path = Rails.root.join("app", config_root)
        return config_root if File.directory?(path)
      end

      # Auto-detect common root directories
      %w[llm ai ml agents].each do |candidate|
        path = Rails.root.join("app", candidate)
        if File.directory?(path) && has_old_structure?(path)
          return candidate
        end
      end

      nil
    end

    def has_old_structure?(path)
      # Check if this looks like an old ruby_llm-agents structure
      old_indicators = %w[
        agents
        image/generators
        audio/speakers
        text/embedders
        workflows
      ]

      old_indicators.any? do |indicator|
        File.directory?(File.join(path, indicator))
      end
    end

    def in_git_repo?
      @in_git_repo ||= File.directory?(Rails.root.join(".git"))
    end

    def move_file(old_path, new_path)
      if options[:use_git] && in_git_repo?
        # Use git mv to preserve history
        old_relative = old_path.sub(Rails.root.to_s + "/", "")
        new_relative = new_path.sub(Rails.root.to_s + "/", "")
        system("git", "mv", old_relative, new_relative, chdir: Rails.root.to_s)
      else
        FileUtils.mv(old_path, new_path)
      end
    end

    def update_file_namespaces(file_path)
      content = File.read(file_path)
      original_content = content.dup
      modified = false

      # Find and replace module/class declarations with old namespaces
      # Pattern: module OldRoot ... end wrapping
      old_root_pattern = /^module\s+#{Regexp.escape(camelize(@source_root_dir))}\s*$/

      if content.match?(old_root_pattern)
        # Remove the old root module wrapper
        content = remove_root_module_wrapper(content, camelize(@source_root_dir))
        modified = true
      end

      # Update module declarations for nested namespaces
      # Image:: -> Images::
      content.gsub!(/\bmodule\s+Image\b/, "module Images") && (modified = true)

      # Text:: -> nothing (embedders/moderators are top-level now)
      # This is handled by the module removal above

      if modified && content != original_content
        File.write(file_path, content)
        say_status :updated, file_path.sub(Rails.root.to_s + "/", ""), :blue
      end
    end

    def update_file_base_classes(file_path)
      content = File.read(file_path)
      original_content = content.dup

      # Update base class references
      replacements = {
        # Application bases with old namespace
        /class\s+Application(\w+)\s*<\s*#{Regexp.escape(camelize(@source_root_dir))}::/ =>
          'class Application\1 < ',

        # Specific base classes
        /ApplicationImageGenerator/ => "ApplicationImageGenerator",
        /ApplicationImageAnalyzer/ => "ApplicationImageAnalyzer",
        /ApplicationImageEditor/ => "ApplicationImageEditor",
        /ApplicationTranscriber/ => "ApplicationTranscriber",
        /ApplicationSpeaker/ => "ApplicationSpeaker",
        /ApplicationEmbedder/ => "ApplicationEmbedder"
      }

      replacements.each do |pattern, replacement|
        content.gsub!(pattern, replacement)
      end

      if content != original_content
        File.write(file_path, content)
        say_status :updated, "base classes in #{file_path.sub(Rails.root.to_s + '/', '')}", :blue
      end
    end

    def remove_root_module_wrapper(content, root_module)
      lines = content.lines
      result = []
      module_depth = 0
      root_module_line = nil

      lines.each_with_index do |line, idx|
        if line.match?(/^\s*module\s+#{Regexp.escape(root_module)}\s*$/)
          root_module_line = idx
          module_depth = 1
          next
        end

        if root_module_line
          # Track module/class/def depth
          if line.match?(/^\s*(module|class)\s+\w/)
            module_depth += 1
          elsif line.match?(/^\s*end\s*$/)
            module_depth -= 1
            if module_depth == 0
              # This is the closing end of the root module, skip it
              root_module_line = nil
              next
            end
          end

          # Dedent by 2 spaces
          result << line.sub(/^  /, "")
        else
          result << line
        end
      end

      result.join
    end

    def cleanup_directory(dir)
      return unless File.directory?(dir)

      # First clean up any empty subdirectories
      Dir.glob("#{dir}/**/").sort_by { |d| -d.count("/") }.each do |subdir|
        next unless File.directory?(subdir) && Dir.empty?(subdir)

        if options[:dry_run]
          say_status :dry_run, "Would remove empty #{subdir.sub(Rails.root.to_s + '/', '')}", :yellow
        else
          FileUtils.rmdir(subdir)
          say_status :removed, subdir.sub(Rails.root.to_s + "/", ""), :red
        end
      end

      # Then try to remove the directory itself if empty
      return unless File.directory?(dir) && Dir.empty?(dir)

      if options[:dry_run]
        say_status :dry_run, "Would remove empty #{dir.sub(Rails.root.to_s + '/', '')}", :yellow
      else
        FileUtils.rmdir(dir)
        say_status :removed, dir.sub(Rails.root.to_s + "/", ""), :red
      end
    end

    def camelize(str)
      return "AI" if str.downcase == "ai"
      return "ML" if str.downcase == "ml"
      return "LLM" if str.downcase == "llm"

      str.split(/[-_]/).map(&:capitalize).join
    end
  end
end
