# frozen_string_literal: true

require "securerandom"

module RubyLLM
  module Agents
    class Workflow
      # Represents an approval request for human-in-the-loop workflows
      #
      # Tracks the state of an approval including who created it, who can approve it,
      # and the final decision with timestamp and reason.
      #
      # @example Creating an approval
      #   approval = Approval.new(
      #     workflow_id: "order-123",
      #     workflow_type: "OrderApprovalWorkflow",
      #     name: :manager_approval,
      #     metadata: { order_total: 5000 }
      #   )
      #
      # @example Approving
      #   approval.approve!("manager@example.com")
      #
      # @example Rejecting
      #   approval.reject!("manager@example.com", reason: "Budget exceeded")
      #
      # @api public
      class Approval
        STATUSES = %i[pending approved rejected expired].freeze

        attr_reader :id, :workflow_id, :workflow_type, :name, :status,
                    :created_at, :metadata, :approvers, :expires_at
        attr_accessor :approved_by, :approved_at, :rejected_by, :rejected_at,
                      :reason, :reminded_at

        # @param workflow_id [String] The workflow instance ID
        # @param workflow_type [String] The workflow class name
        # @param name [Symbol] The approval point name
        # @param approvers [Array<String>] List of user IDs who can approve
        # @param expires_at [Time, nil] When the approval expires
        # @param metadata [Hash] Additional context for the approval
        def initialize(workflow_id:, workflow_type:, name:, approvers: [], expires_at: nil, metadata: {})
          @id = SecureRandom.uuid
          @workflow_id = workflow_id
          @workflow_type = workflow_type
          @name = name
          @status = :pending
          @approvers = approvers
          @expires_at = expires_at
          @metadata = metadata
          @created_at = Time.now
        end

        # Approve the request
        #
        # @param user_id [String] The user approving
        # @param comment [String, nil] Optional comment
        # @return [void]
        def approve!(user_id, comment: nil)
          raise InvalidStateError, "Cannot approve: status is #{status}" unless pending?

          @status = :approved
          @approved_by = user_id
          @approved_at = Time.now
          @metadata[:approval_comment] = comment if comment
        end

        # Reject the request
        #
        # @param user_id [String] The user rejecting
        # @param reason [String, nil] Reason for rejection
        # @return [void]
        def reject!(user_id, reason: nil)
          raise InvalidStateError, "Cannot reject: status is #{status}" unless pending?

          @status = :rejected
          @rejected_by = user_id
          @rejected_at = Time.now
          @reason = reason
        end

        # Expire the approval request
        #
        # @return [void]
        def expire!
          raise InvalidStateError, "Cannot expire: status is #{status}" unless pending?

          @status = :expired
        end

        # Check if approval is still pending
        #
        # @return [Boolean]
        def pending?
          status == :pending
        end

        # Check if approval was granted
        #
        # @return [Boolean]
        def approved?
          status == :approved
        end

        # Check if approval was rejected
        #
        # @return [Boolean]
        def rejected?
          status == :rejected
        end

        # Check if approval has expired
        #
        # @return [Boolean]
        def expired?
          status == :expired
        end

        # Check if the approval has timed out
        #
        # @return [Boolean]
        def timed_out?
          return false unless expires_at

          Time.now > expires_at && pending?
        end

        # Check if a user can approve this request
        #
        # @param user_id [String] The user to check
        # @return [Boolean]
        def can_approve?(user_id)
          return true if approvers.empty? # Anyone can approve if no restrictions

          approvers.include?(user_id)
        end

        # Duration since creation
        #
        # @return [Float] Seconds since creation
        def age
          Time.now - created_at
        end

        # Duration until expiry
        #
        # @return [Float, nil] Seconds until expiry, nil if no expiry
        def time_until_expiry
          return nil unless expires_at

          expires_at - Time.now
        end

        # Mark that a reminder was sent
        #
        # @return [void]
        def mark_reminded!
          @reminded_at = Time.now
        end

        # Check if a reminder should be sent
        #
        # @param reminder_after [Integer] Seconds after creation to send reminder
        # @param reminder_interval [Integer, nil] Interval between reminders
        # @return [Boolean]
        def should_remind?(reminder_after, reminder_interval: nil)
          return false unless pending?
          return false if age < reminder_after

          if reminded_at && reminder_interval
            Time.now - reminded_at >= reminder_interval
          else
            reminded_at.nil?
          end
        end

        # Convert to hash for serialization
        #
        # @return [Hash]
        def to_h
          {
            id: id,
            workflow_id: workflow_id,
            workflow_type: workflow_type,
            name: name,
            status: status,
            approvers: approvers,
            approved_by: approved_by,
            approved_at: approved_at,
            rejected_by: rejected_by,
            rejected_at: rejected_at,
            reason: reason,
            expires_at: expires_at,
            reminded_at: reminded_at,
            metadata: metadata,
            created_at: created_at
          }.compact
        end

        # Error for invalid state transitions
        class InvalidStateError < StandardError; end
      end
    end
  end
end
