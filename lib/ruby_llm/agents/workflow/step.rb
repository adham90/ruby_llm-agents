# frozen_string_literal: true

module RubyLLM
  module Agents
    class Workflow
      # Value object representing a single workflow step
      #
      # Each step wraps an agent class with its configuration:
      # name, parameters to pass, and dependency relationships.
      #
      # @example
      #   Step.new(:draft, DraftAgent, params: { tone: "formal" }, after: [:research])
      #
      class Step
        attr_reader :name, :agent_class, :params, :after_steps, :pass_mappings,
          :condition, :unless_condition

        # @param name [Symbol] Unique step identifier
        # @param agent_class [Class] Agent class that responds to .call
        # @param params [Hash] Static parameters to pass to the agent
        # @param after [Array<Symbol>] Steps that must complete before this one
        # @param if_condition [Proc, nil] Only run step when truthy
        # @param unless_condition [Proc, nil] Skip step when truthy
        def initialize(name, agent_class, params: {}, after: [], if_condition: nil, unless_condition: nil)
          @name = name.to_sym
          @agent_class = agent_class
          @params = params
          @after_steps = Array(after).map(&:to_sym)
          @condition = if_condition
          @unless_condition = unless_condition
          @pass_mappings = []

          validate!
        end

        # Check whether the step should execute given the current context
        #
        # @param context [WorkflowContext] The workflow context
        # @return [Boolean]
        def should_run?(context)
          if @condition
            return false unless evaluate_condition(@condition, context)
          end
          if @unless_condition
            return false if evaluate_condition(@unless_condition, context)
          end
          true
        end

        # Add a pass mapping for this step
        #
        # @param mapping [Hash] Maps output keys from a source step to input params
        def add_pass_mapping(mapping)
          @pass_mappings << mapping
        end

        def to_h
          {
            name: @name,
            agent_class: @agent_class.name,
            params: @params,
            after_steps: @after_steps
          }
        end

        private

        def validate!
          raise ArgumentError, "Step name must be a Symbol, got #{@name.class}" unless @name.is_a?(Symbol)
          unless @agent_class.respond_to?(:call)
            raise ArgumentError, "#{@agent_class} must respond to .call"
          end
        end

        def evaluate_condition(condition, context)
          case condition
          when Proc then condition.call(context)
          when Symbol then context[condition]
          else condition
          end
        end
      end
    end
  end
end
