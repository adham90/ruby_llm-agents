# frozen_string_literal: true

module RubyLLM
  module Agents
    class Execution
      # Metrics concern for cost calculations and performance metrics
      #
      # Provides methods for:
      # - Calculating costs from token usage via RubyLLM pricing
      # - Human-readable duration formatting
      # - Performance metrics (tokens/second, cost per 1K tokens)
      # - Formatted cost display helpers
      #
      module Metrics
        extend ActiveSupport::Concern

        # Calculate costs from token usage and model pricing
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

        # Human-readable duration
        def duration_seconds
          duration_ms ? (duration_ms / 1000.0).round(2) : nil
        end

        # Tokens per second
        def tokens_per_second
          return nil unless duration_ms && duration_ms > 0 && total_tokens
          (total_tokens / duration_seconds.to_f).round(2)
        end

        # Cost per 1K tokens (for comparison, in dollars)
        def cost_per_1k_tokens
          return nil unless total_tokens && total_tokens > 0 && total_cost
          (total_cost / total_tokens.to_f * 1000).round(6)
        end

        # ==============================================================================
        # Cost Display Helpers
        # ==============================================================================
        #
        # Format cost as currency string
        # Example: format_cost(0.000045) => "$0.000045"
        #

        def formatted_input_cost
          format_cost(input_cost)
        end

        def formatted_output_cost
          format_cost(output_cost)
        end

        def formatted_total_cost
          format_cost(total_cost)
        end

        private

        def resolve_model_info
          return nil unless model_id

          model, _provider = RubyLLM::Models.resolve(model_id)
          model
        rescue RubyLLM::ModelNotFoundError
          Rails.logger.warn("[RubyLLM::Agents] Model not found for pricing: #{model_id}")
          nil
        end

        def format_cost(cost)
          return nil unless cost
          format("$%.6f", cost)
        end
      end
    end
  end
end
