# frozen_string_literal: true

module RubyLLM
  module Agents
    class Workflow
      # DSL module for declaring workflow steps and configuration
      #
      # Extended by Workflow subclasses to provide a declarative API
      # for composing agents into pipelines.
      #
      # @example
      #   class ContentWorkflow < RubyLLM::Agents::Workflow
      #     description "Produces edited content"
      #
      #     step :draft, DraftAgent, params: { tone: "formal" }
      #     step :edit,  EditAgent, after: :draft
      #
      #     pass :draft, to: :edit, as: { content: :draft_text }
      #   end
      #
      module DSL
        # Define a workflow step
        #
        # @param name [Symbol] Unique step identifier
        # @param agent_class [Class] Agent class to execute
        # @param params [Hash] Static parameters for the agent
        # @param after [Symbol, Array<Symbol>] Dependency steps
        # @param if [Proc] Conditional execution
        # @param unless [Proc] Conditional skip
        def step(name, agent_class, params: {}, after: [], if: nil, unless: nil)
          @steps ||= []

          if @steps.any? { |s| s.name == name.to_sym }
            raise ArgumentError, "Step :#{name} is already defined"
          end

          @steps << Step.new(
            name,
            agent_class,
            params: params,
            after: Array(after),
            if_condition: binding.local_variable_get(:if),
            unless_condition: binding.local_variable_get(:unless)
          )
        end

        # Declare a sequential flow of steps
        #
        # Creates implicit `after:` dependencies between steps in order.
        # Accepts either a FlowChain (from Symbol#>>) or an array of symbols.
        #
        # @param chain [FlowChain, Array<Symbol>] Ordered step names
        #
        # @example
        #   flow :research >> :draft >> :edit
        #   flow [:research, :draft, :edit]
        #
        def flow(chain)
          names = case chain
          when FlowChain then chain.steps
          when Array then chain.map(&:to_sym)
          else
            raise ArgumentError, "flow expects a FlowChain (a >> b >> c) or Array"
          end

          names.each_cons(2) do |predecessor, successor|
            succ_step = find_step(successor)
            raise ArgumentError, "Unknown step :#{successor} in flow" unless succ_step

            unless succ_step.after_steps.include?(predecessor)
              succ_step.after_steps << predecessor
            end
          end
        end

        # Define output-to-input mapping between steps
        #
        # @param from_step [Symbol] Source step name
        # @param to [Symbol] Target step name
        # @param as [Hash{Symbol => Symbol}] Maps source output keys to target input param names
        #
        # @example
        #   pass :draft, to: :edit, as: { content: :draft_text }
        #   # edit agent receives draft's :draft_text output as :content param
        #
        def pass(from_step, to:, as: {})
          @pass_definitions ||= []
          @pass_definitions << {from: from_step.to_sym, to: to.to_sym, mapping: as}
        end

        # Set or get the workflow description
        #
        # @param value [String, nil]
        # @return [String, nil]
        def description(value = nil)
          if value
            @description = value
          else
            @description || inherited_or_default(:description, nil)
          end
        end

        # Configure failure handling
        #
        # @param strategy [Symbol] :stop (default) or :continue
        def on_failure(strategy = nil)
          if strategy
            unless %i[stop continue].include?(strategy)
              raise ArgumentError, "on_failure must be :stop or :continue"
            end
            @on_failure = strategy
          else
            @on_failure || inherited_or_default(:on_failure, :stop)
          end
        end

        # Set a budget limit for the workflow
        #
        # @param max_cost [Float] Maximum total cost in USD
        def budget(max_cost)
          @budget_limit = max_cost
        end

        # Get the budget limit
        def budget_limit
          @budget_limit || inherited_or_default(:budget_limit, nil)
        end

        # Set tenant context
        def tenant(value = nil)
          if value
            @tenant = value
          else
            @tenant || inherited_or_default(:tenant, nil)
          end
        end

        # Define a dispatch block for routing-based step dispatch
        #
        # Maps route names from a routing step to handler agent classes.
        # After the routing step executes, the matched handler runs as
        # a `:handler` step (or custom name via `as:`).
        #
        # @param router_step [Symbol] The step that produces a RoutingResult
        # @param as [Symbol] Name for the dispatched handler step (default: :handler)
        # @yield [builder] Block to configure route-to-agent mappings
        #
        # @example
        #   dispatch :classify do |d|
        #     d.on :billing,  agent: BillingAgent
        #     d.on :technical, agent: TechAgent
        #     d.on_default     agent: GeneralAgent
        #   end
        #
        def dispatch(router_step, as: :handler, &block)
          @dispatches ||= []
          builder = DispatchBuilder.new(router_step)
          block.call(builder)
          @dispatches << {builder: builder, handler_name: as.to_sym}
        end

        # Get dispatch definitions
        #
        # @return [Array<Hash>]
        def dispatches
          @dispatches ||= []
        end

        # Get all defined steps
        #
        # @return [Array<Step>]
        def steps
          @steps ||= []
        end

        # Get pass definitions
        #
        # @return [Array<Hash>]
        def pass_definitions
          @pass_definitions ||= []
        end

        private

        def find_step(name)
          (@steps || []).find { |s| s.name == name.to_sym }
        end

        def inherited_or_default(attribute, default)
          if superclass.respond_to?(attribute)
            superclass.public_send(attribute)
          else
            default
          end
        end
      end

      # Chain object for flow DSL: flow :a >> :b >> :c
      #
      # Created when Symbol#>> returns a FlowChain, and subsequent
      # >> calls append to the chain.
      class FlowChain
        attr_reader :steps

        def initialize(*steps)
          @steps = steps.map(&:to_sym)
        end

        def >>(other)
          case other
          when Symbol
            @steps << other
            self
          when FlowChain
            @steps.concat(other.steps)
            self
          else
            raise ArgumentError, "Cannot chain #{other.class} into a FlowChain"
          end
        end
      end
    end
  end
end

# Extend Symbol with >> for flow DSL
# Ruby's Symbol does not define >> so this is safe.
unless Symbol.method_defined?(:>>)
  class Symbol
    def >>(other)
      RubyLLM::Agents::Workflow::FlowChain.new(self, other)
    end
  end
end
