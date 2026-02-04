# frozen_string_literal: true

module RubyLLM
  module Agents
    # Alert notification dispatcher for governance events
    #
    # Sends notifications via user-provided handler and ActiveSupport::Notifications
    # when important events occur like budget exceedance or circuit breaker activation.
    #
    # @example Configure an alert handler
    #   RubyLLM::Agents.configure do |config|
    #     config.on_alert = ->(event, payload) {
    #       case event
    #       when :budget_hard_cap
    #         Slack::Notifier.new(ENV["SLACK_WEBHOOK"]).ping("Budget exceeded")
    #       end
    #     }
    #   end
    #
    # @example Subscribe via ActiveSupport::Notifications
    #   ActiveSupport::Notifications.subscribe(/^ruby_llm_agents\.alert\./) do |name, _, _, _, payload|
    #     event = name.sub("ruby_llm_agents.alert.", "").to_sym
    #     MyAlertService.handle(event, payload)
    #   end
    #
    # @see RubyLLM::Agents::Configuration#on_alert
    # @api public
    module AlertManager
      class << self
        # Sends a notification to the configured handler and emits AS::N
        #
        # @param event [Symbol] The event type (e.g., :budget_soft_cap, :breaker_open)
        # @param payload [Hash] Event-specific data
        # @return [void]
        def notify(event, payload)
          full_payload = build_payload(event, payload)

          # Call user-provided handler (if set)
          call_handler(event, full_payload)

          # Always emit ActiveSupport::Notification
          emit_notification(event, full_payload)

          # Store in cache for dashboard display
          store_for_dashboard(event, full_payload)
        rescue StandardError => e
          Rails.logger.error("[RubyLLM::Agents::AlertManager] Failed: #{e.message}")
        end

        private

        # Builds the full payload with standard fields
        #
        # @param event [Symbol] The event type
        # @param payload [Hash] The original payload
        # @return [Hash] Payload with event, timestamp, and tenant_id added
        def build_payload(event, payload)
          payload.merge(
            event: event,
            timestamp: Time.current,
            tenant_id: RubyLLM::Agents.configuration.current_tenant_id
          )
        end

        # Calls the user-provided alert handler
        #
        # @param event [Symbol] The event type
        # @param payload [Hash] The full payload
        # @return [void]
        def call_handler(event, payload)
          handler = RubyLLM::Agents.configuration.on_alert
          return unless handler.respond_to?(:call)

          handler.call(event, payload)
        rescue StandardError => e
          Rails.logger.warn("[RubyLLM::Agents::AlertManager] Handler failed: #{e.message}")
        end

        # Emits an ActiveSupport::Notification
        #
        # @param event [Symbol] The event type
        # @param payload [Hash] The full payload
        # @return [void]
        def emit_notification(event, payload)
          ActiveSupport::Notifications.instrument("ruby_llm_agents.alert.#{event}", payload)
        rescue StandardError
          # Ignore notification failures
        end

        # Stores the alert in cache for dashboard display
        #
        # @param event [Symbol] The event type
        # @param payload [Hash] The full payload
        # @return [void]
        def store_for_dashboard(event, payload)
          cache = RubyLLM::Agents.configuration.cache_store
          key = "ruby_llm_agents:alerts:recent"

          alerts = cache.read(key) || []
          alerts.unshift(
            type: event,
            message: format_message(event, payload),
            agent_type: payload[:agent_type],
            timestamp: payload[:timestamp]
          )
          alerts = alerts.first(50)

          cache.write(key, alerts, expires_in: 24.hours)
        rescue StandardError
          # Ignore cache failures
        end

        # Formats a human-readable message for the event
        #
        # @param event [Symbol] The event type
        # @param payload [Hash] The full payload
        # @return [String] Human-readable message
        def format_message(event, payload)
          case event
          when :budget_soft_cap
            "Budget soft cap reached: $#{payload[:total_cost]&.round(2)} / $#{payload[:limit]&.round(2)}"
          when :budget_hard_cap
            "Budget hard cap exceeded: $#{payload[:total_cost]&.round(2)} / $#{payload[:limit]&.round(2)}"
          when :breaker_open
            "Circuit breaker opened for #{payload[:agent_type]}"
          when :breaker_closed
            "Circuit breaker closed for #{payload[:agent_type]}"
          when :agent_anomaly
            "Anomaly detected: #{payload[:threshold_type]} threshold exceeded"
          else
            event.to_s.humanize
          end
        end
      end
    end
  end
end
