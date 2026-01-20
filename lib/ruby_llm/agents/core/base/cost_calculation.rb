# frozen_string_literal: true

module RubyLLM
  module Agents
    class Base
      # Cost calculation methods for token and pricing calculations
      #
      # Handles input/output cost calculations, model info resolution,
      # and budget tracking for agent executions.
      module CostCalculation
        # Calculates input cost from tokens
        #
        # @param input_tokens [Integer, nil] Number of input tokens
        # @param response_model_id [String, nil] Model that responded
        # @return [Float, nil] Input cost in USD
        def result_input_cost(input_tokens, response_model_id)
          return nil unless input_tokens
          model_info = result_model_info(response_model_id)
          return nil unless model_info&.pricing
          price = model_info.pricing.text_tokens&.input || 0
          (input_tokens / 1_000_000.0 * price).round(6)
        end

        # Calculates output cost from tokens
        #
        # @param output_tokens [Integer, nil] Number of output tokens
        # @param response_model_id [String, nil] Model that responded
        # @return [Float, nil] Output cost in USD
        def result_output_cost(output_tokens, response_model_id)
          return nil unless output_tokens
          model_info = result_model_info(response_model_id)
          return nil unless model_info&.pricing
          price = model_info.pricing.text_tokens&.output || 0
          (output_tokens / 1_000_000.0 * price).round(6)
        end

        # Calculates total cost from tokens
        #
        # @param input_tokens [Integer, nil] Number of input tokens
        # @param output_tokens [Integer, nil] Number of output tokens
        # @param response_model_id [String, nil] Model that responded
        # @return [Float, nil] Total cost in USD
        def result_total_cost(input_tokens, output_tokens, response_model_id)
          input_cost = result_input_cost(input_tokens, response_model_id)
          output_cost = result_output_cost(output_tokens, response_model_id)
          return nil unless input_cost || output_cost
          ((input_cost || 0) + (output_cost || 0)).round(6)
        end

        # Resolves model info for cost calculation
        #
        # @param response_model_id [String, nil] Model ID from response
        # @return [Object, nil] Model info or nil
        def result_model_info(response_model_id)
          lookup_id = response_model_id || model
          return nil unless lookup_id
          model_obj, _provider = RubyLLM::Models.resolve(lookup_id)
          model_obj
        rescue StandardError
          nil
        end

        # Resolves model info for cost calculation (alternate method)
        #
        # @param model_id [String] The model identifier
        # @return [Object, nil] Model info or nil
        def resolve_model_info(model_id)
          model_obj, _provider = RubyLLM::Models.resolve(model_id)
          model_obj
        rescue StandardError
          nil
        end

        # Records cost from an attempt to the budget tracker
        #
        # @param attempt_tracker [AttemptTracker] The attempt tracker
        # @param tenant_id [String, nil] Optional tenant identifier for multi-tenant tracking
        # @return [void]
        def record_attempt_cost(attempt_tracker, tenant_id: nil)
          successful = attempt_tracker.successful_attempt
          return unless successful

          # Calculate cost for this execution
          # Note: Full cost calculation happens in instrumentation, but we
          # record the spend here for budget tracking
          model_info = resolve_model_info(successful[:model_id])
          return unless model_info&.pricing

          input_tokens = successful[:input_tokens] || 0
          output_tokens = successful[:output_tokens] || 0

          input_price = model_info.pricing.text_tokens&.input || 0
          output_price = model_info.pricing.text_tokens&.output || 0

          total_cost = (input_tokens / 1_000_000.0 * input_price) +
                       (output_tokens / 1_000_000.0 * output_price)

          BudgetTracker.record_spend!(self.class.name, total_cost, tenant_id: tenant_id)
        rescue StandardError => e
          Rails.logger.warn("[RubyLLM::Agents] Failed to record budget spend: #{e.message}")
        end
      end
    end
  end
end
