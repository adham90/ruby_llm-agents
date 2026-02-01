# frozen_string_literal: true

# Example Workflow demonstrating Wait/Delay features
# Shows human-in-the-loop approval, delays, and scheduled execution
#
# Demonstrates:
#   - wait: Simple time-based delays between steps
#   - wait_until: Conditional polling with timeout and backoff
#   - wait_until time: Scheduled execution at specific times
#   - wait_for: Human approval with notifications and reminders
#   - Throttle and rate limiting for API protection
#   - Timeout handling with :continue, :fail, :skip_next, :escalate
#
# Usage:
#   result = ApprovalWorkflow.call(
#     document_id: "doc-123",
#     amount: 5000,
#     requester: "alice@example.com"
#   )
#
class ApprovalWorkflow < RubyLLM::Agents::Workflow
  include RubyLLM::Agents::Workflow::DSL::ScheduleHelpers

  description 'Multi-stage document approval with delays and human review'
  version '1.0'
  timeout 48.hours
  max_cost 5.00

  input do
    required :document_id, String
    required :amount, Numeric
    required :requester, String
    optional :priority, String, default: 'normal'
    optional :auto_approve_threshold, Numeric, default: 1000
  end

  # Step 1: Fetch document with rate limiting
  step :fetch_document, DocumentFetcherAgent, 'Retrieve document for review',
       timeout: 30.seconds,
       throttle: 2.seconds,
       retry: { max: 3, backoff: :exponential }

  # Step 2: Auto-classification
  step :classify, ClassifierAgent, 'Determine approval requirements',
       rate_limit: { calls: 10, per: 60 },
       input: -> { { document: fetch_document.content, amount: input.amount } }

  # Step 3: Small amounts - auto-approve with brief delay
  step :auto_approve, AutoApproverAgent, 'Auto-approve low-value requests',
       if: -> { input.amount <= input.auto_approve_threshold },
       input: -> { { document_id: input.document_id, reason: 'Under threshold' } }

  # Wait 5 seconds before human review (rate limiting / cooldown)
  wait 5.seconds, unless: -> { input.amount <= input.auto_approve_threshold }

  # Step 4: Large amounts - require manager approval
  wait_for :manager_approval,
           if: -> { input.amount > input.auto_approve_threshold },
           approvers: ['manager@example.com', 'director@example.com'],
           notify: %i[email slack],
           message: -> { "Approval needed for #{input.document_id} ($#{input.amount})" },
           timeout: 24.hours,
           on_timeout: :escalate,
           escalate_to: 'director@example.com',
           reminder_after: 4.hours,
           reminder_interval: 2.hours

  # Step 5: After approval, wait until business hours to process
  wait_until time: -> { in_business_hours(start_hour: 9, end_hour: 17) },
             if: -> { input.priority != 'urgent' }

  # Step 6: Generate approval document
  step :generate_approval, ApprovalDocumentAgent, 'Create approval record',
       input: lambda {
         {
           document_id: input.document_id,
           amount: input.amount,
           approved_by: manager_approval&.approved_by || 'auto',
           classification: classify.category
         }
       }

  # Wait until external system is ready (polling)
  wait_until -> { external_system_ready? },
             poll_interval: 10.seconds,
             timeout: 5.minutes,
             on_timeout: :continue,
             backoff: 1.5,
             max_interval: 30.seconds

  # Step 7: Submit to external system with throttling
  step :submit, SubmissionAgent, 'Submit to external system',
       throttle: 5.seconds,
       retry: 2,
       optional: true,
       default: { submitted: false, reason: 'External system unavailable' }

  # Step 8: Notify requester
  step :notify_requester, NotificationAgent, 'Send completion notification',
       input: lambda {
         {
           to: input.requester,
           document_id: input.document_id,
           status: submit&.success? ? 'approved' : 'pending_submission'
         }
       }

  on_step_error do |step_name, error|
    Rails.logger.error "Approval workflow step #{step_name} failed: #{error.message}"
  end

  after_workflow do
    Rails.logger.info "Approval workflow completed: #{input.document_id}"
  end

  private

  def external_system_ready?
    # Simulated check - in real usage would call external API
    @external_check_count ||= 0
    @external_check_count += 1
    @external_check_count >= 3 # Ready after 3 polls
  end
end
