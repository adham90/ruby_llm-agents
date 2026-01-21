# frozen_string_literal: true

require "rails/generators"

module RubyLlmAgents
  # BackgroundRemover generator for creating new background removers
  #
  # Usage:
  #   rails generate ruby_llm_agents:background_remover Product
  #   rails generate ruby_llm_agents:background_remover Portrait --model segment-anything --alpha_matting
  #   rails generate ruby_llm_agents:background_remover Photo --refine_edges --return_mask
  #   rails generate ruby_llm_agents:background_remover Product --root=ai
  #
  # This will create:
  #   - app/{root}/image/background_removers/product_background_remover.rb
  #
  class BackgroundRemoverGenerator < ::Rails::Generators::NamedBase
    source_root File.expand_path("templates", __dir__)

    class_option :model, type: :string, default: "rembg",
                 desc: "The segmentation model to use"
    class_option :output_format, type: :string, default: "png",
                 desc: "Output format (png, webp)"
    class_option :refine_edges, type: :boolean, default: false,
                 desc: "Enable edge refinement"
    class_option :alpha_matting, type: :boolean, default: false,
                 desc: "Enable alpha matting for better edges"
    class_option :return_mask, type: :boolean, default: false,
                 desc: "Also return the segmentation mask"
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
      removers_dir = "app/#{root_directory}/image/background_removers"

      # Create directory if needed
      empty_directory removers_dir

      # Create base class if it doesn't exist
      base_class_path = "#{removers_dir}/application_background_remover.rb"
      unless File.exist?(File.join(destination_root, base_class_path))
        template "application_background_remover.rb.tt", base_class_path
      end

      # Create skill file if it doesn't exist
      skill_file_path = "#{removers_dir}/BACKGROUND_REMOVERS.md"
      unless File.exist?(File.join(destination_root, skill_file_path))
        template "skills/BACKGROUND_REMOVERS.md.tt", skill_file_path
      end
    end

    def create_background_remover_file
      @root_namespace = root_namespace
      @image_namespace = "#{root_namespace}::Image"
      remover_path = name.underscore
      template "background_remover.rb.tt", "app/#{root_directory}/image/background_removers/#{remover_path}_background_remover.rb"
    end

    def show_usage
      remover_class_name = name.split("/").map(&:camelize).join("::")
      full_class_name = "#{root_namespace}::Image::#{remover_class_name}BackgroundRemover"
      say ""
      say "Background remover #{full_class_name} created!", :green
      say ""
      say "Usage:"
      say "  # Remove background from an image"
      say "  result = #{full_class_name}.call(image: 'photo.jpg')"
      say "  result.url        # => 'https://...' (transparent PNG)"
      say "  result.has_alpha? # => true"
      say ""
      say "  # Override settings at runtime"
      say "  result = #{full_class_name}.call("
      say "    image: 'portrait.jpg',"
      say "    alpha_matting: true,"
      say "    return_mask: true"
      say "  )"
      say ""
      say "  # Access the segmentation mask"
      say "  result.mask_url  # => 'https://...' (if return_mask was enabled)"
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
