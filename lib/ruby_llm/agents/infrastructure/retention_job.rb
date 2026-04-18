# frozen_string_literal: true

module RubyLLM
  module Agents
    # Background job that enforces two-tier data retention on execution records.
    #
    # Soft pass: for executions older than {Configuration#soft_purge_after},
    # destroys the associated execution_details and tool_executions rows,
    # preserves a truncated copy of error_message in metadata, and stamps
    # metadata["soft_purged_at"] so the dashboard can surface the state and
    # the pass stays idempotent.
    #
    # Hard pass: for executions older than {Configuration#hard_purge_after},
    # destroys the executions row itself. The foreign-key cascade removes
    # any remaining details or tool_executions.
    #
    # Either tier may be set to nil in configuration to skip that pass.
    #
    # @example Enqueue manually
    #   RubyLLM::Agents::RetentionJob.perform_later
    #
    # @example Schedule daily (whenever gem)
    #   every 1.day, at: "3:00 am" do
    #     runner "RubyLLM::Agents::RetentionJob.perform_later"
    #   end
    #
    # @api public
    class RetentionJob < ActiveJob::Base
      queue_as :default

      ERROR_MESSAGE_MAX_LENGTH = 500
      BATCH_SIZE = 500

      # Runs the soft and hard retention passes based on current configuration.
      #
      # @return [Hash] counts of rows affected in each pass
      def perform
        {
          soft_purged: soft_purge,
          hard_purged: hard_purge
        }
      end

      private

      # Destroys detail + tool_execution rows for executions older than the
      # soft-purge window that have not already been soft-purged. Stamps
      # metadata with the purge timestamp and preserves a truncated
      # error_message for long-term error-rate analytics.
      #
      # The "already purged" filter runs in Ruby rather than SQL because
      # JSON key-exists operators differ across SQLite/Postgres/MySQL; this
      # keeps the job adapter-agnostic. We batch to bound memory.
      def soft_purge
        window = RubyLLM::Agents.configuration.soft_purge_after
        return 0 if window.nil?

        cutoff = window.ago
        count = 0

        Execution
          .where("created_at < ?", cutoff)
          .includes(:detail)
          .find_in_batches(batch_size: BATCH_SIZE) do |batch|
            batch.each do |execution|
              next if execution.soft_purged?

              purge_one(execution)
              count += 1
            end
          end

        count
      end

      # Destroys executions (and everything cascaded from them) older than
      # the hard-purge window.
      def hard_purge
        window = RubyLLM::Agents.configuration.hard_purge_after
        return 0 if window.nil?

        cutoff = window.ago
        total = 0

        Execution.where("created_at < ?", cutoff).in_batches(of: BATCH_SIZE) do |batch|
          total += batch.destroy_all.size
        end

        total
      end

      # Performs the soft purge for a single execution.
      def purge_one(execution)
        preserved_error = preserved_error_message(execution)

        Execution.transaction do
          execution.detail&.destroy
          execution.tool_executions.destroy_all

          new_metadata = (execution.metadata || {}).merge(
            "soft_purged_at" => Time.current.iso8601
          )
          new_metadata["error_message"] = preserved_error if preserved_error

          execution.update_columns(metadata: new_metadata)
        end
      end

      # Returns a truncated copy of the detail's error_message, or nil.
      def preserved_error_message(execution)
        raw = execution.detail&.error_message
        return nil if raw.blank?

        raw.to_s.truncate(ERROR_MESSAGE_MAX_LENGTH)
      end
    end
  end
end
