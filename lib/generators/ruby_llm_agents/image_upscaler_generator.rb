# frozen_string_literal: true

require "rails/generators"

module RubyLlmAgents
  # ImageUpscaler generator for creating new image upscalers
  #
  # Usage:
  #   rails generate ruby_llm_agents:image_upscaler Photo
  #   rails generate ruby_llm_agents:image_upscaler Portrait --model real-esrgan --scale 4
  #   rails generate ruby_llm_agents:image_upscaler Face --face_enhance
  #   rails generate ruby_llm_agents:image_upscaler Photo --root=ai
  #
  # This will create:
  #   - app/{root}/image/upscalers/photo_upscaler.rb
  #
  class ImageUpscalerGenerator < ::Rails::Generators::NamedBase
    source_root File.expand_path("templates", __dir__)

    class_option :model, type: :string, default: "real-esrgan",
                 desc: "The upscaling model to use"
    class_option :scale, type: :string, default: "4",
                 desc: "Upscale factor (2, 4, or 8)"
    class_option :face_enhance, type: :boolean, default: false,
                 desc: "Enable face enhancement"
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

    def create_image_upscaler_file
      @root_namespace = root_namespace
      @image_namespace = "#{root_namespace}::Image"
      upscaler_path = name.underscore
      template "image_upscaler.rb.tt", "app/#{root_directory}/image/upscalers/#{upscaler_path}_upscaler.rb"
    end

    def show_usage
      upscaler_class_name = name.split("/").map(&:camelize).join("::")
      full_class_name = "#{root_namespace}::Image::#{upscaler_class_name}Upscaler"
      say ""
      say "Image upscaler #{full_class_name} created!", :green
      say ""
      say "Usage:"
      say "  # Upscale an image"
      say "  result = #{full_class_name}.call(image: 'low_res.jpg')"
      say "  result.url          # => 'https://...'"
      say "  result.output_size  # => '4096x4096'"
      say ""
      say "  # Override settings at runtime"
      say "  result = #{full_class_name}.call("
      say "    image: 'photo.jpg',"
      say "    scale: 8,"
      say "    face_enhance: true"
      say "  )"
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
