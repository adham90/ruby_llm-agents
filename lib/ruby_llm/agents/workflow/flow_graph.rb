# frozen_string_literal: true

module RubyLLM
  module Agents
    class Workflow
      # DAG (Directed Acyclic Graph) of workflow steps
      #
      # Builds a dependency graph from step definitions and flow declarations,
      # then produces execution layers via Kahn's topological sort.
      # Each layer contains steps that can run concurrently.
      #
      # @example
      #   graph = FlowGraph.new(steps)
      #   graph.execution_layers
      #   # => [[:research], [:draft, :outline], [:edit]]
      #
      class FlowGraph
        attr_reader :steps

        # @param steps [Array<Step>] All defined steps
        def initialize(steps)
          @steps = steps
          @step_map = steps.each_with_object({}) { |s, h| h[s.name] = s }
          validate!
        end

        # Compute execution layers using topological sort
        #
        # Steps with no unmet dependencies form a layer.
        # Within each layer, steps can potentially run in parallel.
        #
        # @return [Array<Array<Symbol>>] Layers of step names
        def execution_layers
          return [] if @steps.empty?

          # Build adjacency and in-degree
          in_degree = {}
          adjacency = {}

          @steps.each do |step|
            in_degree[step.name] ||= 0
            adjacency[step.name] ||= []
          end

          @steps.each do |step|
            step.after_steps.each do |dep|
              adjacency[dep] ||= []
              adjacency[dep] << step.name
              in_degree[step.name] += 1
            end
          end

          # Kahn's algorithm — group by layers
          layers = []
          queue = in_degree.select { |_, d| d == 0 }.keys

          until queue.empty?
            layers << queue.sort # deterministic order within layer
            next_queue = []

            queue.each do |name|
              adjacency[name].each do |dependent|
                in_degree[dependent] -= 1
                next_queue << dependent if in_degree[dependent] == 0
              end
            end

            queue = next_queue
          end

          sorted_count = layers.sum(&:size)
          if sorted_count != @steps.size
            raise CyclicDependencyError, "Workflow has circular dependencies"
          end

          layers
        end

        # Look up a step by name
        #
        # @param name [Symbol]
        # @return [Step, nil]
        def step(name)
          @step_map[name.to_sym]
        end

        private

        def validate!
          names = @steps.map(&:name)

          # Check for duplicate names
          dupes = names.group_by(&:itself).select { |_, v| v.size > 1 }.keys
          unless dupes.empty?
            raise ArgumentError, "Duplicate step names: #{dupes.join(", ")}"
          end

          # Check that after_steps reference valid step names
          @steps.each do |step|
            step.after_steps.each do |dep|
              unless names.include?(dep)
                raise ArgumentError, "Step :#{step.name} depends on unknown step :#{dep}"
              end
            end
          end
        end
      end

      # Raised when the workflow graph has circular dependencies
      class CyclicDependencyError < StandardError; end
    end
  end
end
