# frozen_string_literal: true

require_relative "routing/class_methods"
require_relative "routing/result"

module RubyLLM
  module Agents
    # Adds classification & routing capabilities to any BaseAgent.
    #
    # Include this module in a BaseAgent subclass to get:
    # - `route` DSL for defining classification categories
    # - `default_route` for fallback classification
    # - Auto-generated system/user prompts from route definitions
    # - Structured output parsing to return a RoutingResult
    #
    # All existing BaseAgent features (caching, reliability, retries,
    # fallback models, instrumentation, multi-tenancy) work unchanged.
    #
    # @example Class-based router
    #   class SupportRouter < RubyLLM::Agents::BaseAgent
    #     include RubyLLM::Agents::Routing
    #
    #     model "gpt-4o-mini"
    #     temperature 0.0
    #
    #     route :billing,  "Billing, charges, refunds"
    #     route :technical, "Bugs, errors, crashes"
    #     default_route :general
    #   end
    #
    #   result = SupportRouter.call(message: "I was charged twice")
    #   result.route  # => :billing
    #
    # @example Inline classification
    #   route = RubyLLM::Agents::Routing.classify(
    #     message: "I was charged twice",
    #     routes: { billing: "Billing issues", technical: "Tech issues" },
    #     default: :general
    #   )
    #   # => :billing
    #
    module Routing
      def self.included(base)
        unless base < BaseAgent
          raise ArgumentError, "#{base} must inherit from RubyLLM::Agents::BaseAgent to include Routing"
        end

        base.extend(ClassMethods)
        base.param(:message, required: false)
      end

      # Classify a message without defining a router class.
      #
      # Creates an anonymous BaseAgent subclass with Routing included,
      # calls it, and returns just the route symbol.
      #
      # @param message [String] The message to classify
      # @param routes [Hash{Symbol => String}] Route names to descriptions
      # @param default [Symbol] Default route (:general)
      # @param model [String] LLM model to use ("gpt-4o-mini")
      # @param options [Hash] Extra options passed to .call
      # @return [Symbol] The classified route name
      def self.classify(message:, routes:, default: :general, model: "gpt-4o-mini", **options)
        router_model = model
        router = Class.new(BaseAgent) do
          include Routing

          self.model router_model
          temperature 0.0

          routes.each do |name, desc|
            route name, desc
          end
          default_route default
        end

        result = router.call(message: message, **options)
        result.route
      end

      # Helper to get the auto-generated system prompt for routing.
      # Use this in custom system_prompt overrides to include route definitions.
      #
      # @return [String] The auto-generated routing system prompt
      def routing_system_prompt
        default = self.class.default_route_name

        <<~PROMPT.strip
          You are a message classifier. Classify the user's message into exactly one of the following categories:

          #{routing_categories_text}

          If none of the categories clearly match, classify as: #{default}

          Respond with ONLY the category name, nothing else.
        PROMPT
      end

      # Helper to get formatted route categories for use in custom prompts.
      #
      # @return [String] Formatted list of route categories
      def routing_categories_text
        self.class.routes.map do |name, config|
          "- #{name}: #{config[:description]}"
        end.join("\n")
      end

      # Auto-generated system_prompt (used if subclass doesn't override).
      def system_prompt
        super || routing_system_prompt
      end

      # Auto-generated user_prompt from the :message param.
      def user_prompt
        @ask_message || options[:message] || super
      end

      # Override call to capture the caller's stream block so it can be
      # forwarded to the delegated agent. Without this, chunks from the
      # delegated agent are swallowed because build_result has no access
      # to the original block.
      def call(&block)
        @delegation_stream_block = block
        super
      end

      # Override process_response to parse the route from LLM output.
      def process_response(response)
        raw = response.content.to_s.strip.downcase.gsub(/[^a-z0-9_]/, "")
        route_name = raw.to_sym

        valid_routes = self.class.routes.keys
        route_name = self.class.default_route_name unless valid_routes.include?(route_name)

        {
          route: route_name,
          agent_class: self.class.routes.dig(route_name, :agent),
          raw_response: response.content.to_s.strip
        }
      end

      # Override build_result to return a RoutingResult.
      # Auto-delegates to the mapped agent when the route has an `agent:` mapping,
      # unless the caller opts out with `auto_delegate: false`.
      def build_result(content, response, context)
        base = super

        agent_class = content[:agent_class]
        if agent_class && auto_delegate?
          content[:delegated_result] = if @delegation_stream_block
            agent_class.call(**delegation_params, &@delegation_stream_block)
          else
            agent_class.call(**delegation_params)
          end
        end

        RoutingResult.new(base_result: base, route_data: content)
      end

      # Whether auto-delegation to the mapped agent is enabled for this call.
      # Defaults to true. Pass `auto_delegate: false` to receive a
      # classification-only RoutingResult with `delegated? == false` and
      # `agent_class` set so the caller can invoke it manually.
      #
      # @return [Boolean]
      def auto_delegate?
        @options.fetch(:auto_delegate, true)
      end

      # Builds params to forward to the delegated agent.
      # Forwards original message and custom params, excludes routing internals.
      #
      # @return [Hash] Params for the delegated agent
      def delegation_params
        forward = @options.except(:dry_run, :skip_cache, :debug, :stream_events, :auto_delegate)
        forward[:_parent_execution_id] = @parent_execution_id if @parent_execution_id
        forward[:_root_execution_id] = @root_execution_id if @root_execution_id
        forward
      end
    end
  end
end
