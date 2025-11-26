# frozen_string_literal: true

module RubyLLM
  module Agents
    class Execution
      # Metrics concern for cost calculations and performance metrics
      #
      # Provides instance methods for calculating costs from token usage,
      # formatting durations, and computing performance metrics.
      #
      # @see RubyLLM::Agents::Execution::Analytics
      # @api public
      module Metrics
        extend ActiveSupport::Concern

        # Calculates and sets input/output costs from token usage
        #
        # Uses RubyLLM's built-in pricing data to calculate costs.
        # Sets input_cost and output_cost attributes (total_cost is calculated by callback).
        #
        # @param model_info [RubyLLM::Model, nil] Optional pre-resolved model info
        # @return [void]
        # @note Requires input_tokens and output_tokens to be set
        def calculate_costs!(model_info = nil)
          return unless input_tokens && output_tokens

          model_info ||= resolve_model_info
          return unless model_info

          # Get pricing from RubyLLM (prices per million tokens in dollars)
          input_price_per_million = model_info.pricing&.text_tokens&.input || 0
          output_price_per_million = model_info.pricing&.text_tokens&.output || 0

          # Calculate costs in dollars (with 6 decimal precision for micro-dollars)
          self.input_cost = ((input_tokens / 1_000_000.0) * input_price_per_million).round(6)
          self.output_cost = ((output_tokens / 1_000_000.0) * output_price_per_million).round(6)
        end

        # Returns execution duration in seconds
        #
        # @return [Float, nil] Duration in seconds with 2 decimal places, or nil
        def duration_seconds
          duration_ms ? (duration_ms / 1000.0).round(2) : nil
        end

        # Calculates throughput as tokens processed per second
        #
        # @return [Float, nil] Tokens per second, or nil if data unavailable
        def tokens_per_second
          return nil unless duration_ms && duration_ms > 0 && total_tokens
          (total_tokens / duration_seconds.to_f).round(2)
        end

        # Calculates cost efficiency as cost per 1,000 tokens
        #
        # Useful for comparing cost efficiency across different models.
        #
        # @return [Float, nil] Cost per 1K tokens in USD, or nil if data unavailable
        def cost_per_1k_tokens
          return nil unless total_tokens && total_tokens > 0 && total_cost
          (total_cost / total_tokens.to_f * 1000).round(6)
        end

        # @!group Cost Display Helpers

        # Returns input_cost formatted as currency
        #
        # @return [String, nil] Formatted cost (e.g., "$0.000045") or nil
        def formatted_input_cost
          format_cost(input_cost)
        end

        # Returns output_cost formatted as currency
        #
        # @return [String, nil] Formatted cost (e.g., "$0.000045") or nil
        def formatted_output_cost
          format_cost(output_cost)
        end

        # Returns total_cost formatted as currency
        #
        # @return [String, nil] Formatted cost (e.g., "$0.000045") or nil
        def formatted_total_cost
          format_cost(total_cost)
        end

        # @!endgroup

        private

        # Resolves model info from RubyLLM for pricing lookup
        #
        # @return [RubyLLM::Model, nil] Model info or nil if not found
        def resolve_model_info
          return nil unless model_id

          model, _provider = RubyLLM::Models.resolve(model_id)
          model
        rescue RubyLLM::ModelNotFoundError
          Rails.logger.warn("[RubyLLM::Agents] Model not found for pricing: #{model_id}")
          nil
        end

        # Formats a cost value as currency string
        #
        # @param cost [Float, nil] Cost in USD
        # @return [String, nil] Formatted string or nil
        def format_cost(cost)
          return nil unless cost
          format("$%.6f", cost)
        end
      end
    end
  end
end
