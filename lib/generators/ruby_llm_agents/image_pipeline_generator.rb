# frozen_string_literal: true

require "rails/generators"

module RubyLlmAgents
  # ImagePipeline generator for creating new image pipelines
  #
  # Usage:
  #   rails generate ruby_llm_agents:image_pipeline Product
  #   rails generate ruby_llm_agents:image_pipeline Ecommerce --steps generate,upscale,remove_background
  #   rails generate ruby_llm_agents:image_pipeline Content --steps generate,analyze
  #   rails generate ruby_llm_agents:image_pipeline Product --root=ai
  #
  # This will create:
  #   - app/{root}/image/pipelines/product_pipeline.rb
  #
  class ImagePipelineGenerator < ::Rails::Generators::NamedBase
    source_root File.expand_path("templates", __dir__)

    class_option :steps, type: :string, default: "generate,upscale",
                 desc: "Pipeline steps (comma-separated: generate,upscale,transform,analyze,remove_background)"
    class_option :stop_on_error, type: :boolean, default: true,
                 desc: "Stop pipeline on first error"
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

    def create_image_pipeline_file
      @root_namespace = root_namespace
      @image_namespace = "#{root_namespace}::Image"
      pipeline_path = name.underscore
      template "image_pipeline.rb.tt", "app/#{root_directory}/image/pipelines/#{pipeline_path}_pipeline.rb"
    end

    def create_step_classes
      # Create stub classes for referenced steps if they don't exist
      parsed_steps.each do |step|
        create_step_stub(step) if should_create_stub?(step)
      end
    end

    def show_usage
      pipeline_class_name = name.split("/").map(&:camelize).join("::")
      full_class_name = "#{root_namespace}::Image::#{pipeline_class_name}Pipeline"
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

    def parsed_steps
      options[:steps].to_s.split(",").map(&:strip).map(&:to_sym)
    end

    def should_create_stub?(step)
      case step
      when :generate
        !File.exist?("app/#{root_directory}/image/generators/#{name.underscore}_generator.rb")
      when :upscale
        !File.exist?("app/#{root_directory}/image/upscalers/#{name.underscore}_upscaler.rb")
      when :transform
        !File.exist?("app/#{root_directory}/image/transformers/#{name.underscore}_transformer.rb")
      when :analyze
        !File.exist?("app/#{root_directory}/image/analyzers/#{name.underscore}_analyzer.rb")
      when :remove_background
        !File.exist?("app/#{root_directory}/image/background_removers/#{name.underscore}_background_remover.rb")
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
          { step: step, type: :generator, class_name: "#{@image_namespace}::#{class_base}Generator" }
        when :upscale
          { step: step, type: :upscaler, class_name: "#{@image_namespace}::#{class_base}Upscaler" }
        when :transform
          { step: step, type: :transformer, class_name: "#{@image_namespace}::#{class_base}Transformer" }
        when :analyze
          { step: step, type: :analyzer, class_name: "#{@image_namespace}::#{class_base}Analyzer" }
        when :remove_background
          { step: step, type: :remover, class_name: "#{@image_namespace}::#{class_base}BackgroundRemover" }
        else
          { step: step, type: step, class_name: "#{@image_namespace}::#{class_base}#{step.to_s.camelize}" }
        end
      end
    end
  end
end
