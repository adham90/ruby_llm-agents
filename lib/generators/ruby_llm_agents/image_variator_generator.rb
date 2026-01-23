# frozen_string_literal: true

require "rails/generators"

module RubyLlmAgents
  # ImageVariator generator for creating new image variators
  #
  # Usage:
  #   rails generate ruby_llm_agents:image_variator Logo
  #   rails generate ruby_llm_agents:image_variator Product --model gpt-image-1 --size 1024x1024
  #   rails generate ruby_llm_agents:image_variator Avatar --variation_strength 0.3
  #
  # This will create:
  #   - app/agents/images/logo_variator.rb
  #
  class ImageVariatorGenerator < ::Rails::Generators::NamedBase
    source_root File.expand_path("templates", __dir__)

    class_option :model, type: :string, default: "gpt-image-1",
                 desc: "The image model to use"
    class_option :size, type: :string, default: "1024x1024",
                 desc: "Output image size (e.g., 1024x1024)"
    class_option :variation_strength, type: :string, default: "0.5",
                 desc: "Variation strength (0.0-1.0)"
    class_option :cache, type: :string, default: nil,
                 desc: "Cache TTL (e.g., '1.hour', '1.day')"

    def ensure_base_class_and_skill_file
      images_dir = "app/agents/images"

      # Create directory if needed
      empty_directory images_dir

      # Create base class if it doesn't exist
      base_class_path = "#{images_dir}/application_image_variator.rb"
      unless File.exist?(File.join(destination_root, base_class_path))
        template "application_image_variator.rb.tt", base_class_path
      end

      # Create skill file if it doesn't exist
      skill_file_path = "#{images_dir}/IMAGE_VARIATORS.md"
      unless File.exist?(File.join(destination_root, skill_file_path))
        template "skills/IMAGE_VARIATORS.md.tt", skill_file_path
      end
    end

    def create_image_variator_file
      variator_path = name.underscore
      template "image_variator.rb.tt", "app/agents/images/#{variator_path}_variator.rb"
    end

    def show_usage
      variator_class_name = name.split("/").map(&:camelize).join("::")
      full_class_name = "Images::#{variator_class_name}Variator"
      say ""
      say "Image variator #{full_class_name} created!", :green
      say ""
      say "Usage:"
      say "  # Generate variations of an image"
      say "  result = #{full_class_name}.call(image: 'logo.png', count: 4)"
      say "  result.urls  # => ['https://...', ...]"
      say ""
      say "  # Override settings at runtime"
      say "  result = #{full_class_name}.call("
      say "    image: 'logo.png',"
      say "    variation_strength: 0.7,"
      say "    count: 3"
      say "  )"
      say ""
    end
  end
end
