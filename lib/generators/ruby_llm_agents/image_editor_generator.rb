# frozen_string_literal: true

require "rails/generators"

module RubyLlmAgents
  # ImageEditor generator for creating new image editors
  #
  # Usage:
  #   rails generate ruby_llm_agents:image_editor Product
  #   rails generate ruby_llm_agents:image_editor Background --model gpt-image-1 --size 1024x1024
  #   rails generate ruby_llm_agents:image_editor Photo --content_policy strict
  #   rails generate ruby_llm_agents:image_editor Product --root=ai
  #
  # This will create:
  #   - app/{root}/image/editors/product_editor.rb
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
    class_option :root,
                 type: :string,
                 default: nil,
                 desc: "Root directory name (default: uses config or 'llm')"
    class_option :namespace,
                 type: :string,
                 default: nil,
                 desc: "Root namespace (default: camelized root or config)"

    def create_image_editor_file
      @root_namespace = root_namespace
      @image_namespace = "#{root_namespace}::Image"
      editor_path = name.underscore
      template "image_editor.rb.tt", "app/#{root_directory}/image/editors/#{editor_path}_editor.rb"
    end

    def show_usage
      editor_class_name = name.split("/").map(&:camelize).join("::")
      full_class_name = "#{root_namespace}::Image::#{editor_class_name}Editor"
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

    private

    def root_directory
      @root_directory ||= options[:root] || RubyLLM::Agents.configuration.root_directory
    end

    def root_namespace
      @root_namespace ||= options[:namespace] || camelize(root_directory)
    end

    def camelize(str)
      return "AI" if str.downcase == "ai"
      return "ML" if str.downcase == "ml"
      return "LLM" if str.downcase == "llm"
      str.split(/[-_]/).map(&:capitalize).join
    end
  end
end
