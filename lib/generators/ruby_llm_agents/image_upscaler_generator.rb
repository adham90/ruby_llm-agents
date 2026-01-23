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
  #   - app/agents/images/photo_upscaler.rb
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

    def ensure_base_class_and_skill_file
      images_dir = "app/agents/images"

      # Create directory if needed
      empty_directory images_dir

      # Create base class if it doesn't exist
      base_class_path = "#{images_dir}/application_image_upscaler.rb"
      unless File.exist?(File.join(destination_root, base_class_path))
        template "application_image_upscaler.rb.tt", base_class_path
      end

      # Create skill file if it doesn't exist
      skill_file_path = "#{images_dir}/IMAGE_UPSCALERS.md"
      unless File.exist?(File.join(destination_root, skill_file_path))
        template "skills/IMAGE_UPSCALERS.md.tt", skill_file_path
      end
    end

    def create_image_upscaler_file
      upscaler_path = name.underscore
      template "image_upscaler.rb.tt", "app/agents/images/#{upscaler_path}_upscaler.rb"
    end

    def show_usage
      upscaler_class_name = name.split("/").map(&:camelize).join("::")
      full_class_name = "Images::#{upscaler_class_name}Upscaler"
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
  end
end
