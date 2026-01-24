# frozen_string_literal: true

module RubyLLM
  module Agents
    # Mailer for sending alert notifications via email
    #
    # Delivers alert notifications when important events occur like
    # budget exceedance or circuit breaker activation.
    #
    # @example Sending an alert email
    #   AlertMailer.alert_notification(
    #     event: :budget_hard_cap,
    #     payload: { limit: 100.0, total: 105.0 },
    #     recipient: "admin@example.com"
    #   ).deliver_later
    #
    # @api public
    class AlertMailer < ApplicationMailer
      # Sends an alert notification email
      #
      # @param event [Symbol] The event type (e.g., :budget_soft_cap, :breaker_open)
      # @param payload [Hash] Event-specific data
      # @param recipient [String] Email address of the recipient
      # @return [Mail::Message]
      def alert_notification(event:, payload:, recipient:)
        @event = event
        @payload = payload
        @title = event_title(event)
        @severity = event_severity(event)
        @color = event_color(event)
        @timestamp = Time.current

        mail(
          to: recipient,
          subject: "[RubyLLM::Agents Alert] #{@title}"
        )
      end

      private

      # Returns human-readable title for event type
      #
      # @param event [Symbol] The event type
      # @return [String] Human-readable title
      def event_title(event)
        case event
        when :budget_soft_cap then "Budget Soft Cap Reached"
        when :budget_hard_cap then "Budget Hard Cap Exceeded"
        when :breaker_open then "Circuit Breaker Opened"
        when :agent_anomaly then "Agent Anomaly Detected"
        else event.to_s.titleize
        end
      end

      # Returns severity level for event type
      #
      # @param event [Symbol] The event type
      # @return [String] Severity level
      def event_severity(event)
        case event
        when :budget_soft_cap then "Warning"
        when :budget_hard_cap then "Critical"
        when :breaker_open then "Critical"
        when :agent_anomaly then "Warning"
        else "Info"
        end
      end

      # Returns color for event type
      #
      # @param event [Symbol] The event type
      # @return [String] Hex color code
      def event_color(event)
        case event
        when :budget_soft_cap then "#FFA500"  # Orange
        when :budget_hard_cap then "#FF0000"  # Red
        when :breaker_open then "#FF0000"     # Red
        when :agent_anomaly then "#FFA500"    # Orange
        else "#0000FF"                        # Blue
        end
      end
    end
  end
end
