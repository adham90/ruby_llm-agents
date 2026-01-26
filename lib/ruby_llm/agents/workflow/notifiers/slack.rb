# frozen_string_literal: true

require "net/http"
require "uri"
require "json"

module RubyLLM
  module Agents
    class Workflow
      module Notifiers
        # Slack notification adapter for approval requests
        #
        # Sends notifications via Slack webhooks or the Slack API.
        # Supports rich message formatting with blocks.
        #
        # @example Using a webhook
        #   notifier = Slack.new(webhook_url: "https://hooks.slack.com/...")
        #   notifier.notify(approval, "Please review this request")
        #
        # @example Using the API
        #   notifier = Slack.new(api_token: "xoxb-...", channel: "#approvals")
        #
        # @api public
        class Slack < Base
          class << self
            attr_accessor :webhook_url, :api_token, :default_channel

            # Configure the Slack notifier
            #
            # @yield [self] The Slack notifier class
            # @return [void]
            def configure
              yield self
            end

            # Reset configuration to defaults
            #
            # @return [void]
            def reset!
              @webhook_url = nil
              @api_token = nil
              @default_channel = nil
            end
          end

          # @param webhook_url [String, nil] Slack webhook URL
          # @param api_token [String, nil] Slack API token (for posting via API)
          # @param channel [String, nil] Default channel for messages
          def initialize(webhook_url: nil, api_token: nil, channel: nil)
            @webhook_url = webhook_url || self.class.webhook_url
            @api_token = api_token || self.class.api_token
            @channel = channel || self.class.default_channel
          end

          # Send a Slack notification
          #
          # @param approval [Approval] The approval request
          # @param message [String] The notification message
          # @return [Boolean] true if notification was sent
          def notify(approval, message)
            payload = build_payload(approval, message)

            if @webhook_url
              send_webhook(payload)
            elsif @api_token
              send_api(payload)
            else
              log_notification(approval, message)
              false
            end
          rescue StandardError => e
            handle_error(e, approval)
            false
          end

          private

          def build_payload(approval, message)
            {
              text: message,
              blocks: build_blocks(approval, message)
            }.tap do |payload|
              payload[:channel] = @channel if @channel && @api_token
            end
          end

          def build_blocks(approval, message)
            [
              {
                type: "header",
                text: {
                  type: "plain_text",
                  text: "Approval Required: #{approval.name}",
                  emoji: true
                }
              },
              {
                type: "section",
                text: {
                  type: "mrkdwn",
                  text: message
                }
              },
              {
                type: "section",
                fields: [
                  {
                    type: "mrkdwn",
                    text: "*Workflow:*\n#{approval.workflow_type}"
                  },
                  {
                    type: "mrkdwn",
                    text: "*Workflow ID:*\n#{approval.workflow_id}"
                  }
                ]
              },
              {
                type: "context",
                elements: [
                  {
                    type: "mrkdwn",
                    text: "Approval ID: `#{approval.id}`"
                  }
                ]
              }
            ]
          end

          def send_webhook(payload)
            uri = URI.parse(@webhook_url)
            http = Net::HTTP.new(uri.host, uri.port)
            http.use_ssl = uri.scheme == "https"
            http.open_timeout = 5
            http.read_timeout = 10

            request = Net::HTTP::Post.new(uri.path)
            request["Content-Type"] = "application/json"
            request.body = payload.to_json

            response = http.request(request)
            response.code.to_i == 200
          end

          def send_api(payload)
            uri = URI.parse("https://slack.com/api/chat.postMessage")
            http = Net::HTTP.new(uri.host, uri.port)
            http.use_ssl = true
            http.open_timeout = 5
            http.read_timeout = 10

            request = Net::HTTP::Post.new(uri.path)
            request["Content-Type"] = "application/json"
            request["Authorization"] = "Bearer #{@api_token}"
            request.body = payload.to_json

            response = http.request(request)
            result = JSON.parse(response.body)
            result["ok"] == true
          end

          def log_notification(approval, message)
            if defined?(Rails) && Rails.logger
              Rails.logger.info(
                "[RubyLLM::Agents] Slack notification for approval #{approval.id}: #{message}"
              )
            end
          end

          def handle_error(error, approval)
            if defined?(Rails) && Rails.logger
              Rails.logger.error(
                "[RubyLLM::Agents] Failed to send Slack message for approval #{approval.id}: #{error.message}"
              )
            end
          end
        end
      end
    end
  end
end
