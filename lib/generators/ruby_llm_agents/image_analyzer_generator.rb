# frozen_string_literal: true

require "rails/generators"

module RubyLlmAgents
  # ImageAnalyzer generator for creating new image analyzers
  #
  # Usage:
  #   rails generate ruby_llm_agents:image_analyzer Product
  #   rails generate ruby_llm_agents:image_analyzer Content --model gpt-4o --analysis_type detailed
  #   rails generate ruby_llm_agents:image_analyzer Photo --extract_colors --detect_objects
  #
  # This will create:
  #   - app/image_analyzers/product_analyzer.rb (or content_analyzer.rb, etc.)
  #
  class ImageAnalyzerGenerator < ::Rails::Generators::NamedBase
    source_root File.expand_path("templates", __dir__)

    class_option :model, type: :string, default: "gpt-4o",
                 desc: "The vision model to use"
    class_option :analysis_type, type: :string, default: "detailed",
                 desc: "Analysis type (caption, detailed, tags, objects, colors, all)"
    class_option :extract_colors, type: :boolean, default: false,
                 desc: "Enable color extraction"
    class_option :detect_objects, type: :boolean, default: false,
                 desc: "Enable object detection"
    class_option :extract_text, type: :boolean, default: false,
                 desc: "Enable text extraction (OCR)"
    class_option :max_tags, type: :string, default: "10",
                 desc: "Maximum number of tags to return"
    class_option :cache, type: :string, default: nil,
                 desc: "Cache TTL (e.g., '1.hour', '1.day')"

    def create_application_image_analyzer
      template "application_image_analyzer.rb.tt",
               "app/image_analyzers/application_image_analyzer.rb",
               skip: true
    end

    def create_image_analyzer_file
      analyzer_path = name.underscore
      template "image_analyzer.rb.tt", "app/image_analyzers/#{analyzer_path}_analyzer.rb"
    end

    def show_usage
      full_class_name = name.split("/").map(&:camelize).join("::")
      say ""
      say "Image analyzer #{full_class_name}Analyzer created!", :green
      say ""
      say "Usage:"
      say "  # Analyze an image"
      say "  result = #{full_class_name}Analyzer.call(image: 'photo.jpg')"
      say "  result.caption      # => 'A sunset over mountains'"
      say "  result.tags         # => ['sunset', 'mountains', 'nature']"
      say "  result.description  # => 'Detailed description...'"
      say ""
      say "  # Override settings at runtime"
      say "  result = #{full_class_name}Analyzer.call("
      say "    image: 'product.jpg',"
      say "    analysis_type: :all,"
      say "    extract_colors: true,"
      say "    detect_objects: true"
      say "  )"
      say ""
      say "  # Access detected objects and colors"
      say "  result.objects  # => [{name: 'laptop', location: 'center', confidence: 'high'}]"
      say "  result.colors   # => [{hex: '#C0C0C0', name: 'silver', percentage: 45}]"
      say ""
    end
  end
end
