# frozen_string_literal: true

module RubyLLM
  module Agents
    module Routing
      # Class-level DSL for defining routes and classification categories.
      #
      # Extended into any BaseAgent subclass that includes the Routing concern.
      # Provides `route`, `default_route`, and accessor methods for route definitions.
      #
      # @example
      #   class SupportRouter < RubyLLM::Agents::BaseAgent
      #     include RubyLLM::Agents::Routing
      #
      #     route :billing,  "Billing, charges, refunds"
      #     route :technical, "Bugs, errors, crashes"
      #     default_route :general
      #   end
      #
      module ClassMethods
        # Define a classification route.
        #
        # @param name [Symbol] Route identifier
        # @param description [String] What messages belong to this route
        # @param agent [Class, nil] Optional agent class to map to this route
        #
        # @example Simple route
        #   route :billing, "Billing, charges, refunds"
        #
        # @example Route with agent mapping
        #   route :billing, "Billing questions", agent: BillingAgent
        #
        def route(name, description, agent: nil)
          @routes ||= {}
          @routes[name.to_sym] = {
            description: description,
            agent: agent
          }
        end

        # Set the default route for unmatched classifications.
        #
        # @param name [Symbol] Default route name
        # @param agent [Class, nil] Optional default agent class
        #
        def default_route(name, agent: nil)
          @default_route_name = name.to_sym
          @routes ||= {}
          @routes[name.to_sym] ||= {
            description: "Default / general category",
            agent: agent
          }
        end

        # Returns all defined routes (including inherited).
        #
        # @return [Hash{Symbol => Hash}] Route definitions
        def routes
          parent = superclass.respond_to?(:routes) ? superclass.routes : {}
          parent.merge(@routes || {})
        end

        # Returns the default route name (including inherited).
        #
        # @return [Symbol] The default route name
        def default_route_name
          @default_route_name || (superclass.respond_to?(:default_route_name) ? superclass.default_route_name : :general)
        end

        # Returns :router for instrumentation/tracking.
        #
        # @return [Symbol]
        def agent_type
          :router
        end

        # Override call to accept message: as a named param.
        #
        # @param message [String, nil] The message to classify
        # @param kwargs [Hash] Additional options
        # @return [RoutingResult] The classification result
        def call(message: nil, **kwargs, &block)
          if message
            super(**kwargs.merge(message: message), &block)
          else
            super(**kwargs, &block)
          end
        end
      end
    end
  end
end
