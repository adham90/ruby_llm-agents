# frozen_string_literal: true

require "faraday"
require "json"

module RubyLLM
  module Agents
    # Alert notification dispatcher for governance events
    #
    # Sends notifications to configured destinations (Slack, webhooks, custom procs)
    # when important events occur like budget exceedance or circuit breaker activation.
    #
    # @example Sending an alert
    #   AlertManager.notify(:budget_soft_cap, { limit: 25.0, total: 27.5 })
    #
    # @see RubyLLM::Agents::Configuration
    # @api public
    module AlertManager
      class << self
        # Sends a notification to all configured destinations
        #
        # @param event [Symbol] The event type (e.g., :budget_soft_cap, :breaker_open)
        # @param payload [Hash] Event-specific data
        # @return [void]
        def notify(event, payload)
          config = RubyLLM::Agents.configuration
          return unless config.alerts_enabled?
          return unless config.alert_events.include?(event)

          alerts = config.alerts
          full_payload = payload.merge(event: event)

          # Send to Slack
          if alerts[:slack_webhook_url].present?
            send_slack_alert(alerts[:slack_webhook_url], event, full_payload)
          end

          # Send to generic webhook
          if alerts[:webhook_url].present?
            send_webhook_alert(alerts[:webhook_url], full_payload)
          end

          # Call custom proc
          if alerts[:custom].respond_to?(:call)
            call_custom_alert(alerts[:custom], event, full_payload)
          end

          # Emit ActiveSupport::Notification for observability
          emit_notification(event, full_payload)
        rescue StandardError => e
          # Don't let alert failures break the application
          Rails.logger.error("[RubyLLM::Agents::AlertManager] Failed to send alert: #{e.message}")
        end

        private

        # Sends a Slack webhook alert
        #
        # @param webhook_url [String] The Slack webhook URL
        # @param event [Symbol] The event type
        # @param payload [Hash] The payload
        # @return [void]
        def send_slack_alert(webhook_url, event, payload)
          message = format_slack_message(event, payload)

          post_json(webhook_url, message)
        rescue StandardError => e
          Rails.logger.warn("[RubyLLM::Agents::AlertManager] Slack alert failed: #{e.message}")
        end

        # Sends a generic webhook alert
        #
        # @param webhook_url [String] The webhook URL
        # @param payload [Hash] The payload
        # @return [void]
        def send_webhook_alert(webhook_url, payload)
          post_json(webhook_url, payload)
        rescue StandardError => e
          Rails.logger.warn("[RubyLLM::Agents::AlertManager] Webhook alert failed: #{e.message}")
        end

        # Calls a custom alert proc
        #
        # @param custom_proc [Proc] The custom handler
        # @param event [Symbol] The event type
        # @param payload [Hash] The payload
        # @return [void]
        def call_custom_alert(custom_proc, event, payload)
          custom_proc.call(event, payload)
        rescue StandardError => e
          Rails.logger.warn("[RubyLLM::Agents::AlertManager] Custom alert failed: #{e.message}")
        end

        # Emits an ActiveSupport::Notification
        #
        # @param event [Symbol] The event type
        # @param payload [Hash] The payload
        # @return [void]
        def emit_notification(event, payload)
          ActiveSupport::Notifications.instrument("ruby_llm_agents.alert.#{event}", payload)
        rescue StandardError
          # Ignore notification failures
        end

        # Formats a Slack message for the event
        #
        # @param event [Symbol] The event type
        # @param payload [Hash] The payload
        # @return [Hash] Slack message payload
        def format_slack_message(event, payload)
          emoji = event_emoji(event)
          title = event_title(event)
          color = event_color(event)

          fields = payload.except(:event).map do |key, value|
            {
              title: key.to_s.titleize,
              value: value.to_s,
              short: true
            }
          end

          {
            attachments: [
              {
                fallback: "#{title}: #{payload.except(:event).to_json}",
                color: color,
                pretext: "#{emoji} *RubyLLM::Agents Alert*",
                title: title,
                fields: fields,
                footer: "RubyLLM::Agents",
                ts: Time.current.to_i
              }
            ]
          }
        end

        # Returns emoji for event type
        #
        # @param event [Symbol] The event type
        # @return [String] Emoji
        def event_emoji(event)
          case event
          when :budget_soft_cap then ":warning:"
          when :budget_hard_cap then ":no_entry:"
          when :breaker_open then ":rotating_light:"
          when :agent_anomaly then ":mag:"
          else ":bell:"
          end
        end

        # Returns title for event type
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

        # Posts JSON to a URL using Faraday
        #
        # @param url [String] The URL
        # @param payload [Hash] The payload
        # @return [Faraday::Response]
        def post_json(url, payload)
          response = http_client.post(url) do |req|
            req.headers["Content-Type"] = "application/json"
            req.body = payload.to_json
          end

          unless response.success?
            Rails.logger.warn("[RubyLLM::Agents::AlertManager] Webhook returned #{response.status}: #{response.body}")
          end

          response
        end

        # Returns a configured Faraday HTTP client
        #
        # @return [Faraday::Connection]
        def http_client
          @http_client ||= Faraday.new do |conn|
            conn.options.open_timeout = 5
            conn.options.timeout = 10
            conn.adapter Faraday.default_adapter
          end
        end
      end
    end
  end
end
