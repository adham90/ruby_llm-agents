# frozen_string_literal: true

require_relative "image_generator/dsl"
require_relative "image_generator/execution"
require_relative "image_generator/pricing"
require_relative "image_generator/content_policy"
require_relative "image_generator/templates"
require_relative "image_generator/active_storage_support"

module RubyLLM
  module Agents
    # Image generator base class for text-to-image generation
    #
    # Follows the same patterns as Embedder and Moderator - standalone classes
    # with their own DSL, execution flow, and result wrappers.
    #
    # @example Basic usage
    #   result = RubyLLM::Agents::ImageGenerator.call(prompt: "A sunset over mountains")
    #   result.url # => "https://..."
    #
    # @example Custom generator class
    #   class LogoGenerator < RubyLLM::Agents::ImageGenerator
    #     model "gpt-image-1"
    #     size "1024x1024"
    #     quality "hd"
    #     style "vivid"
    #
    #     description "Generates company logos"
    #     content_policy :strict
    #   end
    #
    #   result = LogoGenerator.call(prompt: "Minimalist tech company logo")
    #
    class ImageGenerator
      extend DSL
      include Execution

      class << self
        # Execute image generation with the given prompt
        #
        # @param prompt [String] The text prompt for image generation
        # @param options [Hash] Additional options (model, size, quality, etc.)
        # @return [ImageGenerationResult] The result containing generated images
        def call(prompt:, **options)
          new(prompt: prompt, **options).call
        end

        # Ensure subclasses inherit DSL settings
        def inherited(subclass)
          super
          subclass.instance_variable_set(:@model, @model)
          subclass.instance_variable_set(:@size, @size)
          subclass.instance_variable_set(:@quality, @quality)
          subclass.instance_variable_set(:@style, @style)
          subclass.instance_variable_set(:@version, @version)
          subclass.instance_variable_set(:@description, @description)
          subclass.instance_variable_set(:@cache_ttl, @cache_ttl)
          subclass.instance_variable_set(:@content_policy, @content_policy)
          subclass.instance_variable_set(:@negative_prompt, @negative_prompt)
          subclass.instance_variable_set(:@seed, @seed)
          subclass.instance_variable_set(:@guidance_scale, @guidance_scale)
          subclass.instance_variable_set(:@steps, @steps)
          subclass.instance_variable_set(:@template_string, @template_string)
        end
      end

      attr_reader :prompt, :options, :tenant_id

      # Initialize a new image generator instance
      #
      # @param prompt [String] The text prompt for image generation
      # @param options [Hash] Additional options
      # @option options [String] :model Model to use
      # @option options [String] :size Image size (e.g., "1024x1024")
      # @option options [String] :quality Quality level ("standard", "hd")
      # @option options [String] :style Style preset ("vivid", "natural")
      # @option options [Integer] :count Number of images to generate
      # @option options [Object] :tenant Tenant for multi-tenancy
      def initialize(prompt:, **options)
        @prompt = prompt
        @options = options
        @tenant_id = nil
      end

      # Execute the image generation
      #
      # @return [ImageGenerationResult] The result containing generated images
      def call
        execute
      end
    end
  end
end
