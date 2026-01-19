# frozen_string_literal: true

require "rails/generators"

module RubyLlmAgents
  # Embedder generator for creating new embedders
  #
  # Usage:
  #   rails generate ruby_llm_agents:embedder Document
  #   rails generate ruby_llm_agents:embedder Document --model text-embedding-3-large
  #   rails generate ruby_llm_agents:embedder Document --dimensions 512
  #
  # This will create:
  #   - app/embedders/document_embedder.rb
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

    def create_embedder_file
      # Support nested paths: "search/document" -> "app/embedders/search/document_embedder.rb"
      embedder_path = name.underscore
      template "embedder.rb.tt", "app/embedders/#{embedder_path}_embedder.rb"
    end

    def show_usage
      # Build full class name from path
      full_class_name = name.split("/").map(&:camelize).join("::")
      say ""
      say "Embedder #{full_class_name}Embedder created!", :green
      say ""
      say "Usage:"
      say "  # Single text"
      say "  #{full_class_name}Embedder.call(text: \"Hello world\")"
      say ""
      say "  # Multiple texts (batch)"
      say "  #{full_class_name}Embedder.call(texts: [\"Hello\", \"World\"])"
      say ""
      say "  # With progress tracking"
      say "  #{full_class_name}Embedder.call(texts: large_array) do |batch, idx|"
      say "    puts \"Processed batch \#{idx}\""
      say "  end"
      say ""
    end
  end
end
