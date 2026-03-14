# frozen_string_literal: true

module RubyLLM
  module Agents
    module Routing
      # Wraps a standard Result with routing-specific accessors.
      #
      # When the route has an `agent:` mapping, the router auto-delegates
      # to that agent. The delegated result is available via `delegated_result`,
      # and `content` returns the delegated agent's content.
      #
      # @example Classification only (no agent mapping)
      #   result = SupportRouter.call(message: "I was charged twice")
      #   result.route        # => :billing
      #   result.delegated?   # => false
      #
      # @example Auto-delegation (with agent mapping)
      #   result = SupportRouter.call(message: "I was charged twice")
      #   result.route            # => :billing
      #   result.delegated?       # => true
      #   result.delegated_to     # => BillingAgent
      #   result.content          # => BillingAgent's response content
      #   result.routing_cost     # => cost of classification step
      #   result.total_cost       # => classification + delegation
      #
      class RoutingResult < Result
        # @return [Symbol] The classified route name
        attr_reader :route

        # @return [Class, nil] The mapped agent class (if defined via `agent:`)
        attr_reader :agent_class

        # @return [String] The raw text response from the LLM
        attr_reader :raw_response

        # @return [Result, nil] The result from the delegated agent (if auto-delegated)
        attr_reader :delegated_result

        # Creates a new RoutingResult by wrapping a base Result with route data.
        #
        # @param base_result [Result] The standard Result from BaseAgent execution
        # @param route_data [Hash] Parsed route information
        # @option route_data [Symbol] :route The classified route name
        # @option route_data [Class, nil] :agent_class Mapped agent class
        # @option route_data [String] :raw_response Raw LLM text
        # @option route_data [Result, nil] :delegated_result Result from auto-delegation
        def initialize(base_result:, route_data:)
          @delegated_result = route_data[:delegated_result]
          @routing_cost = base_result.total_cost

          # When delegated, merge costs from both classification and delegation
          total = if @delegated_result
            (base_result.total_cost || 0) + (@delegated_result.respond_to?(:total_cost) ? @delegated_result.total_cost || 0 : 0)
          else
            base_result.total_cost
          end

          # Use delegated content when available
          effective_content = if @delegated_result
            @delegated_result.respond_to?(:content) ? @delegated_result.content : route_data
          else
            route_data
          end

          super(
            content: effective_content,
            input_tokens: base_result.input_tokens,
            output_tokens: base_result.output_tokens,
            input_cost: base_result.input_cost,
            output_cost: base_result.output_cost,
            total_cost: total,
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

        # Whether the router auto-delegated to a mapped agent
        #
        # @return [Boolean]
        def delegated?
          !@delegated_result.nil?
        end

        # The agent class that was auto-invoked (alias for agent_class)
        #
        # @return [Class, nil]
        def delegated_to
          @agent_class if delegated?
        end

        # Cost of the classification step only (excluding delegation)
        #
        # @return [Float]
        def routing_cost
          @routing_cost || 0
        end

        # Converts the result to a hash including routing fields.
        #
        # @return [Hash] All result data plus route, agent_class, raw_response
        def to_h
          super.merge(
            route: route,
            agent_class: agent_class&.name,
            raw_response: raw_response,
            delegated: delegated?
          )
        end
      end
    end
  end
end
