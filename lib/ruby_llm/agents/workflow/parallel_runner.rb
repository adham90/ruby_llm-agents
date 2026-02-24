# frozen_string_literal: true

module RubyLLM
  module Agents
    class Workflow
      # Extends Runner with parallel execution for multi-step layers
      #
      # When a layer contains multiple steps, they run concurrently
      # using Thread.new. Uses the WorkflowContext's Mutex for
      # thread-safe result storage.
      #
      # No external gem dependency — Ruby's Thread is sufficient
      # for I/O-bound LLM API calls.
      #
      class ParallelRunner < Runner
        private

        def parallel_enabled?
          true
        end

        def execute_parallel(layer)
          threads = layer.map do |step_name|
            Thread.new(step_name) { |name| execute_step(name) }
          end

          # Wait for all threads to complete, collecting any unhandled errors
          threads.each do |thread|
            thread.join
          rescue => e
            # Thread errors are already captured via execute_step's rescue,
            # but re-raise truly unexpected errors
            raise e unless e.is_a?(StandardError)
          end
        end
      end
    end
  end
end
