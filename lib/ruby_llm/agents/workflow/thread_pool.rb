# frozen_string_literal: true

module RubyLLM
  module Agents
    class Workflow
      # Simple bounded thread pool for parallel workflow execution
      #
      # Provides a fixed-size pool of worker threads that process submitted tasks.
      # Supports fail-fast abort and graceful shutdown.
      #
      # @example Basic usage
      #   pool = ThreadPool.new(size: 4)
      #   pool.post { perform_task_1 }
      #   pool.post { perform_task_2 }
      #   pool.wait_for_completion
      #   pool.shutdown
      #
      # @example With fail-fast
      #   pool = ThreadPool.new(size: 4)
      #   begin
      #     pool.post { risky_task }
      #   rescue => e
      #     pool.abort!  # Signal workers to stop
      #   end
      #   pool.shutdown
      #
      # @api private
      class ThreadPool
        attr_reader :size

        # Creates a new thread pool
        #
        # @param size [Integer] Number of worker threads (default: 4)
        def initialize(size: 4)
          @size = size
          @queue = Queue.new
          @workers = []
          @mutex = Mutex.new
          @completion_condition = ConditionVariable.new
          @pending_count = 0
          @completed_count = 0
          @aborted = false
          @shutdown = false

          spawn_workers
        end

        # Submits a task to the pool
        #
        # @yield Block to execute in a worker thread
        # @return [void]
        # @raise [RuntimeError] If pool has been shutdown
        def post(&block)
          raise "ThreadPool has been shutdown" if @shutdown

          @mutex.synchronize do
            @pending_count += 1
          end

          @queue.push(block)
        end

        # Signals workers to abort remaining tasks
        #
        # Currently running tasks will complete, but pending tasks will be skipped.
        #
        # @return [void]
        def abort!
          @mutex.synchronize do
            @aborted = true
          end
        end

        # Returns whether the pool has been aborted
        #
        # @return [Boolean] true if abort! was called
        def aborted?
          @mutex.synchronize { @aborted }
        end

        # Waits for all submitted tasks to complete
        #
        # @param timeout [Integer, nil] Maximum seconds to wait (nil = indefinite)
        # @return [Boolean] true if all tasks completed, false if timeout
        def wait_for_completion(timeout: nil)
          deadline = timeout ? Time.current + timeout : nil

          @mutex.synchronize do
            loop do
              return true if @pending_count == @completed_count

              if deadline
                remaining = deadline - Time.current
                return false if remaining <= 0

                @completion_condition.wait(@mutex, remaining)
              else
                @completion_condition.wait(@mutex)
              end
            end
          end
        end

        # Shuts down the pool and waits for workers to terminate
        #
        # @param timeout [Integer] Maximum seconds to wait for termination
        # @return [void]
        def shutdown(timeout: 5)
          @shutdown = true

          # Send poison pills to stop workers
          @size.times { @queue.push(nil) }

          wait_for_termination(timeout: timeout)
        end

        # Waits for all worker threads to terminate
        #
        # @param timeout [Integer] Maximum seconds to wait
        # @return [void]
        def wait_for_termination(timeout: 5)
          deadline = Time.current + timeout

          @workers.each do |worker|
            remaining = deadline - Time.current
            break if remaining <= 0

            worker.join(remaining)
          end
        end

        private

        # Spawns the worker threads
        #
        # @return [void]
        def spawn_workers
          @size.times do |i|
            @workers << Thread.new do
              Thread.current.name = "pool-worker-#{i}"
              worker_loop
            end
          end
        end

        # Main worker loop - processes tasks from the queue
        #
        # @return [void]
        def worker_loop
          loop do
            task = @queue.pop

            # nil is the poison pill - time to exit
            break if task.nil?

            # Skip if aborted
            if aborted?
              mark_completed
              next
            end

            begin
              task.call
            rescue StandardError
              # Errors are handled by the task itself (via rescue in the block)
              # We just need to ensure we mark completion
            ensure
              mark_completed
            end
          end
        end

        # Marks a task as completed and signals waiters
        #
        # @return [void]
        def mark_completed
          @mutex.synchronize do
            @completed_count += 1
            @completion_condition.broadcast
          end
        end
      end
    end
  end
end
