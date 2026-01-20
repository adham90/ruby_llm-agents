# frozen_string_literal: true

module RubyLLM
  module Agents
    class Base
      # DSL for configuring content moderation on agents
      #
      # Provides declarative configuration for moderating user input
      # and/or LLM output against safety policies.
      #
      # @example Basic input moderation
      #   class MyAgent < ApplicationAgent
      #     moderation :input
      #   end
      #
      # @example Moderate both input and output
      #   class MyAgent < ApplicationAgent
      #     moderation :both
      #   end
      #
      # @example With configuration options
      #   class MyAgent < ApplicationAgent
      #     moderation :input,
      #       model: 'omni-moderation-latest',
      #       threshold: 0.8,
      #       categories: [:hate, :violence],
      #       on_flagged: :raise
      #   end
      #
      # @example Block-based DSL
      #   class MyAgent < ApplicationAgent
      #     moderation do
      #       input enabled: true, threshold: 0.7
      #       output enabled: true, threshold: 0.9
      #       model 'omni-moderation-latest'
      #       categories :hate, :violence
      #       on_flagged :block
      #     end
      #   end
      #
      # @api public
      module ModerationDSL
        # Configures content moderation for this agent
        #
        # @param phases [Array<Symbol>] Phases to moderate (:input, :output, :both)
        # @param model [String] Moderation model to use
        # @param threshold [Float] Score threshold (0.0-1.0) for flagging
        # @param categories [Array<Symbol>] Categories to check
        # @param on_flagged [Symbol] Action when flagged (:block, :raise, :warn, :log)
        # @param custom_handler [Symbol] Method name for custom handling
        # @yield Block for advanced configuration
        # @return [Hash, nil] The moderation configuration
        #
        # @example Simple input moderation
        #   moderation :input
        #
        # @example Input and output moderation
        #   moderation :input, :output
        #   # or
        #   moderation :both
        #
        # @example With options
        #   moderation :input, threshold: 0.8, on_flagged: :raise
        def moderation(*phases, **options, &block)
          if block_given?
            builder = ModerationBuilder.new
            builder.instance_eval(&block)
            @moderation_config = builder.config
          else
            # Handle :both shorthand
            phases = [:input, :output] if phases.include?(:both)
            phases = [:input] if phases.empty?

            @moderation_config = {
              phases: phases.flatten.map(&:to_sym),
              model: options[:model],
              threshold: options[:threshold],
              categories: options[:categories],
              on_flagged: options[:on_flagged] || :block,
              custom_handler: options[:custom_handler]
            }
          end
        end

        # Returns the moderation configuration for this agent
        #
        # @return [Hash, nil] The moderation configuration or nil if not configured
        def moderation_config
          @moderation_config || inherited_or_default(:moderation_config, nil)
        end

        # Returns whether moderation is enabled for this agent
        #
        # @return [Boolean] true if moderation is configured
        def moderation_enabled?
          !!moderation_config
        end
      end

      # Builder class for block-based moderation configuration
      #
      # @api private
      class ModerationBuilder
        attr_reader :config

        def initialize
          @config = {
            phases: [],
            on_flagged: :block
          }
        end

        # Enables input moderation
        #
        # @param enabled [Boolean] Whether to enable input moderation
        # @param threshold [Float, nil] Score threshold for input phase
        # @return [void]
        def input(enabled: true, threshold: nil)
          @config[:phases] << :input if enabled
          @config[:input_threshold] = threshold if threshold
        end

        # Enables output moderation
        #
        # @param enabled [Boolean] Whether to enable output moderation
        # @param threshold [Float, nil] Score threshold for output phase
        # @return [void]
        def output(enabled: true, threshold: nil)
          @config[:phases] << :output if enabled
          @config[:output_threshold] = threshold if threshold
        end

        # Sets the moderation model
        #
        # @param model_name [String] Model identifier
        # @return [void]
        def model(model_name)
          @config[:model] = model_name
        end

        # Sets the global threshold
        #
        # @param value [Float] Score threshold (0.0-1.0)
        # @return [void]
        def threshold(value)
          @config[:threshold] = value
        end

        # Sets categories to check
        #
        # @param cats [Array<Symbol>] Category symbols
        # @return [void]
        def categories(*cats)
          @config[:categories] = cats.flatten.map(&:to_sym)
        end

        # Sets the action when content is flagged
        #
        # @param action [Symbol] :block, :raise, :warn, or :log
        # @return [void]
        def on_flagged(action)
          @config[:on_flagged] = action
        end

        # Sets a custom handler method
        #
        # @param method_name [Symbol] Method name to call on the agent
        # @return [void]
        def custom_handler(method_name)
          @config[:custom_handler] = method_name
        end
      end
    end
  end
end
