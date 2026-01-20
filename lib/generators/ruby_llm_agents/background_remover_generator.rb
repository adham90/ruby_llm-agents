# frozen_string_literal: true

require "rails/generators"

module RubyLlmAgents
  # BackgroundRemover generator for creating new background removers
  #
  # Usage:
  #   rails generate ruby_llm_agents:background_remover Product
  #   rails generate ruby_llm_agents:background_remover Portrait --model segment-anything --alpha_matting
  #   rails generate ruby_llm_agents:background_remover Photo --refine_edges --return_mask
  #
  # This will create:
  #   - app/background_removers/product_background_remover.rb (or portrait_background_remover.rb, etc.)
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

    def create_application_background_remover
      template "application_background_remover.rb.tt",
               "app/background_removers/application_background_remover.rb",
               skip: true
    end

    def create_background_remover_file
      remover_path = name.underscore
      template "background_remover.rb.tt", "app/background_removers/#{remover_path}_background_remover.rb"
    end

    def show_usage
      full_class_name = name.split("/").map(&:camelize).join("::")
      say ""
      say "Background remover #{full_class_name}BackgroundRemover created!", :green
      say ""
      say "Usage:"
      say "  # Remove background from an image"
      say "  result = #{full_class_name}BackgroundRemover.call(image: 'photo.jpg')"
      say "  result.url        # => 'https://...' (transparent PNG)"
      say "  result.has_alpha? # => true"
      say ""
      say "  # Override settings at runtime"
      say "  result = #{full_class_name}BackgroundRemover.call("
      say "    image: 'portrait.jpg',"
      say "    alpha_matting: true,"
      say "    return_mask: true"
      say "  )"
      say ""
      say "  # Access the segmentation mask"
      say "  result.mask_url  # => 'https://...' (if return_mask was enabled)"
      say ""
    end
  end
end
