# frozen_string_literal: true

require "rails/generators"

module RubyLlmAgents
  # Embedder generator for creating new embedders
  #
  # Usage:
  #   rails generate ruby_llm_agents:embedder Document
  #   rails generate ruby_llm_agents:embedder Document --model text-embedding-3-large
  #   rails generate ruby_llm_agents:embedder Document --dimensions 512
  #   rails generate ruby_llm_agents:embedder Document --root=ai
  #
  # This will create:
  #   - app/{root}/text/embedders/document_embedder.rb
  #
  class EmbedderGenerator < ::Rails::Generators::NamedBase
    source_root File.expand_path("templates", __dir__)

    class_option :model, type: :string, default: "text-embedding-3-small",
                 desc: "The embedding model to use"
    class_option :dimensions, type: :numeric, default: nil,
                 desc: "Vector dimensions (nil for model default)"
    class_option :batch_size, type: :numeric, default: 100,
                 desc: "Texts per API call for batch processing"
    class_option :cache, type: :string, default: nil,
                 desc: "Cache TTL (e.g., '1.week', '1.day')"
    class_option :root,
                 type: :string,
                 default: nil,
                 desc: "Root directory name (default: uses config or 'llm')"
    class_option :namespace,
                 type: :string,
                 default: nil,
                 desc: "Root namespace (default: camelized root or config)"

    def ensure_base_class_and_skill_file
      @root_namespace = root_namespace
      @text_namespace = "#{root_namespace}::Text"
      embedders_dir = "app/#{root_directory}/text/embedders"

      # Create directory if needed
      empty_directory embedders_dir

      # Create base class if it doesn't exist
      base_class_path = "#{embedders_dir}/application_embedder.rb"
      unless File.exist?(File.join(destination_root, base_class_path))
        template "application_embedder.rb.tt", base_class_path
      end

      # Create skill file if it doesn't exist
      skill_file_path = "#{embedders_dir}/EMBEDDERS.md"
      unless File.exist?(File.join(destination_root, skill_file_path))
        template "skills/EMBEDDERS.md.tt", skill_file_path
      end
    end

    def create_embedder_file
      # Support nested paths: "search/document" -> "app/{root}/text/embedders/search/document_embedder.rb"
      @root_namespace = root_namespace
      @text_namespace = "#{root_namespace}::Text"
      embedder_path = name.underscore
      template "embedder.rb.tt", "app/#{root_directory}/text/embedders/#{embedder_path}_embedder.rb"
    end

    def show_usage
      # Build full class name from path
      embedder_class_name = name.split("/").map(&:camelize).join("::")
      full_class_name = "#{root_namespace}::Text::#{embedder_class_name}Embedder"
      say ""
      say "Embedder #{full_class_name} created!", :green
      say ""
      say "Usage:"
      say "  # Single text"
      say "  #{full_class_name}.call(text: \"Hello world\")"
      say ""
      say "  # Multiple texts (batch)"
      say "  #{full_class_name}.call(texts: [\"Hello\", \"World\"])"
      say ""
      say "  # With progress tracking"
      say "  #{full_class_name}.call(texts: large_array) do |batch, idx|"
      say "    puts \"Processed batch \#{idx}\""
      say "  end"
      say ""
    end

    private

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
