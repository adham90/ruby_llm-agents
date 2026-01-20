# frozen_string_literal: true

module RubyLLM
  module Agents
    # Async/Fiber support for concurrent agent execution
    #
    # Provides utilities for running agents concurrently using Ruby's Fiber scheduler.
    # When used inside an `Async` block, RubyLLM automatically becomes non-blocking
    # because it uses `Net::HTTP` which cooperates with Ruby's fiber scheduler.
    #
    # @example Basic concurrent execution
    #   require 'async'
    #
    #   Async do
    #     results = RubyLLM::Agents::Async.batch([
    #       [SentimentAgent, { input: "I love this!" }],
    #       [SummaryAgent, { input: "Long text..." }],
    #       [CategoryAgent, { input: "Product review" }]
    #     ])
    #   end
    #
    # @example With rate limiting
    #   Async do
    #     results = RubyLLM::Agents::Async.batch(
    #       items.map { |item| [ProcessorAgent, { input: item }] },
    #       max_concurrent: 5
    #     )
    #   end
    #
    # @example Streaming multiple agents
    #   Async do
    #     RubyLLM::Agents::Async.each([AgentA, AgentB]) do |agent|
    #       agent.call(input: data) { |chunk| stream_chunk(chunk) }
    #     end
    #   end
    #
    # @see https://rubyllm.com/async/ RubyLLM Async Documentation
    # @api public
    module Async
      class << self
        # Executes multiple agents concurrently with optional rate limiting
        #
        # @param agents_with_params [Array<Array(Class, Hash)>] Array of [AgentClass, params] pairs
        # @param max_concurrent [Integer, nil] Maximum concurrent executions (nil = use config default)
        # @yield [result, index] Optional block called for each completed result
        # @return [Array<Object>] Results in the same order as input
        #
        # @example Basic batch
        #   results = RubyLLM::Agents::Async.batch([
        #     [AgentA, { input: "text1" }],
        #     [AgentB, { input: "text2" }]
        #   ])
        #
        # @example With progress callback
        #   RubyLLM::Agents::Async.batch(agents_with_params) do |result, index|
        #     puts "Completed #{index + 1}/#{agents_with_params.size}"
        #   end
        def batch(agents_with_params, max_concurrent: nil, &block)
          ensure_async_available!

          max_concurrent ||= RubyLLM::Agents.configuration.async_max_concurrency
          semaphore = ::Async::Semaphore.new(max_concurrent)

          ::Async do
            agents_with_params.each_with_index.map do |(agent_class, params), index|
              ::Async do
                result = semaphore.acquire do
                  agent_class.call(**(params || {}))
                end
                yield(result, index) if block
                result
              end
            end.map(&:wait)
          end.wait
        end

        # Executes a block for each item concurrently
        #
        # @param items [Array] Items to process
        # @param max_concurrent [Integer, nil] Maximum concurrent executions
        # @yield [item] Block to execute for each item
        # @return [Array<Object>] Results in the same order as input
        #
        # @example Process items concurrently
        #   RubyLLM::Agents::Async.each(texts, max_concurrent: 10) do |text|
        #     SummaryAgent.call(input: text)
        #   end
        def each(items, max_concurrent: nil, &block)
          ensure_async_available!
          raise ArgumentError, "Block required" unless block

          max_concurrent ||= RubyLLM::Agents.configuration.async_max_concurrency
          semaphore = ::Async::Semaphore.new(max_concurrent)

          ::Async do
            items.map do |item|
              ::Async do
                semaphore.acquire do
                  yield(item)
                end
              end
            end.map(&:wait)
          end.wait
        end

        # Executes multiple agents and returns results as they complete
        #
        # Unlike `batch`, this yields results as soon as they're ready,
        # not in order. Useful for progress updates.
        #
        # @param agents_with_params [Array<Array(Class, Hash)>] Array of [AgentClass, params] pairs
        # @param max_concurrent [Integer, nil] Maximum concurrent executions
        # @yield [result, agent_class, index] Block called as each result completes
        # @return [Hash<Integer, Object>] Results keyed by original index
        #
        # @example Stream results as they complete
        #   RubyLLM::Agents::Async.stream(agents) do |result, agent_class, index|
        #     puts "#{agent_class.name} finished: #{result.content}"
        #   end
        def stream(agents_with_params, max_concurrent: nil, &block)
          ensure_async_available!

          max_concurrent ||= RubyLLM::Agents.configuration.async_max_concurrency
          semaphore = ::Async::Semaphore.new(max_concurrent)
          results = {}
          mutex = Mutex.new

          ::Async do |task|
            agents_with_params.each_with_index.map do |(agent_class, params), index|
              ::Async do
                result = semaphore.acquire do
                  agent_class.call(**(params || {}))
                end

                mutex.synchronize { results[index] = result }
                yield(result, agent_class, index) if block
              end
            end.map(&:wait)
          end.wait

          results
        end

        # Wraps a synchronous agent call in an async task
        #
        # @param agent_class [Class] The agent class to call
        # @param params [Hash] Parameters to pass to the agent
        # @yield [chunk] Optional streaming block
        # @return [Async::Task] The async task (call .wait to get result)
        #
        # @example Fire and forget
        #   task = RubyLLM::Agents::Async.call_async(MyAgent, input: "Hello")
        #   # ... do other work ...
        #   result = task.wait
        def call_async(agent_class, **params, &block)
          ensure_async_available!

          ::Async do
            agent_class.call(**params, &block)
          end
        end

        # Sleeps without blocking other fibers
        #
        # Automatically uses async sleep when in async context,
        # falls back to regular sleep otherwise.
        #
        # @param seconds [Numeric] Duration to sleep
        # @return [void]
        def sleep(seconds)
          if async_context?
            ::Async::Task.current.sleep(seconds)
          else
            Kernel.sleep(seconds)
          end
        end

        # Checks if async gem is available
        #
        # @return [Boolean] true if async gem is loaded
        def available?
          RubyLLM::Agents.configuration.async_available?
        end

        # Checks if currently in an async context
        #
        # @return [Boolean] true if inside an Async block
        def async_context?
          RubyLLM::Agents.configuration.async_context?
        end

        private

        # Raises an error if async gem is not available
        #
        # @raise [RuntimeError] If async gem is not loaded
        def ensure_async_available!
          return if available?

          raise <<~ERROR
            Async gem is required for concurrent agent execution.

            Add to your Gemfile:
              gem 'async'

            Then:
              bundle install

            Usage:
              require 'async'

              Async do
                RubyLLM::Agents::Async.batch([...])
              end
          ERROR
        end
      end
    end
  end
end
