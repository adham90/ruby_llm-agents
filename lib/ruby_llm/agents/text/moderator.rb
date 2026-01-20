# frozen_string_literal: true

require_relative "../results/moderation_result"

module RubyLLM
  module Agents
    # Standalone moderator for content moderation using the middleware pipeline
    #
    # Provides a class-based interface for moderating content with built-in
    # support for caching, instrumentation, and multi-tenancy through the
    # middleware pipeline.
    #
    # @example Basic usage
    #   class ContentModerator < RubyLLM::Agents::Moderator
    #     model 'omni-moderation-latest'
    #   end
    #
    #   result = ContentModerator.call(text: "content to check")
    #   result.flagged?  # => true/false
    #
    # @example With configuration
    #   class StrictModerator < RubyLLM::Agents::Moderator
    #     model 'omni-moderation-latest'
    #     threshold 0.7
    #     categories :hate, :violence, :harassment
    #   end
    #
    # @example Runtime override
    #   result = ContentModerator.call(
    #     text: "content",
    #     threshold: 0.9,
    #     categories: [:hate]
    #   )
    #
    # @api public
    class Moderator < BaseAgent
      class << self
        # Returns the agent type for moderators
        #
        # @return [Symbol] :moderation
        def agent_type
          :moderation
        end

        # @!group Moderation-specific DSL

        # Sets or returns the moderation model
        #
        # Defaults to the moderation model from configuration, not the
        # conversation model that BaseAgent uses.
        #
        # @param value [String, nil] Model identifier to set
        # @return [String] Current model setting
        def model(value = nil)
          @model = value if value
          return @model if defined?(@model) && @model

          # For inheritance: check if parent is also a Moderator
          if superclass.respond_to?(:agent_type) && superclass.agent_type == :moderation
            superclass.model
          else
            default_moderation_model
          end
        end

        # Sets or returns the score threshold
        #
        # @param value [Float, nil] Threshold value (0.0-1.0)
        # @return [Float, nil] Current threshold
        def threshold(value = nil)
          @threshold = value if value
          @threshold || inherited_or_default(:threshold, nil)
        end

        # Sets or returns the categories to check
        #
        # @param cats [Array<Symbol>] Category symbols
        # @return [Array<Symbol>, nil] Current categories
        def categories(*cats)
          @categories = cats.flatten.map(&:to_sym) if cats.any?
          @categories || inherited_or_default(:categories, nil)
        end

        # @!endgroup

        # Factory method to instantiate and execute moderation
        #
        # @param text [String] Text to moderate
        # @param options [Hash] Runtime options
        # @option options [String] :model Override moderation model
        # @option options [Float] :threshold Override threshold
        # @option options [Array<Symbol>] :categories Override categories
        # @option options [Object] :tenant Tenant for multi-tenancy
        # @return [ModerationResult] The moderation result
        def call(text:, **options)
          new(text: text, **options).call
        end

        private

        def inherited_or_default(method, default)
          superclass.respond_to?(method) ? superclass.send(method) : default
        end

        def default_moderation_model
          RubyLLM::Agents.configuration.default_moderation_model
        rescue StandardError
          "omni-moderation-latest"
        end
      end

      # @!attribute [r] text
      #   @return [String] Text to moderate
      attr_reader :text

      # Creates a new Moderator instance
      #
      # @param text [String] Text to moderate
      # @param options [Hash] Runtime options
      def initialize(text:, **options)
        @text = text
        @runtime_threshold = options.delete(:threshold)
        @runtime_categories = options.delete(:categories)

        # Set model to moderation model if not specified
        options[:model] ||= self.class.model

        super(**options)
      end

      # Executes the moderation through the middleware pipeline
      #
      # @return [ModerationResult] The moderation result
      def call
        context = build_context
        result_context = Pipeline::Executor.execute(context)
        result_context.output
      end

      # The input for this moderation operation
      #
      # Used by the pipeline to generate cache keys and for instrumentation.
      #
      # @return [String] The text being moderated
      def user_prompt
        text
      end

      # Core moderation execution
      #
      # This is called by the Pipeline::Executor after middleware
      # has been applied. Only contains the moderation API logic.
      #
      # @param context [Pipeline::Context] The execution context
      # @return [void] Sets context.output with the ModerationResult
      def execute(context)
        # Track timing internally
        execution_started_at = Time.current

        moderation_opts = {}
        moderation_opts[:model] = resolved_model if resolved_model

        raw_result = RubyLLM.moderate(text, **moderation_opts)

        execution_completed_at = Time.current
        duration_ms = ((execution_completed_at - execution_started_at) * 1000).to_i

        # Update context with basic info (no tokens for moderation)
        context.input_tokens = 0
        context.output_tokens = 0
        context.total_cost = 0.0

        # Build final result
        context.output = ModerationResult.new(
          result: raw_result,
          threshold: resolved_threshold,
          categories: resolved_categories
        )
      end

      # Generates the cache key for this moderation
      #
      # @return [String] Cache key in format "ruby_llm_agents/moderation/..."
      def agent_cache_key
        components = [
          "ruby_llm_agents",
          "moderation",
          self.class.name,
          self.class.version,
          resolved_model,
          resolved_threshold,
          resolved_categories&.sort&.join(","),
          Digest::SHA256.hexdigest(text)
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
          skip_cache: @options[:skip_cache]
        )
      end

      # Resolves the model to use
      #
      # @return [String] The model identifier
      def resolved_model
        @model || self.class.model
      end

      # Resolves the threshold to use
      #
      # @return [Float, nil] The threshold
      def resolved_threshold
        @runtime_threshold || self.class.threshold
      end

      # Resolves the categories to check
      #
      # @return [Array<Symbol>, nil] The categories
      def resolved_categories
        @runtime_categories || self.class.categories
      end
    end
  end
end
