# frozen_string_literal: true

module RubyLLM
  module Agents
    class Workflow
      module DSL
        # Executes wait steps within a workflow
        #
        # Handles the four types of waits:
        # - delay: Simple time-based pause
        # - until: Poll until a condition is met
        # - schedule: Wait until a specific time
        # - approval: Wait for human approval
        #
        # @example Executing a delay wait
        #   executor = WaitExecutor.new(wait_config, workflow)
        #   result = executor.execute
        #
        # @api private
        class WaitExecutor
          # @param config [WaitConfig] The wait configuration
          # @param workflow [Workflow] The workflow instance
          # @param approval_store [ApprovalStore, nil] Custom approval store
          def initialize(config, workflow, approval_store: nil)
            @config = config
            @workflow = workflow
            @approval_store = approval_store || ApprovalStore.store
          end

          # Execute the wait step
          #
          # @return [WaitResult] The result of the wait
          def execute
            # Check conditions first
            unless @config.should_execute?(@workflow)
              return WaitResult.skipped(@config.type, reason: "Condition not met")
            end

            case @config.type
            when :delay
              execute_delay
            when :until
              execute_until
            when :schedule
              execute_schedule
            when :approval
              execute_approval
            else
              raise ArgumentError, "Unknown wait type: #{@config.type}"
            end
          end

          private

          # Execute a simple delay
          #
          # @return [WaitResult]
          def execute_delay
            duration = resolve_duration(@config.duration)
            sleep_with_interruption(duration)
            WaitResult.success(:delay, duration)
          end

          # Execute a conditional wait (polling)
          #
          # @return [WaitResult]
          def execute_until
            started_at = Time.now
            interval = normalize_duration(@config.poll_interval)
            timeout = @config.timeout ? normalize_duration(@config.timeout) : nil
            max_interval = @config.max_interval ? normalize_duration(@config.max_interval) : nil

            loop do
              # Check condition
              if evaluate_condition(@config.condition)
                waited = Time.now - started_at
                return WaitResult.success(:until, waited)
              end

              # Check timeout
              if timeout
                elapsed = Time.now - started_at
                if elapsed >= timeout
                  return handle_timeout(:until, elapsed)
                end
              end

              # Wait before next poll
              sleep_with_interruption(interval)

              # Apply exponential backoff if configured
              if @config.exponential_backoff?
                interval = apply_backoff(interval, max_interval)
              end
            end
          end

          # Execute a scheduled wait
          #
          # @return [WaitResult]
          def execute_schedule
            target_time = evaluate_time(@config.condition)

            unless target_time.is_a?(Time)
              raise ArgumentError, "Schedule condition must return a Time, got #{target_time.class}"
            end

            wait_duration = target_time - Time.now

            if wait_duration > 0
              sleep_with_interruption(wait_duration)
            end

            WaitResult.success(:schedule, [wait_duration, 0].max, target_time: target_time)
          end

          # Execute a human approval wait
          #
          # @return [WaitResult]
          def execute_approval
            started_at = Time.now

            # Create approval request
            approval = create_approval_request

            # Save to store
            @approval_store.save(approval)

            # Send notifications
            send_notifications(approval)

            # Set up reminder tracking
            reminder_sent = false
            reminder_after = @config.reminder_after ? normalize_duration(@config.reminder_after) : nil
            reminder_interval = @config.reminder_interval ? normalize_duration(@config.reminder_interval) : nil

            # Poll for approval or timeout
            timeout = @config.timeout ? normalize_duration(@config.timeout) : nil
            poll_interval = normalize_duration(@config.poll_interval)

            loop do
              # Refresh approval from store
              approval = @approval_store.find(approval.id)

              unless approval
                waited = Time.now - started_at
                return WaitResult.timeout(:approval, waited, :fail,
                                          error: "Approval not found")
              end

              # Check if approved
              if approval.approved?
                waited = Time.now - started_at
                return WaitResult.approved(approval.id, approval.approved_by, waited)
              end

              # Check if rejected
              if approval.rejected?
                waited = Time.now - started_at
                return WaitResult.rejected(approval.id, approval.rejected_by, waited,
                                           reason: approval.reason)
              end

              # Check if expired
              if approval.expired? || approval.timed_out?
                waited = Time.now - started_at
                return handle_timeout(:approval, waited, approval_id: approval.id)
              end

              # Check timeout
              if timeout
                elapsed = Time.now - started_at
                if elapsed >= timeout
                  approval.expire!
                  @approval_store.save(approval)
                  return handle_timeout(:approval, elapsed, approval_id: approval.id)
                end
              end

              # Check if reminder should be sent
              if reminder_after && approval.should_remind?(reminder_after,
                                                           reminder_interval: reminder_interval)
                send_reminder(approval)
                approval.mark_reminded!
                @approval_store.save(approval)
              end

              # Wait before next poll
              sleep_with_interruption(poll_interval)
            end
          end

          def create_approval_request
            Approval.new(
              workflow_id: @workflow.object_id.to_s,
              workflow_type: @workflow.class.name,
              name: @config.name,
              approvers: @config.approvers,
              expires_at: @config.timeout ? Time.now + normalize_duration(@config.timeout) : nil,
              metadata: {
                workflow_input: @workflow.input.to_h,
                created_by: "workflow"
              }
            )
          end

          def send_notifications(approval)
            return if @config.notify_channels.empty?

            message = resolve_message(@config.message, approval)
            Notifiers.notify(approval, message, channels: @config.notify_channels)
          end

          def send_reminder(approval)
            return if @config.notify_channels.empty?

            message = resolve_message(@config.message, approval)
            @config.notify_channels.each do |channel|
              notifier = Notifiers[channel]
              notifier&.remind(approval, message)
            end
          end

          def resolve_message(message_config, approval)
            case message_config
            when String
              message_config
            when Proc
              @workflow.instance_exec(approval, &message_config)
            else
              "Approval required: #{approval.name}"
            end
          end

          def handle_timeout(type, elapsed, **metadata)
            action = @config.on_timeout

            case action
            when :continue
              WaitResult.timeout(type, elapsed, :continue, **metadata)
            when :skip_next
              WaitResult.timeout(type, elapsed, :skip_next, **metadata)
            when :escalate
              handle_escalation(type, elapsed, metadata)
            else # :fail
              WaitResult.timeout(type, elapsed, :fail, **metadata)
            end
          end

          def handle_escalation(type, elapsed, metadata)
            if @config.escalate_to
              # Create escalated approval or notify escalation target
              WaitResult.timeout(type, elapsed, :escalate,
                                 escalated_to: @config.escalate_to,
                                 **metadata)
            else
              WaitResult.timeout(type, elapsed, :fail, **metadata)
            end
          end

          def resolve_duration(duration)
            normalize_duration(duration)
          end

          def normalize_duration(duration)
            if duration.respond_to?(:to_f)
              duration.to_f
            else
              duration.to_i.to_f
            end
          end

          def evaluate_condition(condition)
            case condition
            when Proc
              @workflow.instance_exec(&condition)
            when Symbol
              @workflow.send(condition)
            else
              !!condition
            end
          end

          def evaluate_time(time_config)
            case time_config
            when Proc
              @workflow.instance_exec(&time_config)
            when Time
              time_config
            else
              raise ArgumentError, "Schedule time must be a Time or Proc, got #{time_config.class}"
            end
          end

          def apply_backoff(current_interval, max_interval)
            new_interval = current_interval * @config.backoff

            if max_interval
              [new_interval, max_interval].min
            else
              new_interval
            end
          end

          def sleep_with_interruption(duration)
            # Use Async.sleep if available, otherwise Kernel.sleep
            if defined?(::Async::Task) && ::Async::Task.current?
              ::Async::Task.current.sleep(duration)
            else
              Kernel.sleep(duration)
            end
          end
        end
      end
    end
  end
end
