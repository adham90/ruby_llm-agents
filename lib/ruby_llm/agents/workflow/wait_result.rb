# frozen_string_literal: true

module RubyLLM
  module Agents
    class Workflow
      # Result object for wait step execution
      #
      # Encapsulates the outcome of a wait operation including success/failure status,
      # duration waited, and any metadata like approval details.
      #
      # @example Success result
      #   WaitResult.success(:delay, 5.0)
      #
      # @example Timeout result
      #   WaitResult.timeout(:until, 60.0, :fail)
      #
      # @example Approval result
      #   WaitResult.approved("approval-123", "user@example.com", 3600.0)
      #
      # @api private
      class WaitResult
        STATUSES = %i[success timeout approved rejected skipped].freeze

        attr_reader :type, :status, :waited_duration, :metadata

        # @param type [Symbol] Wait type (:delay, :until, :schedule, :approval)
        # @param status [Symbol] Result status (:success, :timeout, :approved, :rejected, :skipped)
        # @param waited_duration [Float, nil] Duration waited in seconds
        # @param metadata [Hash] Additional result metadata
        def initialize(type:, status:, waited_duration: nil, metadata: {})
          @type = type
          @status = status
          @waited_duration = waited_duration
          @metadata = metadata
        end

        # Creates a success result
        #
        # @param type [Symbol] Wait type
        # @param waited_duration [Float] Duration waited
        # @param metadata [Hash] Additional metadata
        # @return [WaitResult]
        def self.success(type, waited_duration, **metadata)
          new(
            type: type,
            status: :success,
            waited_duration: waited_duration,
            metadata: metadata
          )
        end

        # Creates a timeout result
        #
        # @param type [Symbol] Wait type
        # @param waited_duration [Float] Duration waited before timeout
        # @param action_taken [Symbol] Action taken on timeout (:fail, :continue, :skip_next)
        # @param metadata [Hash] Additional metadata
        # @return [WaitResult]
        def self.timeout(type, waited_duration, action_taken, **metadata)
          new(
            type: type,
            status: :timeout,
            waited_duration: waited_duration,
            metadata: metadata.merge(action_taken: action_taken)
          )
        end

        # Creates a skipped result (when condition not met)
        #
        # @param type [Symbol] Wait type
        # @param reason [String, nil] Reason for skipping
        # @return [WaitResult]
        def self.skipped(type, reason: nil)
          new(
            type: type,
            status: :skipped,
            waited_duration: 0,
            metadata: { reason: reason }.compact
          )
        end

        # Creates an approved result for approval waits
        #
        # @param approval_id [String] Approval identifier
        # @param approved_by [String] User who approved
        # @param waited_duration [Float] Duration waited for approval
        # @param metadata [Hash] Additional metadata
        # @return [WaitResult]
        def self.approved(approval_id, approved_by, waited_duration, **metadata)
          new(
            type: :approval,
            status: :approved,
            waited_duration: waited_duration,
            metadata: metadata.merge(
              approval_id: approval_id,
              approved_by: approved_by
            )
          )
        end

        # Creates a rejected result for approval waits
        #
        # @param approval_id [String] Approval identifier
        # @param rejected_by [String] User who rejected
        # @param waited_duration [Float] Duration waited before rejection
        # @param reason [String, nil] Rejection reason
        # @param metadata [Hash] Additional metadata
        # @return [WaitResult]
        def self.rejected(approval_id, rejected_by, waited_duration, reason: nil, **metadata)
          new(
            type: :approval,
            status: :rejected,
            waited_duration: waited_duration,
            metadata: metadata.merge(
              approval_id: approval_id,
              rejected_by: rejected_by,
              reason: reason
            ).compact
          )
        end

        # Returns whether the wait completed successfully
        #
        # @return [Boolean]
        def success?
          status == :success || status == :approved
        end

        # Returns whether the wait timed out
        #
        # @return [Boolean]
        def timeout?
          status == :timeout
        end

        # Returns whether the wait was skipped
        #
        # @return [Boolean]
        def skipped?
          status == :skipped
        end

        # Returns whether an approval was granted
        #
        # @return [Boolean]
        def approved?
          status == :approved
        end

        # Returns whether an approval was rejected
        #
        # @return [Boolean]
        def rejected?
          status == :rejected
        end

        # Returns whether the workflow should continue after this wait
        #
        # @return [Boolean]
        def should_continue?
          success? || skipped? || (timeout? && metadata[:action_taken] == :continue)
        end

        # Returns whether the next step should be skipped
        #
        # @return [Boolean]
        def should_skip_next?
          timeout? && metadata[:action_taken] == :skip_next
        end

        # Returns the action taken on timeout
        #
        # @return [Symbol, nil]
        def timeout_action
          metadata[:action_taken]
        end

        # Returns the approval ID for approval waits
        #
        # @return [String, nil]
        def approval_id
          metadata[:approval_id]
        end

        # Returns who approved/rejected for approval waits
        #
        # @return [String, nil]
        def actor
          metadata[:approved_by] || metadata[:rejected_by]
        end

        # Returns the rejection reason
        #
        # @return [String, nil]
        def rejection_reason
          metadata[:reason]
        end

        # Converts to hash for serialization
        #
        # @return [Hash]
        def to_h
          {
            type: type,
            status: status,
            waited_duration: waited_duration,
            metadata: metadata
          }
        end
      end
    end
  end
end
