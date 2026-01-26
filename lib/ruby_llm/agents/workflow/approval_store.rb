# frozen_string_literal: true

module RubyLLM
  module Agents
    class Workflow
      # Abstract base class for approval storage
      #
      # Provides a common interface for storing and retrieving approval requests.
      # Implementations can use in-memory storage, databases, Redis, etc.
      #
      # @example Setting a custom store
      #   RubyLLM::Agents::Workflow::ApprovalStore.store = MyRedisStore.new
      #
      # @example Using the default store
      #   store = RubyLLM::Agents::Workflow::ApprovalStore.store
      #   store.save(approval)
      #
      # @api public
      class ApprovalStore
        class << self
          # Returns the configured store instance
          #
          # @return [ApprovalStore]
          def store
            @store ||= default_store
          end

          # Sets the store instance
          #
          # @param store [ApprovalStore] The store to use
          # @return [void]
          def store=(store)
            @store = store
          end

          # Resets to the default store (useful for testing)
          #
          # @return [void]
          def reset!
            @store = nil
          end

          private

          def default_store
            MemoryApprovalStore.new
          end
        end

        # Save an approval
        #
        # @param approval [Approval] The approval to save
        # @return [Approval] The saved approval
        def save(approval)
          raise NotImplementedError, "#{self.class}#save must be implemented"
        end

        # Find an approval by ID
        #
        # @param id [String] The approval ID
        # @return [Approval, nil]
        def find(id)
          raise NotImplementedError, "#{self.class}#find must be implemented"
        end

        # Find all approvals for a workflow
        #
        # @param workflow_id [String] The workflow ID
        # @return [Array<Approval>]
        def find_by_workflow(workflow_id)
          raise NotImplementedError, "#{self.class}#find_by_workflow must be implemented"
        end

        # Find pending approvals for a user
        #
        # @param user_id [String] The user ID
        # @return [Array<Approval>]
        def pending_for_user(user_id)
          raise NotImplementedError, "#{self.class}#pending_for_user must be implemented"
        end

        # Find all pending approvals
        #
        # @return [Array<Approval>]
        def all_pending
          raise NotImplementedError, "#{self.class}#all_pending must be implemented"
        end

        # Delete an approval
        #
        # @param id [String] The approval ID
        # @return [Boolean] true if deleted
        def delete(id)
          raise NotImplementedError, "#{self.class}#delete must be implemented"
        end

        # Delete all approvals (useful for testing)
        #
        # @return [void]
        def clear!
          raise NotImplementedError, "#{self.class}#clear! must be implemented"
        end
      end

      # In-memory approval store for development and testing
      #
      # Thread-safe storage using a Mutex.
      #
      # @api public
      class MemoryApprovalStore < ApprovalStore
        def initialize
          @approvals = {}
          @mutex = Mutex.new
        end

        # @see ApprovalStore#save
        def save(approval)
          @mutex.synchronize do
            @approvals[approval.id] = approval
          end
          approval
        end

        # @see ApprovalStore#find
        def find(id)
          @mutex.synchronize do
            @approvals[id]
          end
        end

        # @see ApprovalStore#find_by_workflow
        def find_by_workflow(workflow_id)
          @mutex.synchronize do
            @approvals.values.select { |a| a.workflow_id == workflow_id }
          end
        end

        # @see ApprovalStore#pending_for_user
        def pending_for_user(user_id)
          @mutex.synchronize do
            @approvals.values.select do |a|
              a.pending? && a.can_approve?(user_id)
            end
          end
        end

        # @see ApprovalStore#all_pending
        def all_pending
          @mutex.synchronize do
            @approvals.values.select(&:pending?)
          end
        end

        # @see ApprovalStore#delete
        def delete(id)
          @mutex.synchronize do
            !!@approvals.delete(id)
          end
        end

        # @see ApprovalStore#clear!
        def clear!
          @mutex.synchronize do
            @approvals.clear
          end
        end

        # Returns the count of stored approvals
        #
        # @return [Integer]
        def count
          @mutex.synchronize do
            @approvals.size
          end
        end
      end
    end
  end
end
