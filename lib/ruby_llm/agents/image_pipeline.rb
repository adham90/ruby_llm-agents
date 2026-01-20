# frozen_string_literal: true

require_relative "image_pipeline/dsl"
require_relative "image_pipeline/execution"

module RubyLLM
  module Agents
    # Image pipeline for chaining multiple image operations
    #
    # Orchestrates complex image workflows by chaining generators,
    # transformers, upscalers, analyzers, and other image operations
    # into a single pipeline with aggregated results and costs.
    #
    # @example Basic pipeline
    #   class ProductPipeline < RubyLLM::Agents::ImagePipeline
    #     step :generate, generator: ProductGenerator
    #     step :upscale, upscaler: PhotoUpscaler
    #     step :remove_background, remover: BackgroundRemover
    #   end
    #
    #   result = ProductPipeline.call(prompt: "Professional laptop photo")
    #   result.final_image   # => The processed image
    #   result.total_cost    # => Combined cost of all steps
    #
    # @example Pipeline with analysis
    #   class AnalysisPipeline < RubyLLM::Agents::ImagePipeline
    #     step :generate, generator: ProductGenerator
    #     step :analyze, analyzer: ProductAnalyzer
    #
    #     description "Generates and analyzes product images"
    #   end
    #
    #   result = AnalysisPipeline.call(prompt: "Wireless earbuds")
    #   result.analysis   # => ImageAnalysisResult from analyzer step
    #
    # @example Conditional pipeline
    #   class SmartPipeline < RubyLLM::Agents::ImagePipeline
    #     step :generate, generator: ProductGenerator
    #     step :upscale, upscaler: PhotoUpscaler, if: ->(ctx) { ctx[:upscale] }
    #     step :remove_background, remover: BackgroundRemover, if: ->(ctx) { ctx[:transparent] }
    #   end
    #
    #   result = SmartPipeline.call(prompt: "...", upscale: true, transparent: false)
    #
    class ImagePipeline
      extend DSL
      include Execution

      class << self
        # Execute pipeline with the given options
        #
        # @param options [Hash] Pipeline options
        # @option options [String] :prompt Prompt for generation steps
        # @option options [String, IO] :image Input image for non-generation pipelines
        # @option options [Object] :tenant Tenant for multi-tenancy
        # @return [ImagePipelineResult] The combined result of all steps
        def call(**options)
          new(**options).call
        end

        # Ensure subclasses inherit DSL settings and steps
        def inherited(subclass)
          super
          # Copy steps to subclass
          subclass.instance_variable_set(:@steps, @steps&.dup || [])
          subclass.instance_variable_set(:@callbacks, @callbacks&.dup || { before: [], after: [] })
          subclass.instance_variable_set(:@version, @version)
          subclass.instance_variable_set(:@description, @description)
          subclass.instance_variable_set(:@cache_ttl, @cache_ttl)
          subclass.instance_variable_set(:@stop_on_error, @stop_on_error)
        end
      end

      attr_reader :options, :tenant_id, :step_results, :context

      # Initialize a new pipeline instance
      #
      # @param options [Hash] Pipeline options
      # @option options [String] :prompt Prompt for generation steps
      # @option options [String, IO] :image Input image
      # @option options [Object] :tenant Tenant for multi-tenancy
      def initialize(**options)
        @options = options
        @tenant_id = nil
        @step_results = []
        @context = options.dup
      end

      # Execute the pipeline
      #
      # @return [ImagePipelineResult] The combined result of all steps
      def call
        execute
      end
    end
  end
end
