# frozen_string_literal: true

module RubyLLM
  module Agents
    class Workflow
      # Conditional routing workflow pattern
      #
      # Classifies input and routes to the appropriate specialized agent.
      # Uses a fast, cheap model for classification by default, then
      # delegates to the selected route's agent.
      #
      # @example Basic router
      #   class SupportRouter < RubyLLM::Agents::Workflow::Router
      #     version "1.0"
      #
      #     classifier_model "gpt-4o-mini"
      #
      #     route :billing,   to: BillingAgent,   description: "Billing, charges, refunds"
      #     route :technical, to: TechSupportAgent, description: "Bugs, errors, crashes"
      #     route :sales,     to: SalesAgent,     description: "Pricing, plans, upgrades"
      #     route :default,   to: GeneralAgent    # Fallback
      #   end
      #
      #   result = SupportRouter.call(message: "I was charged twice")
      #   result.routed_to           # :billing
      #   result.classification_cost # Cost of classifier
      #   result.content             # BillingAgent's response
      #
      # @example With custom classification
      #   class CustomRouter < RubyLLM::Agents::Workflow::Router
      #     route :fast, to: FastAgent, description: "Quick tasks"
      #     route :slow, to: SlowAgent, description: "Complex tasks"
      #
      #     def classify(input)
      #       # Custom classification logic
      #       input[:message].length > 100 ? :slow : :fast
      #     end
      #   end
      #
      # @example With input transformation
      #   class TransformRouter < RubyLLM::Agents::Workflow::Router
      #     route :analyze, to: AnalyzerAgent, description: "Analysis requests"
      #
      #     def before_route(input, chosen_route)
      #       input.merge(route_context: chosen_route, priority: "high")
      #     end
      #   end
      #
      # @api public
      class Router < Workflow
        class << self
          # Returns the defined routes
          #
          # @return [Hash<Symbol, Hash>] Route configurations
          def routes
            @routes ||= {}
          end

          # Inherits routes from parent class
          def inherited(subclass)
            super
            subclass.instance_variable_set(:@routes, routes.dup)
            subclass.instance_variable_set(:@classifier_model, @classifier_model)
            subclass.instance_variable_set(:@classifier_temperature, @classifier_temperature)
          end

          # Defines a route
          #
          # @param name [Symbol] Route identifier
          # @param to [Class] The agent class to route to
          # @param description [String, nil] Description for LLM classification
          # @param match [Proc, nil] Lambda for rule-based matching (bypasses LLM)
          # @return [void]
          #
          # @example Basic route
          #   route :billing, to: BillingAgent, description: "Billing and payment issues"
          #
          # @example Default/fallback route
          #   route :default, to: GeneralAgent
          #
          # @example With rule-based matching
          #   route :urgent, to: UrgentAgent, match: ->(input) { input[:priority] == "urgent" }
          def route(name, to:, description: nil, match: nil)
            routes[name] = {
              agent: to,
              description: description,
              match: match
            }
          end

          # Sets or returns the classifier model
          #
          # @param value [String, nil] Model ID
          # @return [String] The classifier model
          def classifier_model(value = nil)
            if value
              @classifier_model = value
            else
              @classifier_model || RubyLLM::Agents.configuration.default_model || "gpt-4o-mini"
            end
          end

          # Sets or returns the classifier temperature
          #
          # @param value [Float, nil] Temperature (0.0-2.0)
          # @return [Float] The classifier temperature
          def classifier_temperature(value = nil)
            if value
              @classifier_temperature = value
            else
              @classifier_temperature || 0.0
            end
          end
        end

        # Executes the router workflow
        #
        # Classifies input and routes to the appropriate agent.
        #
        # @yield [chunk] Yields chunks when streaming (passed to routed agent)
        # @return [WorkflowResult] The router result
        def call(&block)
          instrument_workflow do
            execute_router(&block)
          end
        end

        # Override to provide custom classification logic
        #
        # @param input [Hash] The input to classify
        # @return [Symbol] The route name to use
        def classify(input)
          # First, try rule-based matching
          rule_match = try_rule_matching(input)
          return rule_match if rule_match

          # Fall back to LLM classification
          llm_classify(input)
        end

        protected

        # Hook to transform input before routing
        #
        # @param input [Hash] Original input
        # @param chosen_route [Symbol] The selected route
        # @return [Hash] Transformed input for the routed agent
        def before_route(input, chosen_route)
          input
        end

        private

        # Executes the router logic
        #
        # @return [WorkflowResult] The router result
        def execute_router(&block)
          # Classify the input
          classification_start = Time.current
          chosen_route, classifier_result = perform_classification(options)
          classification_time = ((Time.current - classification_start) * 1000).round

          # Validate route exists
          route_config = self.class.routes[chosen_route]
          unless route_config
            # Fall back to default route
            chosen_route = :default
            route_config = self.class.routes[:default]

            unless route_config
              raise RouterError, "Route '#{chosen_route}' not found and no default route defined"
            end
          end

          # Transform input for the routed agent
          routed_input = before_route(options, chosen_route)

          # Execute the routed agent
          agent_result = execute_agent(
            route_config[:agent],
            routed_input,
            step_name: chosen_route,
            &block
          )

          build_router_result(
            content: agent_result.content,
            routed_to: chosen_route,
            routed_result: agent_result,
            classifier_result: classifier_result,
            classification_time_ms: classification_time
          )
        rescue RouterError
          # Re-raise configuration errors
          raise
        rescue StandardError => e
          build_router_result(
            content: nil,
            routed_to: nil,
            classifier_result: classifier_result,
            error: e,
            status: "error"
          )
        end

        # Performs classification and returns route + classifier result
        #
        # @param input [Hash] Input to classify
        # @return [Array<Symbol, Result>] Route name and classifier result
        def perform_classification(input)
          # Check if subclass overrides classify completely
          if self.class.instance_method(:classify).owner != Router
            # Custom classify method - no classifier_result
            route = classify(input)
            [route, nil]
          else
            classify_with_result(input)
          end
        end

        # Classifies input and returns both route and result
        #
        # @param input [Hash] Input to classify
        # @return [Array<Symbol, Result>] Route name and classifier result
        def classify_with_result(input)
          # First, try rule-based matching
          rule_match = try_rule_matching(input)
          return [rule_match, nil] if rule_match

          # Fall back to LLM classification
          result = llm_classify_with_result(input)
          route = parse_classification(result.content)
          [route, result]
        end

        # Tries rule-based matching before LLM classification
        #
        # @param input [Hash] Input to match
        # @return [Symbol, nil] Matched route or nil
        def try_rule_matching(input)
          self.class.routes.each do |name, config|
            next unless config[:match]
            next if name == :default

            begin
              return name if config[:match].call(input)
            rescue StandardError => e
              Rails.logger.warn("[RubyLLM::Agents::Router] Match rule for #{name} failed: #{e.message}")
            end
          end
          nil
        end

        # Classifies input using LLM (returns only route)
        #
        # @param input [Hash] Input to classify
        # @return [Symbol] The classified route
        def llm_classify(input)
          result = llm_classify_with_result(input)
          parse_classification(result.content)
        end

        # Classifies input using LLM and returns full result
        #
        # @param input [Hash] Input to classify
        # @return [Result] The classifier result
        def llm_classify_with_result(input)
          prompt = build_classifier_prompt(input)

          # Use RubyLLM directly for classification
          client = RubyLLM.chat
            .with_model(self.class.classifier_model)
            .with_temperature(self.class.classifier_temperature)

          response = client.ask(prompt)

          # Build a simple result for tracking
          build_classifier_result(response)
        end

        # Builds the classification prompt
        #
        # @param input [Hash] Input to classify
        # @return [String] The classification prompt
        def build_classifier_prompt(input)
          routes_with_descriptions = self.class.routes
            .reject { |name, _| name == :default }
            .select { |_, config| config[:description] }

          if routes_with_descriptions.empty?
            raise RouterError, "No routes with descriptions defined. Add descriptions or override #classify"
          end

          routes_desc = routes_with_descriptions.map do |name, config|
            "- #{name}: #{config[:description]}"
          end.join("\n")

          # Extract the main content to classify
          content = extract_classifiable_content(input)

          <<~PROMPT
            Classify the following input into exactly one category.

            Categories:
            #{routes_desc}

            Input: #{content}

            Respond with ONLY the category name, nothing else. The response must be exactly one of: #{routes_with_descriptions.keys.join(', ')}
          PROMPT
        end

        # Extracts the main content from input for classification
        #
        # @param input [Hash] The input
        # @return [String] Content to classify
        def extract_classifiable_content(input)
          # Try common keys
          %i[message text content query input prompt].each do |key|
            return input[key].to_s if input[key].present?
          end

          # Fall back to first string value or serialized input
          input.values.find { |v| v.is_a?(String) && v.present? } || input.to_json
        end

        # Parses the LLM classification response
        #
        # @param content [String] The LLM response
        # @return [Symbol] The parsed route name
        def parse_classification(content)
          return :default unless content

          # Clean up response
          cleaned = content.to_s.strip.downcase.gsub(/[^a-z0-9_]/, "")

          # Find matching route
          self.class.routes.keys.find { |name| name.to_s == cleaned } || :default
        end

        # Builds a result object for the classifier
        #
        # @param response [RubyLLM::Message] The LLM response
        # @return [Result] Simple result for tracking
        def build_classifier_result(response)
          RubyLLM::Agents::Result.new(
            content: response.content,
            input_tokens: response.input_tokens,
            output_tokens: response.output_tokens,
            total_cost: calculate_classifier_cost(response),
            model_id: self.class.classifier_model,
            temperature: self.class.classifier_temperature
          )
        end

        # Calculates classifier cost
        #
        # @param response [RubyLLM::Message] The LLM response
        # @return [Float] Cost in USD
        def calculate_classifier_cost(response)
          model_info, _provider = RubyLLM::Models.resolve(self.class.classifier_model)
          return 0.0 unless model_info&.pricing

          input_price = model_info.pricing.text_tokens&.input || 0
          output_price = model_info.pricing.text_tokens&.output || 0

          input_cost = ((response.input_tokens || 0) / 1_000_000.0) * input_price
          output_cost = ((response.output_tokens || 0) / 1_000_000.0) * output_price

          input_cost + output_cost
        rescue StandardError
          0.0
        end

        # Builds the final router result
        #
        # @param content [Object] Final content
        # @param routed_to [Symbol] The selected route
        # @param routed_result [Result, nil] The routed agent's result
        # @param classifier_result [Result, nil] The classifier result
        # @param classification_time_ms [Integer, nil] Classification time
        # @param error [Exception, nil] Error if failed
        # @param status [String] Final status
        # @return [WorkflowResult] The router result
        def build_router_result(content:, routed_to:, routed_result: nil, classifier_result: nil,
                                classification_time_ms: nil, error: nil, status: nil)
          # Build branches hash with routed result
          branches = {}
          branches[routed_to] = routed_result if routed_to && routed_result

          # Build classification info
          classification = {
            route: routed_to,
            classifier_model: self.class.classifier_model,
            classification_time_ms: classification_time_ms,
            method: classifier_result ? "llm" : "rule"
          }

          final_status = status || (error ? "error" : "success")

          result = Workflow::Result.new(
            content: content,
            workflow_type: self.class.name,
            workflow_id: workflow_id,
            routed_to: routed_to,
            classification: classification,
            classifier_result: classifier_result,
            branches: branches,
            status: final_status,
            started_at: @workflow_started_at,
            completed_at: Time.current,
            duration_ms: (((Time.current - @workflow_started_at) * 1000).round if @workflow_started_at)
          )

          if error
            result.instance_variable_set(:@error_class, error.class.name)
            result.instance_variable_set(:@error_message, error.message)
            result.instance_variable_set(:@errors, { routing: error })
          end

          result
        end
      end

      # Error raised for router-specific issues
      class RouterError < StandardError; end
    end
  end
end
