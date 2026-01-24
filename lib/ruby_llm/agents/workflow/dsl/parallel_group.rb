# frozen_string_literal: true

module RubyLLM
  module Agents
    class Workflow
      module DSL
        # Represents a group of steps that execute in parallel
        #
        # Parallel groups allow multiple steps to run concurrently and
        # their results to be available to subsequent steps.
        #
        # @example Basic parallel group
        #   parallel do
        #     step :sentiment, SentimentAgent
        #     step :keywords, KeywordAgent
        #     step :entities, EntityAgent
        #   end
        #
        # @example Named parallel group
        #   parallel :analysis do
        #     step :sentiment, SentimentAgent
        #     step :keywords, KeywordAgent
        #   end
        #
        #   step :combine, CombinerAgent,
        #        input: -> { { analysis: analysis } }
        #
        # @api private
        class ParallelGroup
          attr_reader :name, :step_names, :options

          # @param name [Symbol, nil] Optional name for the group
          # @param step_names [Array<Symbol>] Names of steps in the group
          # @param options [Hash] Group options
          def initialize(name: nil, step_names: [], options: {})
            @name = name
            @step_names = step_names
            @options = options
          end

          # Adds a step to the group
          #
          # @param step_name [Symbol]
          # @return [void]
          def add_step(step_name)
            @step_names << step_name
          end

          # Returns the number of steps in the group
          #
          # @return [Integer]
          def size
            @step_names.size
          end

          # Returns whether the group is empty
          #
          # @return [Boolean]
          def empty?
            @step_names.empty?
          end

          # Returns the fail-fast setting for this group
          #
          # @return [Boolean]
          def fail_fast?
            options[:fail_fast] == true
          end

          # Returns the concurrency limit for this group
          #
          # @return [Integer, nil]
          def concurrency
            options[:concurrency]
          end

          # Returns the timeout for the entire group
          #
          # @return [Integer, nil]
          def timeout
            options[:timeout]
          end

          # Converts to hash for serialization
          #
          # @return [Hash]
          def to_h
            {
              name: name,
              step_names: step_names,
              fail_fast: fail_fast?,
              concurrency: concurrency,
              timeout: timeout
            }.compact
          end

          # String representation
          #
          # @return [String]
          def inspect
            "#<ParallelGroup name=#{name.inspect} steps=#{step_names.inspect}>"
          end
        end
      end
    end
  end
end
