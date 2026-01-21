# frozen_string_literal: true

require "rails/generators"

module RubyLlmAgents
  # ImageGenerator generator for creating new image generators
  #
  # Usage:
  #   rails generate ruby_llm_agents:image_generator Logo
  #   rails generate ruby_llm_agents:image_generator Product --model gpt-image-1 --size 1024x1024
  #   rails generate ruby_llm_agents:image_generator Avatar --quality hd --style vivid
  #   rails generate ruby_llm_agents:image_generator Logo --root=ai
  #
  # This will create:
  #   - app/{root}/image/generators/logo_generator.rb
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
    class_option :root,
                 type: :string,
                 default: nil,
                 desc: "Root directory name (default: uses config or 'llm')"
    class_option :namespace,
                 type: :string,
                 default: nil,
                 desc: "Root namespace (default: camelized root or config)"

    def ensure_base_class_and_skill_file
      @root_namespace = root_namespace
      @image_namespace = "#{root_namespace}::Image"
      generators_dir = "app/#{root_directory}/image/generators"

      # Create directory if needed
      empty_directory generators_dir

      # Create base class if it doesn't exist
      base_class_path = "#{generators_dir}/application_image_generator.rb"
      unless File.exist?(File.join(destination_root, base_class_path))
        template "application_image_generator.rb.tt", base_class_path
      end

      # Create skill file if it doesn't exist
      skill_file_path = "#{generators_dir}/IMAGE_GENERATORS.md"
      unless File.exist?(File.join(destination_root, skill_file_path))
        template "skills/IMAGE_GENERATORS.md.tt", skill_file_path
      end
    end

    def create_image_generator_file
      # Support nested paths: "product/hero" -> "app/{root}/image/generators/product/hero_generator.rb"
      @root_namespace = root_namespace
      @image_namespace = "#{root_namespace}::Image"
      generator_path = name.underscore
      template "image_generator.rb.tt", "app/#{root_directory}/image/generators/#{generator_path}_generator.rb"
    end

    def show_usage
      # Build full class name from path
      generator_class_name = name.split("/").map(&:camelize).join("::")
      full_class_name = "#{root_namespace}::Image::#{generator_class_name}Generator"
      say ""
      say "Image generator #{full_class_name} created!", :green
      say ""
      say "Usage:"
      say "  # Generate a single image"
      say "  result = #{full_class_name}.call(prompt: \"A beautiful sunset\")"
      say "  result.url        # => \"https://...\""
      say "  result.save(\"sunset.png\")"
      say ""
      say "  # Generate multiple images"
      say "  result = #{full_class_name}.call(prompt: \"Logos\", count: 4)"
      say "  result.urls       # => [\"https://...\", ...]"
      say ""
      say "  # Override settings at runtime"
      say "  result = #{full_class_name}.call("
      say "    prompt: \"High quality portrait\","
      say "    quality: \"hd\","
      say "    size: \"1792x1024\""
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
      # Handle special cases for common abbreviations
      return "AI" if str.downcase == "ai"
      return "ML" if str.downcase == "ml"
      return "LLM" if str.downcase == "llm"

      # Standard camelization
      str.split(/[-_]/).map(&:capitalize).join
    end
  end
end
