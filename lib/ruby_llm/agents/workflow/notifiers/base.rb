# frozen_string_literal: true

module RubyLLM
  module Agents
    class Workflow
      module Notifiers
        # Base class for approval notification adapters
        #
        # Subclasses should implement the #notify and optionally #remind methods
        # to send notifications through their respective channels.
        #
        # @example Creating a custom notifier
        #   class SmsNotifier < Base
        #     def notify(approval, message)
        #       # Send SMS via Twilio
        #     end
        #   end
        #
        # @api public
        class Base
          # Send a notification for an approval request
          #
          # @param approval [Approval] The approval request
          # @param message [String] The notification message
          # @return [Boolean] true if notification was sent successfully
          def notify(approval, message)
            raise NotImplementedError, "#{self.class}#notify must be implemented"
          end

          # Send a reminder for a pending approval
          #
          # @param approval [Approval] The approval request
          # @param message [String] The reminder message
          # @return [Boolean] true if reminder was sent successfully
          def remind(approval, message)
            notify(approval, "[Reminder] #{message}")
          end

          # Send an escalation notice
          #
          # @param approval [Approval] The approval request
          # @param message [String] The escalation message
          # @param escalate_to [String] The escalation target
          # @return [Boolean] true if escalation was sent successfully
          def escalate(approval, message, escalate_to:)
            notify(approval, "[Escalation to #{escalate_to}] #{message}")
          end
        end

        # Registry for notifier instances
        #
        # @api private
        class Registry
          class << self
            # Returns the registered notifiers
            #
            # @return [Hash<Symbol, Base>]
            def notifiers
              @notifiers ||= {}
            end

            # Register a notifier
            #
            # @param name [Symbol] The notifier name
            # @param notifier [Base] The notifier instance
            # @return [void]
            def register(name, notifier)
              notifiers[name.to_sym] = notifier
            end

            # Get a registered notifier
            #
            # @param name [Symbol] The notifier name
            # @return [Base, nil]
            def get(name)
              notifiers[name.to_sym]
            end

            # Check if a notifier is registered
            #
            # @param name [Symbol] The notifier name
            # @return [Boolean]
            def registered?(name)
              notifiers.key?(name.to_sym)
            end

            # Send notification through specified channels
            #
            # @param approval [Approval] The approval request
            # @param message [String] The notification message
            # @param channels [Array<Symbol>] The notification channels
            # @return [Hash<Symbol, Boolean>] Results per channel
            def notify_all(approval, message, channels:)
              results = {}
              channels.each do |channel|
                notifier = get(channel)
                if notifier
                  results[channel] = notifier.notify(approval, message)
                else
                  results[channel] = false
                end
              end
              results
            end

            # Reset the registry (useful for testing)
            #
            # @return [void]
            def reset!
              @notifiers = {}
            end
          end
        end
      end
    end
  end
end
