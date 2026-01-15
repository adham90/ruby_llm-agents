# frozen_string_literal: true

module RubyLLM
  module Agents
    module Reliability
      # Manages execution constraints like total timeout and budget
      #
      # Tracks elapsed time and enforces timeout limits across
      # all retry and fallback attempts.
      #
      # @example
      #   constraints = ExecutionConstraints.new(total_timeout: 30)
      #   constraints.timeout_exceeded?  # => false
      #   constraints.enforce_timeout!   # raises if exceeded
      #   constraints.elapsed            # => 5.2
      #
      # @api private
      class ExecutionConstraints
        attr_reader :total_timeout, :started_at, :deadline

        # @param total_timeout [Integer, nil] Total timeout in seconds
        def initialize(total_timeout: nil)
          @total_timeout = total_timeout
          @started_at = Time.current
          @deadline = total_timeout ? @started_at + total_timeout : nil
        end

        # Checks if total timeout has been exceeded
        #
        # @return [Boolean] true if past deadline
        def timeout_exceeded?
          deadline && Time.current > deadline
        end

        # Returns elapsed time since start
        #
        # @return [Float] Elapsed seconds
        def elapsed
          Time.current - started_at
        end

        # Raises TotalTimeoutError if timeout exceeded
        #
        # @raise [TotalTimeoutError] If timeout exceeded
        # @return [void]
        def enforce_timeout!
          if timeout_exceeded?
            raise TotalTimeoutError.new(total_timeout, elapsed)
          end
        end

        # Returns remaining time until deadline
        #
        # @return [Float, nil] Remaining seconds or nil if no timeout
        def remaining
          return nil unless deadline
          [deadline - Time.current, 0].max
        end

        # Checks if there's a timeout configured
        #
        # @return [Boolean] true if timeout is set
        def has_timeout?
          total_timeout.present?
        end
      end
    end
  end
end
