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
  #   - app/image_variators/logo_variator.rb (or product_variator.rb, etc.)
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

    def create_application_image_variator
      template "application_image_variator.rb.tt",
               "app/image_variators/application_image_variator.rb",
               skip: true
    end

    def create_image_variator_file
      variator_path = name.underscore
      template "image_variator.rb.tt", "app/image_variators/#{variator_path}_variator.rb"
    end

    def show_usage
      full_class_name = name.split("/").map(&:camelize).join("::")
      say ""
      say "Image variator #{full_class_name}Variator created!", :green
      say ""
      say "Usage:"
      say "  # Generate variations of an image"
      say "  result = #{full_class_name}Variator.call(image: 'logo.png', count: 4)"
      say "  result.urls  # => ['https://...', ...]"
      say ""
      say "  # Override settings at runtime"
      say "  result = #{full_class_name}Variator.call("
      say "    image: 'logo.png',"
      say "    variation_strength: 0.7,"
      say "    count: 3"
      say "  )"
      say ""
    end
  end
end
