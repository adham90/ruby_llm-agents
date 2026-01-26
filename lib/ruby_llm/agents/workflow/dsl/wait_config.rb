# frozen_string_literal: true

module RubyLLM
  module Agents
    class Workflow
      module DSL
        # Configuration object for a workflow wait step
        #
        # Holds all the configuration options for a wait step including
        # the type (delay, until, schedule, approval), duration, conditions,
        # timeout settings, and notification options.
        #
        # @example Simple delay
        #   WaitConfig.new(type: :delay, duration: 5.seconds)
        #
        # @example Conditional wait
        #   WaitConfig.new(
        #     type: :until,
        #     condition: -> { payment.confirmed? },
        #     poll_interval: 5.seconds,
        #     timeout: 10.minutes
        #   )
        #
        # @example Human approval
        #   WaitConfig.new(
        #     type: :approval,
        #     name: :manager_approval,
        #     notify: [:email, :slack],
        #     timeout: 24.hours
        #   )
        #
        # @api private
        class WaitConfig
          TYPES = %i[delay until schedule approval].freeze

          attr_reader :type, :duration, :condition, :name, :options

          # @param type [Symbol] Wait type (:delay, :until, :schedule, :approval)
          # @param duration [ActiveSupport::Duration, Integer, nil] Duration for delay
          # @param condition [Proc, nil] Condition for until/schedule waits
          # @param name [Symbol, nil] Name for approval waits
          # @param options [Hash] Additional options
          def initialize(type:, duration: nil, condition: nil, name: nil, **options)
            raise ArgumentError, "Unknown wait type: #{type}" unless TYPES.include?(type)

            @type = type
            @duration = duration
            @condition = condition
            @name = name
            @options = options
          end

          # Returns whether this is a simple delay
          #
          # @return [Boolean]
          def delay?
            type == :delay
          end

          # Returns whether this is a conditional wait
          #
          # @return [Boolean]
          def conditional?
            type == :until
          end

          # Returns whether this is a scheduled wait
          #
          # @return [Boolean]
          def scheduled?
            type == :schedule
          end

          # Returns whether this is an approval wait
          #
          # @return [Boolean]
          def approval?
            type == :approval
          end

          # Returns the poll interval for conditional waits
          #
          # @return [ActiveSupport::Duration, Integer] Default: 1 second
          def poll_interval
            options[:poll_interval] || 1
          end

          # Returns the timeout for the wait
          #
          # @return [ActiveSupport::Duration, Integer, nil]
          def timeout
            options[:timeout]
          end

          # Returns the action to take on timeout
          #
          # @return [Symbol] :fail, :continue, or :skip_next (default: :fail)
          def on_timeout
            options[:on_timeout] || :fail
          end

          # Returns the backoff multiplier for exponential backoff
          #
          # @return [Numeric, nil]
          def backoff
            options[:backoff]
          end

          # Returns the maximum poll interval when using backoff
          #
          # @return [ActiveSupport::Duration, Integer, nil]
          def max_interval
            options[:max_interval]
          end

          # Returns whether this wait uses exponential backoff
          #
          # @return [Boolean]
          def exponential_backoff?
            backoff.present?
          end

          # Returns the notification channels for approval waits
          #
          # @return [Array<Symbol>]
          def notify_channels
            Array(options[:notify])
          end

          # Returns the message for approval notifications
          #
          # @return [String, Proc, nil]
          def message
            options[:message]
          end

          # Returns the reminder interval
          #
          # @return [ActiveSupport::Duration, Integer, nil]
          def reminder_after
            options[:reminder_after]
          end

          # Returns the reminder repeat interval
          #
          # @return [ActiveSupport::Duration, Integer, nil]
          def reminder_interval
            options[:reminder_interval]
          end

          # Returns the escalation target on timeout
          #
          # @return [Symbol, nil]
          def escalate_to
            options[:escalate_to]
          end

          # Returns the list of approvers
          #
          # @return [Array<String, Symbol>]
          def approvers
            Array(options[:approvers])
          end

          # Returns the timezone for scheduled waits
          #
          # @return [String, nil]
          def timezone
            options[:timezone]
          end

          # Returns the condition for executing this wait
          #
          # @return [Symbol, Proc, nil]
          def if_condition
            options[:if]
          end

          # Returns the negative condition for executing this wait
          #
          # @return [Symbol, Proc, nil]
          def unless_condition
            options[:unless]
          end

          # Evaluates whether this wait should execute
          #
          # @param workflow [Workflow] The workflow instance
          # @return [Boolean]
          def should_execute?(workflow)
            passes_if = if_condition.nil? || evaluate_condition(workflow, if_condition)
            passes_unless = unless_condition.nil? || !evaluate_condition(workflow, unless_condition)
            passes_if && passes_unless
          end

          # Returns a UI-friendly label for this wait
          #
          # @return [String]
          def ui_label
            case type
            when :delay
              "Wait #{format_duration(duration)}"
            when :until
              "Wait until condition"
            when :schedule
              "Wait until scheduled time"
            when :approval
              "Awaiting #{name || 'approval'}"
            end
          end

          # Converts to hash for serialization
          #
          # @return [Hash]
          def to_h
            {
              type: type,
              duration: duration,
              name: name,
              poll_interval: poll_interval,
              timeout: timeout,
              on_timeout: on_timeout,
              backoff: backoff,
              max_interval: max_interval,
              notify: notify_channels,
              approvers: approvers,
              ui_label: ui_label
            }.compact
          end

          private

          def evaluate_condition(workflow, condition)
            case condition
            when Symbol then workflow.send(condition)
            when Proc then workflow.instance_exec(&condition)
            else condition
            end
          end

          def format_duration(dur)
            return "unknown" unless dur

            seconds = dur.respond_to?(:to_i) ? dur.to_i : dur
            if seconds >= 3600
              "#{seconds / 3600}h"
            elsif seconds >= 60
              "#{seconds / 60}m"
            else
              "#{seconds}s"
            end
          end
        end
      end
    end
  end
end
