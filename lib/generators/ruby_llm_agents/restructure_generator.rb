# frozen_string_literal: true

require "rails/generators"
require "fileutils"

module RubyLlmAgents
  # Restructure generator for migrating existing apps to new directory structure
  #
  # Migrates ruby_llm-agents directories from the flat structure:
  #   app/agents/, app/speakers/, app/embedders/, etc.
  #
  # To the new grouped structure under app/llm/:
  #   app/llm/agents/, app/llm/audio/speakers/, app/llm/image/generators/, etc.
  #
  # Usage:
  #   rails generate ruby_llm_agents:restructure
  #   rails generate ruby_llm_agents:restructure --root=ai
  #
  class RestructureGenerator < ::Rails::Generators::Base
    source_root File.expand_path("templates", __dir__)

    class_option :root,
      type: :string,
      default: nil,
      desc: "Root directory name (default: uses config or 'llm')"

    class_option :namespace,
      type: :string,
      default: nil,
      desc: "Root namespace (default: camelized root or config)"

    class_option :dry_run,
      type: :boolean,
      default: false,
      desc: "Show what would be done without making changes"

    # Maps old directory -> { category:, type: }
    DIRECTORY_MAPPING = {
      # Top-level under llm/
      "agents" => { category: nil, type: "agents" },
      "workflows" => { category: nil, type: "workflows" },
      "tools" => { category: nil, type: "tools" },

      # Audio group
      "speakers" => { category: :audio, type: "speakers" },
      "transcribers" => { category: :audio, type: "transcribers" },

      # Image group
      "image_generators" => { category: :image, type: "generators" },
      "image_editors" => { category: :image, type: "editors" },
      "image_analyzers" => { category: :image, type: "analyzers" },
      "image_transformers" => { category: :image, type: "transformers" },
      "image_upscalers" => { category: :image, type: "upscalers" },
      "image_variators" => { category: :image, type: "variators" },
      "background_removers" => { category: :image, type: "background_removers" },

      # Text group
      "embedders" => { category: :text, type: "embedders" },
      "moderators" => { category: :text, type: "moderators" }
    }.freeze

    def validate_root_directory
      unless root_directory.match?(/\A[a-z][a-z0-9_-]*\z/i)
        raise ArgumentError, "Invalid root directory name: #{root_directory}. " \
                             "Must start with a letter and contain only letters, numbers, underscores, or hyphens."
      end
    end

    def create_directory_structure
      say_status :create, "#{root_directory}/ directory structure", :green

      if options[:dry_run]
        say_status :dry_run, "Would create directory structure under app/#{root_directory}/", :yellow
        return
      end

      # Create root directory
      empty_directory "app/#{root_directory}"

      # Create all subdirectories
      config.all_autoload_paths.each do |path|
        empty_directory path
      end
    end

    def move_directories
      say ""
      say_status :migrate, "Moving directories to new structure", :green

      directories_moved = 0

      DIRECTORY_MAPPING.each do |old_dir, mapping|
        source = Rails.root.join("app", old_dir)
        next unless File.directory?(source)

        destination = Rails.root.join(config.path_for(mapping[:category], mapping[:type]))

        if options[:dry_run]
          say_status :dry_run, "Would move app/#{old_dir}/* -> #{destination}", :yellow
          directories_moved += 1
          next
        end

        move_directory_contents(source, destination, old_dir)
        directories_moved += 1
      end

      if directories_moved == 0
        say_status :skip, "No directories found to migrate", :yellow
      end
    end

    def update_namespaces
      say ""
      say_status :update, "Adding namespaces to Ruby files", :green

      DIRECTORY_MAPPING.each do |_old_dir, mapping|
        directory_path = Rails.root.join(config.path_for(mapping[:category], mapping[:type]))
        next unless File.directory?(directory_path)

        namespace = config.namespace_for(mapping[:category])

        Dir.glob("#{directory_path}/**/*.rb").each do |file|
          update_file_namespace(file, namespace)
        end
      end
    end

    def cleanup_empty_directories
      say ""
      say_status :cleanup, "Removing empty old directories", :green

      DIRECTORY_MAPPING.keys.each do |old_dir|
        path = Rails.root.join("app", old_dir)
        next unless File.directory?(path)

        if Dir.empty?(path)
          if options[:dry_run]
            say_status :dry_run, "Would remove empty directory app/#{old_dir}", :yellow
          else
            FileUtils.rmdir(path)
            say_status :removed, "app/#{old_dir}", :red
          end
        else
          say_status :warning, "app/#{old_dir} is not empty, skipping removal", :yellow
        end
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
        say "  rails generate ruby_llm_agents:restructure"
      else
        say "Migration complete!", :green
        say ""
        say "Your app now uses the new directory structure:"
        say ""
        say "  app/#{root_directory}/"
        say "  ├── agents/"
        say "  ├── audio/"
        say "  │   ├── speakers/"
        say "  │   └── transcribers/"
        say "  ├── image/"
        say "  │   ├── analyzers/"
        say "  │   ├── generators/"
        say "  │   └── ..."
        say "  ├── text/"
        say "  │   ├── embedders/"
        say "  │   └── moderators/"
        say "  ├── workflows/"
        say "  └── tools/"
        say ""
        say "Namespaces have been updated to use #{root_namespace}::"
        say ""
        say "Next steps:"
        say "  1. Update any explicit class references in your code"
        say "  2. Run your test suite to verify everything works"
        say "  3. Commit the changes"
      end
      say ""
      say "=" * 60
    end

    private

    def root_directory
      @root_directory ||= options[:root] || RubyLLM::Agents.configuration.root_directory
    end

    def root_namespace
      @root_namespace ||= options[:namespace] || camelize(root_directory)
    end

    def config
      @config ||= begin
        c = RubyLLM::Agents.configuration.dup
        c.root_directory = root_directory
        c.root_namespace = root_namespace
        c
      end
    end

    def camelize(str)
      # Handle special cases for common abbreviations
      return "AI" if str.downcase == "ai"
      return "ML" if str.downcase == "ml"
      return "LLM" if str.downcase == "llm"

      # Standard camelization
      str.split(/[-_]/).map(&:capitalize).join
    end

    def move_directory_contents(source, destination, old_dir_name)
      # Ensure destination exists
      FileUtils.mkdir_p(destination) unless File.directory?(destination)

      # Move all contents
      Dir.glob("#{source}/**/*", File::FNM_DOTMATCH).each do |item|
        next if item.end_with?(".", "..")
        next if File.directory?(item)

        relative_path = item.sub("#{source}/", "")
        dest_item = File.join(destination, relative_path)

        FileUtils.mkdir_p(File.dirname(dest_item))
        FileUtils.mv(item, dest_item)

        say_status :moved, "app/#{old_dir_name}/#{relative_path}", :green
      end

      # Remove old directory if empty
      cleanup_empty_subdirs(source)
      FileUtils.rmdir(source) if File.directory?(source) && Dir.empty?(source)
    end

    def cleanup_empty_subdirs(dir)
      return unless File.directory?(dir)

      Dir.glob("#{dir}/**/").reverse_each do |subdir|
        FileUtils.rmdir(subdir) if Dir.empty?(subdir)
      rescue SystemCallError
        # Ignore errors if directory is not empty or already removed
      end
    end

    def update_file_namespace(file, namespace)
      content = File.read(file)

      # Skip if already has the namespace
      first_module = namespace.split("::").first
      return if content.include?("module #{first_module}")

      # Add namespace
      updated = add_namespace(content, namespace)
      File.write(file, updated)

      say_status :namespaced, file.sub(Rails.root.to_s + "/", ""), :blue
    end

    def add_namespace(content, namespace)
      modules = namespace.split("::")
      indent = ""

      # Build opening modules
      opening = modules.map do |mod|
        line = "#{indent}module #{mod}"
        indent += "  "
        line
      end.join("\n")

      # Build closing modules
      closing = modules.map { "end" }.join("\n")

      # Indent original content
      indented_content = content.lines.map do |line|
        if line.strip.empty?
          line
        else
          ("  " * modules.size) + line
        end
      end.join

      "#{opening}\n#{indented_content}#{closing}\n"
    end
  end
end
