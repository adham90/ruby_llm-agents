# frozen_string_literal: true

module RubyLLM
  module Agents
    module Routing
      # Wraps a standard Result with routing-specific accessors.
      #
      # Delegates all standard Result methods (tokens, cost, timing, etc.)
      # to the underlying result, adding only the route-specific interface.
      #
      # @example
      #   result = SupportRouter.call(message: "I was charged twice")
      #   result.route        # => :billing
      #   result.agent_class  # => BillingAgent (if mapped)
      #   result.success?     # => true
      #   result.total_cost   # => 0.0001
      #
      class RoutingResult < Result
        # @return [Symbol] The classified route name
        attr_reader :route

        # @return [Class, nil] The mapped agent class (if defined via `agent:`)
        attr_reader :agent_class

        # @return [String] The raw text response from the LLM
        attr_reader :raw_response

        # Creates a new RoutingResult by wrapping a base Result with route data.
        #
        # @param base_result [Result] The standard Result from BaseAgent execution
        # @param route_data [Hash] Parsed route information
        # @option route_data [Symbol] :route The classified route name
        # @option route_data [Class, nil] :agent_class Mapped agent class
        # @option route_data [String] :raw_response Raw LLM text
        def initialize(base_result:, route_data:)
          super(
            content: route_data,
            input_tokens: base_result.input_tokens,
            output_tokens: base_result.output_tokens,
            input_cost: base_result.input_cost,
            output_cost: base_result.output_cost,
            total_cost: base_result.total_cost,
            model_id: base_result.model_id,
            chosen_model_id: base_result.chosen_model_id,
            temperature: base_result.temperature,
            started_at: base_result.started_at,
            completed_at: base_result.completed_at,
            duration_ms: base_result.duration_ms,
            finish_reason: base_result.finish_reason,
            streaming: base_result.streaming,
            error_class: base_result.error_class,
            error_message: base_result.error_message,
            attempts_count: base_result.attempts_count
          )

          @route = route_data[:route]
          @agent_class = route_data[:agent_class]
          @raw_response = route_data[:raw_response]
        end

        # Converts the result to a hash including routing fields.
        #
        # @return [Hash] All result data plus route, agent_class, raw_response
        def to_h
          super.merge(
            route: route,
            agent_class: agent_class&.name,
            raw_response: raw_response
          )
        end
      end
    end
  end
end
