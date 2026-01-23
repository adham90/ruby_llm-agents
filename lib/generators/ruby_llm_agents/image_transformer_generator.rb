# frozen_string_literal: true

require "rails/generators"

module RubyLlmAgents
  # ImageTransformer generator for creating new image transformers
  #
  # Usage:
  #   rails generate ruby_llm_agents:image_transformer Anime
  #   rails generate ruby_llm_agents:image_transformer Watercolor --model sdxl --strength 0.8
  #   rails generate ruby_llm_agents:image_transformer Oil --template "oil painting, {prompt}"
  #
  # This will create:
  #   - app/agents/images/anime_transformer.rb
  #
  class ImageTransformerGenerator < ::Rails::Generators::NamedBase
    source_root File.expand_path("templates", __dir__)

    class_option :model, type: :string, default: "sdxl",
                 desc: "The image model to use"
    class_option :size, type: :string, default: "1024x1024",
                 desc: "Output image size (e.g., 1024x1024)"
    class_option :strength, type: :string, default: "0.75",
                 desc: "Transformation strength (0.0-1.0)"
    class_option :template, type: :string, default: nil,
                 desc: "Prompt template (use {prompt} as placeholder)"
    class_option :content_policy, type: :string, default: "standard",
                 desc: "Content policy level (none, standard, moderate, strict)"
    class_option :cache, type: :string, default: nil,
                 desc: "Cache TTL (e.g., '1.hour', '1.day')"

    def ensure_base_class_and_skill_file
      images_dir = "app/agents/images"

      # Create directory if needed
      empty_directory images_dir

      # Create base class if it doesn't exist
      base_class_path = "#{images_dir}/application_image_transformer.rb"
      unless File.exist?(File.join(destination_root, base_class_path))
        template "application_image_transformer.rb.tt", base_class_path
      end

      # Create skill file if it doesn't exist
      skill_file_path = "#{images_dir}/IMAGE_TRANSFORMERS.md"
      unless File.exist?(File.join(destination_root, skill_file_path))
        template "skills/IMAGE_TRANSFORMERS.md.tt", skill_file_path
      end
    end

    def create_image_transformer_file
      transformer_path = name.underscore
      template "image_transformer.rb.tt", "app/agents/images/#{transformer_path}_transformer.rb"
    end

    def show_usage
      transformer_class_name = name.split("/").map(&:camelize).join("::")
      full_class_name = "Images::#{transformer_class_name}Transformer"
      say ""
      say "Image transformer #{full_class_name} created!", :green
      say ""
      say "Usage:"
      say "  # Transform an image with a style"
      say "  result = #{full_class_name}.call("
      say "    image: 'photo.jpg',"
      say "    prompt: 'portrait of a person'"
      say "  )"
      say "  result.url  # => 'https://...'"
      say ""
      say "  # Override strength at runtime"
      say "  result = #{full_class_name}.call("
      say "    image: 'photo.jpg',"
      say "    prompt: 'detailed portrait',"
      say "    strength: 0.9"
      say "  )"
      say ""
    end
  end
end
