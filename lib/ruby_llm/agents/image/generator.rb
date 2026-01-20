# frozen_string_literal: true

require "digest"

module RubyLLM
  module Agents
    # Image generator base class for text-to-image generation using the middleware pipeline
    #
    # Follows the same patterns as other agents - inherits from BaseAgent for unified
    # execution flow, caching, instrumentation, and budget controls through middleware.
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
    # @api public
    class ImageGenerator < BaseAgent
      class << self
        # Returns the agent type for image generators
        #
        # @return [Symbol] :image
        def agent_type
          :image
        end

        # @!group Image-specific DSL

        # Sets or returns the image generation model
        #
        # @param value [String, nil] Model identifier
        # @return [String] The model to use
        def model(value = nil)
          @model = value if value
          return @model if defined?(@model) && @model

          if superclass.respond_to?(:agent_type) && superclass.agent_type == :image
            superclass.model
          else
            default_image_model
          end
        end

        # Sets or returns the image size
        #
        # @param value [String, nil] Size (e.g., "1024x1024", "1792x1024")
        # @return [String] The size to use
        def size(value = nil)
          @size = value if value
          @size || inherited_or_default(:size, default_image_size)
        end

        # Sets or returns the quality level
        #
        # @param value [String, nil] Quality ("standard", "hd")
        # @return [String] The quality to use
        def quality(value = nil)
          @quality = value if value
          @quality || inherited_or_default(:quality, default_image_quality)
        end

        # Sets or returns the style preset
        #
        # @param value [String, nil] Style ("vivid", "natural")
        # @return [String] The style to use
        def style(value = nil)
          @style = value if value
          @style || inherited_or_default(:style, default_image_style)
        end

        # Sets or returns the content policy level
        #
        # @param level [Symbol, nil] Policy level (:none, :standard, :moderate, :strict)
        # @return [Symbol] The content policy level
        def content_policy(level = nil)
          @content_policy = level if level
          @content_policy || inherited_or_default(:content_policy, :standard)
        end

        # Sets or returns negative prompt (things to avoid in generation)
        #
        # @param value [String, nil] Negative prompt text
        # @return [String, nil] The negative prompt
        def negative_prompt(value = nil)
          @negative_prompt = value if value
          @negative_prompt || inherited_or_default(:negative_prompt, nil)
        end

        # Sets or returns the seed for reproducible generation
        #
        # @param value [Integer, nil] Seed value
        # @return [Integer, nil] The seed
        def seed(value = nil)
          @seed = value if value
          @seed || inherited_or_default(:seed, nil)
        end

        # Sets or returns guidance scale (CFG scale)
        #
        # @param value [Float, nil] Guidance scale (typically 1.0-20.0)
        # @return [Float, nil] The guidance scale
        def guidance_scale(value = nil)
          @guidance_scale = value if value
          @guidance_scale || inherited_or_default(:guidance_scale, nil)
        end

        # Sets or returns number of inference steps
        #
        # @param value [Integer, nil] Number of steps
        # @return [Integer, nil] The steps
        def steps(value = nil)
          @steps = value if value
          @steps || inherited_or_default(:steps, nil)
        end

        # Sets a prompt template (use {prompt} as placeholder)
        #
        # @param value [String, nil] Template string
        # @return [String, nil] The template
        def template(value = nil)
          @template_string = value if value
          @template_string || inherited_or_default(:template_string, nil)
        end

        # Gets the template string
        #
        # @return [String, nil] The template string
        def template_string
          @template_string || inherited_or_default(:template_string, nil)
        end

        # @!endgroup

        # Factory method to execute image generation
        #
        # @param prompt [String] The text prompt for image generation
        # @param options [Hash] Additional options
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

        private

        def inherited_or_default(method, default)
          superclass.respond_to?(method) ? superclass.send(method) : default
        end

        def default_image_model
          RubyLLM::Agents.configuration.default_image_model
        rescue StandardError
          "dall-e-3"
        end

        def default_image_size
          RubyLLM::Agents.configuration.default_image_size
        rescue StandardError
          "1024x1024"
        end

        def default_image_quality
          RubyLLM::Agents.configuration.default_image_quality
        rescue StandardError
          "standard"
        end

        def default_image_style
          RubyLLM::Agents.configuration.default_image_style
        rescue StandardError
          "vivid"
        end
      end

      # @!attribute [r] prompt
      #   @return [String] The text prompt for image generation
      attr_reader :prompt

      # Creates a new ImageGenerator instance
      #
      # @param prompt [String] The text prompt for image generation
      # @param options [Hash] Additional options
      def initialize(prompt:, **options)
        @prompt = prompt
        @runtime_count = options.delete(:count) || 1

        # Set model to image model if not specified
        options[:model] ||= self.class.model

        super(**options)
      end

      # Executes the image generation through the middleware pipeline
      #
      # @return [ImageGenerationResult] The result containing generated images
      def call
        context = build_context
        result_context = Pipeline::Executor.execute(context)
        result_context.output
      end

      # The input for this generation operation
      #
      # @return [String] The prompt
      def user_prompt
        prompt
      end

      # Core image generation execution
      #
      # This is called by the Pipeline::Executor after middleware
      # has been applied. Only contains the image generation API logic.
      #
      # @param context [Pipeline::Context] The execution context
      # @return [void] Sets context.output with the ImageGenerationResult
      def execute(context)
        execution_started_at = Time.current

        validate_prompt!
        validate_content_policy!

        # Generate image(s)
        images = generate_images

        execution_completed_at = Time.current
        duration_ms = ((execution_completed_at - execution_started_at) * 1000).to_i

        # Build result
        result = build_result(
          images: images,
          started_at: context.started_at || execution_started_at,
          completed_at: execution_completed_at,
          tenant_id: context.tenant_id
        )

        # Update context with cost info
        context.input_tokens = result.input_tokens
        context.output_tokens = 0
        context.total_cost = result.total_cost

        context.output = result
      rescue StandardError => e
        execution_completed_at = Time.current
        context.output = build_error_result(
          e,
          started_at: context.started_at || execution_started_at,
          completed_at: execution_completed_at,
          tenant_id: context.tenant_id
        )
      end

      # Generates the cache key for this image generation
      #
      # @return [String] Cache key
      def agent_cache_key
        components = [
          "ruby_llm_agents",
          "image_generator",
          self.class.name,
          self.class.version,
          resolved_model,
          resolved_size,
          resolved_quality,
          resolved_style,
          Digest::SHA256.hexdigest(prompt)
        ].compact

        components.join("/")
      end

      private

      # Builds context for pipeline execution
      #
      # @return [Pipeline::Context] The context object
      def build_context
        Pipeline::Context.new(
          input: user_prompt,
          agent_class: self.class,
          agent_instance: self,
          model: resolved_model,
          tenant: @options[:tenant],
          skip_cache: @options[:skip_cache] || !single_image_request?
        )
      end

      # Validates the prompt
      def validate_prompt!
        raise ArgumentError, "Prompt cannot be blank" if prompt.nil? || prompt.strip.empty?

        max_length = config.max_image_prompt_length || 4000
        if prompt.length > max_length
          raise ArgumentError, "Prompt exceeds maximum length of #{max_length} characters"
        end
      end

      # Validates prompt against content policy
      def validate_content_policy!
        policy = self.class.content_policy
        return if policy == :none || policy == :standard

        ContentPolicy.validate!(prompt, policy)
      end

      # Generate images using RubyLLM.paint
      def generate_images
        count = @runtime_count

        Array.new(count) do
          paint_options = build_paint_options
          RubyLLM.paint(apply_template(prompt), **paint_options)
        end
      end

      # Build options hash for RubyLLM.paint
      def build_paint_options
        opts = {
          model: resolved_model,
          size: resolved_size
        }

        opts[:quality] = resolved_quality if resolved_quality
        opts[:style] = resolved_style if resolved_style
        opts[:negative_prompt] = resolved_negative_prompt if resolved_negative_prompt
        opts[:seed] = resolved_seed if resolved_seed
        opts[:guidance_scale] = resolved_guidance_scale if resolved_guidance_scale
        opts[:steps] = resolved_steps if resolved_steps
        opts[:assume_model_exists] = true if @options[:assume_model_exists]

        opts
      end

      # Apply prompt template if defined
      def apply_template(text)
        template = self.class.try(:template_string)
        return text unless template

        template.gsub("{prompt}", text)
      end

      # Build successful result
      def build_result(images:, started_at:, completed_at:, tenant_id:)
        ImageGenerationResult.new(
          images: images,
          prompt: prompt,
          model_id: resolved_model,
          size: resolved_size,
          quality: resolved_quality,
          style: resolved_style,
          started_at: started_at,
          completed_at: completed_at,
          tenant_id: tenant_id,
          generator_class: self.class.name
        )
      end

      # Build error result
      def build_error_result(error, started_at:, completed_at:, tenant_id:)
        ImageGenerationResult.new(
          images: [],
          prompt: prompt,
          model_id: resolved_model,
          size: resolved_size,
          quality: resolved_quality,
          style: resolved_style,
          started_at: started_at,
          completed_at: completed_at,
          tenant_id: tenant_id,
          generator_class: self.class.name,
          error_class: error.class.name,
          error_message: error.message
        )
      end

      # Resolution methods (runtime options override class config)

      def resolved_model
        model = @options[:model] || @model || self.class.model
        # Handle aliases
        config.image_model_aliases&.dig(model.to_sym) || model
      end

      def resolved_size
        @options[:size] || self.class.size
      end

      def resolved_quality
        @options[:quality] || self.class.quality
      end

      def resolved_style
        @options[:style] || self.class.style
      end

      def resolved_negative_prompt
        @options[:negative_prompt] || self.class.negative_prompt
      end

      def resolved_seed
        @options[:seed] || self.class.seed
      end

      def resolved_guidance_scale
        @options[:guidance_scale] || self.class.guidance_scale
      end

      def resolved_steps
        @options[:steps] || self.class.steps
      end

      def single_image_request?
        @runtime_count == 1
      end

      def config
        RubyLLM::Agents.configuration
      end
    end
  end
end

# Load supporting modules after class is defined (they reopen the class)
require_relative "generator/pricing"
require_relative "generator/content_policy"
require_relative "generator/templates"
require_relative "generator/active_storage_support"
