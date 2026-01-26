# frozen_string_literal: true

require_relative "notifiers/base"
require_relative "notifiers/email"
require_relative "notifiers/slack"
require_relative "notifiers/webhook"

module RubyLLM
  module Agents
    class Workflow
      module Notifiers
        # Configure and register default notifiers
        #
        # @example Register notifiers
        #   RubyLLM::Agents::Workflow::Notifiers.setup do |config|
        #     config.register :email, Email.new
        #     config.register :slack, Slack.new(webhook_url: "...")
        #   end
        #
        # @api public
        class << self
          # Setup notifiers with configuration
          #
          # @yield [Registry] The notifier registry
          # @return [void]
          def setup
            yield Registry
          end

          # Register a notifier
          #
          # @param name [Symbol] The notifier name
          # @param notifier [Base] The notifier instance
          # @return [void]
          def register(name, notifier)
            Registry.register(name, notifier)
          end

          # Get a notifier
          #
          # @param name [Symbol] The notifier name
          # @return [Base, nil]
          def [](name)
            Registry.get(name)
          end

          # Send notifications through multiple channels
          #
          # @param approval [Approval] The approval request
          # @param message [String] The notification message
          # @param channels [Array<Symbol>] The channels to notify
          # @return [Hash<Symbol, Boolean>] Results per channel
          def notify(approval, message, channels:)
            Registry.notify_all(approval, message, channels: channels)
          end

          # Reset all notifier configuration
          #
          # @return [void]
          def reset!
            Registry.reset!
            Email.reset!
            Slack.reset!
            Webhook.reset!
          end
        end
      end
    end
  end
end
