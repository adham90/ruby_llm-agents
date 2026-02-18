# frozen_string_literal: true

module RubyLLM
  module Agents
    module Pricing
      # Extracts pricing from the ruby_llm gem's built-in model registry.
      #
      # This is a local, zero-HTTP-cost source that provides pricing for
      # models that ruby_llm knows about. It's the fastest adapter since
      # all data is already loaded in-process.
      #
      # Uses RubyLLM::Models.find(model_id) which returns pricing as
      # USD per million tokens.
      #
      # @example
      #   RubyLLMAdapter.find_model("gpt-4o")
      #   # => { input_cost_per_token: 0.0000025, output_cost_per_token: 0.00001, source: :ruby_llm }
      #
      module RubyLLMAdapter
        extend self

        # Find and normalize pricing for a model from ruby_llm's registry
        #
        # @param model_id [String] The model identifier
        # @return [Hash, nil] Normalized pricing hash or nil
        def find_model(model_id)
          return nil unless defined?(::RubyLLM::Models)

          model_info = ::RubyLLM::Models.find(model_id)
          return nil unless model_info

          normalize(model_info)
        rescue
          nil
        end

        private

        def normalize(model_info)
          pricing = model_info.pricing
          return nil unless pricing

          result = {source: :ruby_llm}

          # Text tokens (per million → per token)
          text_tokens = pricing.respond_to?(:text_tokens) ? pricing.text_tokens : nil
          if text_tokens
            input_per_million = text_tokens.respond_to?(:input) ? text_tokens.input : nil
            output_per_million = text_tokens.respond_to?(:output) ? text_tokens.output : nil

            if input_per_million.is_a?(Numeric) && input_per_million.positive?
              result[:input_cost_per_token] = input_per_million / 1_000_000.0
            end

            if output_per_million.is_a?(Numeric) && output_per_million.positive?
              result[:output_cost_per_token] = output_per_million / 1_000_000.0
            end
          end

          # Audio tokens (per million → per token) if available
          audio_tokens = pricing.respond_to?(:audio_tokens) ? pricing.audio_tokens : nil
          if audio_tokens
            audio_input = audio_tokens.respond_to?(:input) ? audio_tokens.input : nil
            audio_output = audio_tokens.respond_to?(:output) ? audio_tokens.output : nil

            if audio_input.is_a?(Numeric) && audio_input.positive?
              result[:input_cost_per_audio_token] = audio_input / 1_000_000.0
            end

            if audio_output.is_a?(Numeric) && audio_output.positive?
              result[:output_cost_per_audio_token] = audio_output / 1_000_000.0
            end
          end

          # Image pricing if available
          images = pricing.respond_to?(:images) ? pricing.images : nil
          if images
            per_image = images.respond_to?(:input) ? images.input : nil
            if per_image.is_a?(Numeric) && per_image.positive?
              result[:input_cost_per_image] = per_image
            end
          end

          # Mode from model type if available
          if model_info.respond_to?(:type)
            result[:mode] = model_info.type.to_s
          end

          (result.keys.size > 1) ? result : nil
        end
      end
    end
  end
end
