# frozen_string_literal: true

module RubyLLM
  module Agents
    class Workflow
      module DSL
        # Builder for defining routing options in a step
        #
        # Used with the `on:` option to route to different agents based on
        # a runtime value. Supports a fluent interface for defining routes.
        #
        # @example Basic routing
        #   step :process, on: -> { enrich.tier } do |route|
        #     route.premium  PremiumAgent
        #     route.standard StandardAgent
        #     route.default  DefaultAgent
        #   end
        #
        # @example With per-route options
        #   step :process, on: -> { enrich.tier } do |route|
        #     route.premium  PremiumAgent, input: -> { { vip: true } }, timeout: 5.minutes
        #     route.standard StandardAgent
        #     route.default  DefaultAgent
        #   end
        #
        # @api private
        class RouteBuilder
          # Error raised when no route matches and no default is defined
          class NoRouteError < StandardError
            attr_reader :value, :available_routes

            def initialize(message, value: nil, available_routes: [])
              super(message)
              @value = value
              @available_routes = available_routes
            end
          end

          def initialize
            @routes = {}
            @default = nil
          end

          # Returns all defined routes
          #
          # @return [Hash<Symbol, Hash>]
          attr_reader :routes

          # Returns or sets the default route
          #
          # When called with no arguments, returns the current default.
          # When called with an agent, sets the default route.
          #
          # @param agent [Class, nil] Agent class for the default route
          # @param options [Hash] Route options
          # @return [Hash, nil]
          def default(agent = nil, **options)
            if agent.nil? && options.empty?
              @default
            else
              @default = { agent: agent, options: options }
            end
          end

          # Handles dynamic route definitions
          #
          # Any method call becomes a route definition.
          #
          # @param name [Symbol] Route name
          # @param agent [Class] Agent class for this route
          # @param options [Hash] Route options
          # @return [void]
          def method_missing(name, agent = nil, **options)
            if name == :default
              @default = { agent: agent, options: options }
            else
              @routes[name.to_sym] = { agent: agent, options: options }
            end
          end

          def respond_to_missing?(name, include_private = false)
            true
          end

          # Resolves the route for a given value
          #
          # @param value [Object] The routing key value
          # @return [Hash] Route configuration with :agent and :options
          # @raise [NoRouteError] If no route matches and no default is defined
          def resolve(value)
            key = normalize_key(value)

            route = @routes[key] || @default

            unless route
              raise NoRouteError.new(
                "No route defined for value: #{value.inspect} (normalized: #{key}). " \
                "Available routes: #{@routes.keys.join(', ')}",
                value: value,
                available_routes: @routes.keys
              )
            end

            route
          end

          # Returns all route names
          #
          # @return [Array<Symbol>]
          def route_names
            @routes.keys
          end

          # Checks if a route exists
          #
          # @param name [Symbol] Route name
          # @return [Boolean]
          def route_exists?(name)
            @routes.key?(name.to_sym) || @default.present?
          end

          # Converts to hash for serialization
          #
          # @return [Hash]
          def to_h
            {
              routes: @routes.transform_values do |r|
                { agent: r[:agent]&.name, options: r[:options] }
              end,
              default: @default ? { agent: @default[:agent]&.name, options: @default[:options] } : nil
            }
          end

          private

          def normalize_key(value)
            case value
            when Symbol then value
            when String then value.to_sym
            when TrueClass then :true
            when FalseClass then :false
            when NilClass then :nil
            else value.to_s.to_sym
            end
          end
        end
      end
    end
  end
end
