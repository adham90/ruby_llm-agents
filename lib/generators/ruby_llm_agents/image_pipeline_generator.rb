# frozen_string_literal: true

require "rails/generators"

module RubyLlmAgents
  # ImagePipeline generator for creating new image pipelines
  #
  # Usage:
  #   rails generate ruby_llm_agents:image_pipeline Product
  #   rails generate ruby_llm_agents:image_pipeline Ecommerce --steps generate,upscale,remove_background
  #   rails generate ruby_llm_agents:image_pipeline Content --steps generate,analyze
  #
  # This will create:
  #   - app/agents/images/product_pipeline.rb
  #
  class ImagePipelineGenerator < ::Rails::Generators::NamedBase
    source_root File.expand_path("templates", __dir__)

    class_option :steps, type: :string, default: "generate,upscale",
                 desc: "Pipeline steps (comma-separated: generate,upscale,transform,analyze,remove_background)"
    class_option :stop_on_error, type: :boolean, default: true,
                 desc: "Stop pipeline on first error"
    class_option :cache, type: :string, default: nil,
                 desc: "Cache TTL (e.g., '1.hour', '1.day')"

    def ensure_base_class_and_skill_file
      images_dir = "app/agents/images"

      # Create directory if needed
      empty_directory images_dir

      # Create base class if it doesn't exist
      base_class_path = "#{images_dir}/application_image_pipeline.rb"
      unless File.exist?(File.join(destination_root, base_class_path))
        template "application_image_pipeline.rb.tt", base_class_path
      end

      # Create skill file if it doesn't exist
      skill_file_path = "#{images_dir}/IMAGE_PIPELINES.md"
      unless File.exist?(File.join(destination_root, skill_file_path))
        template "skills/IMAGE_PIPELINES.md.tt", skill_file_path
      end
    end

    def create_image_pipeline_file
      pipeline_path = name.underscore
      template "image_pipeline.rb.tt", "app/agents/images/#{pipeline_path}_pipeline.rb"
    end

    def create_step_classes
      # Create stub classes for referenced steps if they don't exist
      parsed_steps.each do |step|
        create_step_stub(step) if should_create_stub?(step)
      end
    end

    def show_usage
      pipeline_class_name = name.split("/").map(&:camelize).join("::")
      full_class_name = "Images::#{pipeline_class_name}Pipeline"
      say ""
      say "Image pipeline #{full_class_name} created!", :green
      say ""
      say "Usage:"
      say "  # Run the pipeline"
      say "  result = #{full_class_name}.call(prompt: 'Product photo')"
      say "  result.final_image   # => The processed image"
      say "  result.total_cost    # => Combined cost of all steps"
      say "  result.step_count    # => Number of steps executed"
      say ""
      say "  # Access individual step results"
      say "  result.step(:generate)  # => ImageGenerationResult"
      say "  result.step(:upscale)   # => ImageUpscaleResult"
      say "  result.analysis         # => ImageAnalysisResult (if analyzer step)"
      say ""
      say "  # Save the final image"
      say "  result.save('output.png')"
      say ""
      say "  # With tenant tracking"
      say "  result = #{full_class_name}.call("
      say "    prompt: 'Product photo',"
      say "    tenant: current_organization"
      say "  )"
      say ""
    end

    private

    def parsed_steps
      options[:steps].to_s.split(",").map(&:strip).map(&:to_sym)
    end

    def should_create_stub?(step)
      case step
      when :generate
        !File.exist?("app/agents/images/#{name.underscore}_generator.rb")
      when :upscale
        !File.exist?("app/agents/images/#{name.underscore}_upscaler.rb")
      when :transform
        !File.exist?("app/agents/images/#{name.underscore}_transformer.rb")
      when :analyze
        !File.exist?("app/agents/images/#{name.underscore}_analyzer.rb")
      when :remove_background
        !File.exist?("app/agents/images/#{name.underscore}_background_remover.rb")
      else
        false
      end
    end

    def create_step_stub(step)
      # Just show a note - don't auto-create stubs
      case step
      when :generate
        say "  Note: You may want to create #{name}Generator with:", :yellow
        say "    rails generate ruby_llm_agents:image_generator #{name}"
      when :upscale
        say "  Note: You may want to create #{name}Upscaler with:", :yellow
        say "    rails generate ruby_llm_agents:image_upscaler #{name}"
      when :transform
        say "  Note: You may want to create #{name}Transformer with:", :yellow
        say "    rails generate ruby_llm_agents:image_transformer #{name}"
      when :analyze
        say "  Note: You may want to create #{name}Analyzer with:", :yellow
        say "    rails generate ruby_llm_agents:image_analyzer #{name}"
      when :remove_background
        say "  Note: You may want to create #{name}BackgroundRemover with:", :yellow
        say "    rails generate ruby_llm_agents:background_remover #{name}"
      end
    end

    def step_classes
      @step_classes ||= parsed_steps.map do |step|
        class_base = name.split("/").map(&:camelize).join("::")
        case step
        when :generate
          { step: step, type: :generator, class_name: "Images::#{class_base}Generator" }
        when :upscale
          { step: step, type: :upscaler, class_name: "Images::#{class_base}Upscaler" }
        when :transform
          { step: step, type: :transformer, class_name: "Images::#{class_base}Transformer" }
        when :analyze
          { step: step, type: :analyzer, class_name: "Images::#{class_base}Analyzer" }
        when :remove_background
          { step: step, type: :remover, class_name: "Images::#{class_base}BackgroundRemover" }
        else
          { step: step, type: step, class_name: "Images::#{class_base}#{step.to_s.camelize}" }
        end
      end
    end
  end
end
