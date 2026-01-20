# frozen_string_literal: true

require "rails/generators"

module RubyLlmAgents
  # ImageGenerator generator for creating new image generators
  #
  # Usage:
  #   rails generate ruby_llm_agents:image_generator Logo
  #   rails generate ruby_llm_agents:image_generator Product --model gpt-image-1 --size 1024x1024
  #   rails generate ruby_llm_agents:image_generator Avatar --quality hd --style vivid
  #
  # This will create:
  #   - app/image_generators/logo_generator.rb (or product_generator.rb, etc.)
  #
  class ImageGeneratorGenerator < ::Rails::Generators::NamedBase
    source_root File.expand_path("templates", __dir__)

    class_option :model, type: :string, default: "gpt-image-1",
                 desc: "The image generation model to use"
    class_option :size, type: :string, default: "1024x1024",
                 desc: "Image size (e.g., 1024x1024, 1792x1024)"
    class_option :quality, type: :string, default: "standard",
                 desc: "Image quality (standard, hd)"
    class_option :style, type: :string, default: "vivid",
                 desc: "Image style (vivid, natural)"
    class_option :content_policy, type: :string, default: "standard",
                 desc: "Content policy level (none, standard, moderate, strict)"
    class_option :cache, type: :string, default: nil,
                 desc: "Cache TTL (e.g., '1.hour', '1.day')"

    def create_application_image_generator
      template "application_image_generator.rb.tt",
               "app/image_generators/application_image_generator.rb",
               skip: true
    end

    def create_image_generator_file
      # Support nested paths: "product/hero" -> "app/image_generators/product/hero_generator.rb"
      generator_path = name.underscore
      template "image_generator.rb.tt", "app/image_generators/#{generator_path}_generator.rb"
    end

    def show_usage
      # Build full class name from path
      full_class_name = name.split("/").map(&:camelize).join("::")
      say ""
      say "Image generator #{full_class_name}Generator created!", :green
      say ""
      say "Usage:"
      say "  # Generate a single image"
      say "  result = #{full_class_name}Generator.call(prompt: \"A beautiful sunset\")"
      say "  result.url        # => \"https://...\""
      say "  result.save(\"sunset.png\")"
      say ""
      say "  # Generate multiple images"
      say "  result = #{full_class_name}Generator.call(prompt: \"Logos\", count: 4)"
      say "  result.urls       # => [\"https://...\", ...]"
      say ""
      say "  # Override settings at runtime"
      say "  result = #{full_class_name}Generator.call("
      say "    prompt: \"High quality portrait\","
      say "    quality: \"hd\","
      say "    size: \"1792x1024\""
      say "  )"
      say ""
    end
  end
end
