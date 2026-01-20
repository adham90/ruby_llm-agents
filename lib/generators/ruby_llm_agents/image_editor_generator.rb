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
  #   - app/image_editors/product_editor.rb (or background_editor.rb, etc.)
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

    def create_application_image_editor
      template "application_image_editor.rb.tt",
               "app/image_editors/application_image_editor.rb",
               skip: true
    end

    def create_image_editor_file
      editor_path = name.underscore
      template "image_editor.rb.tt", "app/image_editors/#{editor_path}_editor.rb"
    end

    def show_usage
      full_class_name = name.split("/").map(&:camelize).join("::")
      say ""
      say "Image editor #{full_class_name}Editor created!", :green
      say ""
      say "Usage:"
      say "  # Edit an image with a mask"
      say "  result = #{full_class_name}Editor.call("
      say "    image: 'photo.png',"
      say "    mask: 'mask.png',"
      say "    prompt: 'Replace the background with a beach scene'"
      say "  )"
      say "  result.url  # => 'https://...'"
      say ""
      say "  # Generate multiple edit variations"
      say "  result = #{full_class_name}Editor.call("
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
