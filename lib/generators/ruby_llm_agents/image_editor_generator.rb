# frozen_string_literal: true

require "rails/generators"

module RubyLlmAgents
  # ImageEditor generator for creating new image editors
  #
  # Usage:
  #   rails generate ruby_llm_agents:image_editor Product
  #   rails generate ruby_llm_agents:image_editor Background --model gpt-image-1 --size 1024x1024
  #   rails generate ruby_llm_agents:image_editor Photo --content_policy strict
  #
  # This will create:
  #   - app/agents/images/product_editor.rb
  #
  class ImageEditorGenerator < ::Rails::Generators::NamedBase
    source_root File.expand_path("templates", __dir__)

    class_option :model, type: :string, default: "gpt-image-1",
                 desc: "The image model to use"
    class_option :size, type: :string, default: "1024x1024",
                 desc: "Output image size (e.g., 1024x1024)"
    class_option :content_policy, type: :string, default: "standard",
                 desc: "Content policy level (none, standard, moderate, strict)"
    class_option :cache, type: :string, default: nil,
                 desc: "Cache TTL (e.g., '1.hour', '1.day')"

    def ensure_base_class_and_skill_file
      images_dir = "app/agents/images"

      # Create directory if needed
      empty_directory images_dir

      # Create base class if it doesn't exist
      base_class_path = "#{images_dir}/application_image_editor.rb"
      unless File.exist?(File.join(destination_root, base_class_path))
        template "application_image_editor.rb.tt", base_class_path
      end

      # Create skill file if it doesn't exist
      skill_file_path = "#{images_dir}/IMAGE_EDITORS.md"
      unless File.exist?(File.join(destination_root, skill_file_path))
        template "skills/IMAGE_EDITORS.md.tt", skill_file_path
      end
    end

    def create_image_editor_file
      editor_path = name.underscore
      template "image_editor.rb.tt", "app/agents/images/#{editor_path}_editor.rb"
    end

    def show_usage
      editor_class_name = name.split("/").map(&:camelize).join("::")
      full_class_name = "Images::#{editor_class_name}Editor"
      say ""
      say "Image editor #{full_class_name} created!", :green
      say ""
      say "Usage:"
      say "  # Edit an image with a mask"
      say "  result = #{full_class_name}.call("
      say "    image: 'photo.png',"
      say "    mask: 'mask.png',"
      say "    prompt: 'Replace the background with a beach scene'"
      say "  )"
      say "  result.url  # => 'https://...'"
      say ""
      say "  # Generate multiple edit variations"
      say "  result = #{full_class_name}.call("
      say "    image: 'photo.png',"
      say "    mask: 'mask.png',"
      say "    prompt: 'Add a sunset',"
      say "    count: 3"
      say "  )"
      say "  result.urls  # => ['https://...', ...]"
      say ""
    end
  end
end
