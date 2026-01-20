# frozen_string_literal: true

require "rails/generators"

module RubyLlmAgents
  # ImageUpscaler generator for creating new image upscalers
  #
  # Usage:
  #   rails generate ruby_llm_agents:image_upscaler Photo
  #   rails generate ruby_llm_agents:image_upscaler Portrait --model real-esrgan --scale 4
  #   rails generate ruby_llm_agents:image_upscaler Face --face_enhance
  #
  # This will create:
  #   - app/image_upscalers/photo_upscaler.rb (or portrait_upscaler.rb, etc.)
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

    def create_application_image_upscaler
      template "application_image_upscaler.rb.tt",
               "app/image_upscalers/application_image_upscaler.rb",
               skip: true
    end

    def create_image_upscaler_file
      upscaler_path = name.underscore
      template "image_upscaler.rb.tt", "app/image_upscalers/#{upscaler_path}_upscaler.rb"
    end

    def show_usage
      full_class_name = name.split("/").map(&:camelize).join("::")
      say ""
      say "Image upscaler #{full_class_name}Upscaler created!", :green
      say ""
      say "Usage:"
      say "  # Upscale an image"
      say "  result = #{full_class_name}Upscaler.call(image: 'low_res.jpg')"
      say "  result.url          # => 'https://...'"
      say "  result.output_size  # => '4096x4096'"
      say ""
      say "  # Override settings at runtime"
      say "  result = #{full_class_name}Upscaler.call("
      say "    image: 'photo.jpg',"
      say "    scale: 8,"
      say "    face_enhance: true"
      say "  )"
      say ""
    end
  end
end
