# frozen_string_literal: true

module RubyLLM
  module Agents
    class Workflow
      # Dispatch configuration for routing-based step dispatch
      #
      # Collects route-to-agent mappings and resolves which agent
      # to call based on a routing step's result.
      #
      # @example DSL usage
      #   dispatch :classify do
      #     on :billing,   agent: BillingAgent
      #     on :technical,  agent: TechAgent
      #     on_default      agent: GeneralAgent
      #   end
      #
      class DispatchBuilder
        attr_reader :router_step, :routes, :default_agent

        # @param router_step [Symbol] The step whose result contains the route
        def initialize(router_step)
          @router_step = router_step.to_sym
          @routes = {}
          @default_agent = nil
        end

        # Map a route to an agent
        #
        # @param route_name [Symbol] The route name from RoutingResult
        # @param agent [Class] The agent class to handle this route
        # @param params [Hash] Extra params to pass to the handler agent
        def on(route_name, agent:, params: {})
          @routes[route_name.to_sym] = {agent: agent, params: params}
        end

        # Set the default handler for unmatched routes
        #
        # @param agent [Class] The fallback agent class
        # @param params [Hash] Extra params to pass
        def on_default(agent:, params: {})
          @default_agent = {agent: agent, params: params}
        end

        # Resolve which agent to call based on the routing result
        #
        # @param route [Symbol] The route name from the routing step
        # @return [Hash, nil] { agent: Class, params: Hash } or nil
        def resolve(route)
          @routes[route.to_sym] || @default_agent
        end
      end
    end
  end
end
