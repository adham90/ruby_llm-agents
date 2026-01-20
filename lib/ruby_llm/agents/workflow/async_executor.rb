# frozen_string_literal: true

module RubyLLM
  module Agents
    class Workflow
      # Fiber-based concurrent executor for parallel workflows
      #
      # Provides an alternative to ThreadPool that uses Ruby's Fiber scheduler
      # for lightweight concurrency. Automatically used when the async gem is
      # available and we're inside an async context.
      #
      # @example Basic usage
      #   executor = AsyncExecutor.new(max_concurrent: 4)
      #   executor.post { perform_task_1 }
      #   executor.post { perform_task_2 }
      #   executor.wait_for_completion
      #
      # @example With fail-fast
      #   executor = AsyncExecutor.new(max_concurrent: 4)
      #   executor.post { risky_task }
      #   executor.abort! if something_failed
      #   executor.wait_for_completion
      #
      # @api private
      class AsyncExecutor
        attr_reader :max_concurrent

        # Creates a new async executor
        #
        # @param max_concurrent [Integer] Maximum concurrent fibers (default: 10)
        def initialize(max_concurrent: 10)
          @max_concurrent = max_concurrent
          @tasks = []
          @results = []
          @mutex = Mutex.new
          @aborted = false
          @semaphore = nil
        end

        # Submits a task for execution
        #
        # @yield Block to execute
        # @return [void]
        def post(&block)
          @mutex.synchronize do
            @tasks << block
          end
        end

        # Signals that remaining tasks should be skipped
        #
        # Currently running tasks will complete, but pending tasks will be skipped.
        #
        # @return [void]
        def abort!
          @mutex.synchronize do
            @aborted = true
          end
        end

        # Returns whether the executor has been aborted
        #
        # @return [Boolean] true if abort! was called
        def aborted?
          @mutex.synchronize { @aborted }
        end

        # Executes all submitted tasks and waits for completion
        #
        # @param timeout [Integer, nil] Maximum seconds to wait (nil = indefinite)
        # @return [Boolean] true if all tasks completed, false if timeout
        def wait_for_completion(timeout: nil)
          return true if @tasks.empty?

          ensure_async_available!

          @semaphore = ::Async::Semaphore.new(@max_concurrent)

          if timeout
            execute_with_timeout(timeout)
          else
            execute_all
            true
          end
        end

        # Shuts down the executor
        #
        # For AsyncExecutor this is a no-op since fibers are garbage collected.
        #
        # @param timeout [Integer] Ignored for async executor
        # @return [void]
        def shutdown(timeout: 5)
          # No-op for fiber-based executor
          # Fibers are lightweight and garbage collected
        end

        # Waits for termination (compatibility with ThreadPool)
        #
        # @param timeout [Integer] Ignored for async executor
        # @return [void]
        def wait_for_termination(timeout: 5)
          # No-op for fiber-based executor
        end

        private

        # Executes all tasks with async
        #
        # @return [void]
        def execute_all
          Kernel.send(:Async) do
            @tasks.map do |task|
              Kernel.send(:Async) do
                next if aborted?

                @semaphore.acquire do
                  next if aborted?
                  task.call
                end
              end
            end.map(&:wait)
          end.wait
        end

        # Executes all tasks with a timeout
        #
        # @param timeout [Integer] Maximum seconds to wait
        # @return [Boolean] true if completed, false if timeout
        def execute_with_timeout(timeout)
          completed = false

          Kernel.send(:Async) do |task|
            task.with_timeout(timeout) do
              execute_all
              completed = true
            rescue ::Async::TimeoutError
              completed = false
            end
          end.wait

          completed
        end

        # Ensures async gem is available
        #
        # @raise [RuntimeError] If async gem is not loaded
        def ensure_async_available!
          return if defined?(::Async) && defined?(::Async::Semaphore)

          raise "AsyncExecutor requires the 'async' gem. Add gem 'async' to your Gemfile."
        end
      end
    end
  end
end
