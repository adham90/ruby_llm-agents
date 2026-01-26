# frozen_string_literal: true

require "net/http"
require "uri"
require "json"

module RubyLLM
  module Agents
    class Workflow
      module Notifiers
        # Generic webhook notification adapter for approval requests
        #
        # Posts approval notifications to any HTTP endpoint.
        # Supports custom headers for authentication and content negotiation.
        #
        # @example Basic usage
        #   notifier = Webhook.new(url: "https://api.example.com/approvals")
        #   notifier.notify(approval, "Please review")
        #
        # @example With authentication
        #   notifier = Webhook.new(
        #     url: "https://api.example.com/approvals",
        #     headers: { "Authorization" => "Bearer token123" }
        #   )
        #
        # @api public
        class Webhook < Base
          class << self
            attr_accessor :default_url, :default_headers, :timeout

            # Configure the webhook notifier
            #
            # @yield [self] The webhook notifier class
            # @return [void]
            def configure
              yield self
            end

            # Reset configuration to defaults
            #
            # @return [void]
            def reset!
              @default_url = nil
              @default_headers = nil
              @timeout = nil
            end
          end

          # @param url [String] The webhook URL
          # @param headers [Hash] Additional HTTP headers
          # @param timeout [Integer] Request timeout in seconds
          def initialize(url: nil, headers: {}, timeout: nil)
            @url = url || self.class.default_url
            @headers = (self.class.default_headers || {}).merge(headers)
            @timeout = timeout || self.class.timeout || 10
          end

          # Send a webhook notification
          #
          # @param approval [Approval] The approval request
          # @param message [String] The notification message
          # @return [Boolean] true if webhook returned 2xx status
          def notify(approval, message)
            return false unless @url

            payload = build_payload(approval, message)
            send_request(payload)
          rescue StandardError => e
            handle_error(e, approval)
            false
          end

          private

          def build_payload(approval, message)
            {
              event: "approval_requested",
              approval: {
                id: approval.id,
                workflow_id: approval.workflow_id,
                workflow_type: approval.workflow_type,
                name: approval.name,
                status: approval.status,
                approvers: approval.approvers,
                expires_at: approval.expires_at&.iso8601,
                created_at: approval.created_at.iso8601,
                metadata: approval.metadata
              },
              message: message,
              timestamp: Time.now.iso8601
            }
          end

          def send_request(payload)
            uri = URI.parse(@url)
            http = Net::HTTP.new(uri.host, uri.port)
            http.use_ssl = uri.scheme == "https"
            http.open_timeout = @timeout
            http.read_timeout = @timeout

            request = Net::HTTP::Post.new(uri.request_uri)
            request["Content-Type"] = "application/json"
            @headers.each { |key, value| request[key] = value }
            request.body = payload.to_json

            response = http.request(request)
            response.code.to_i.between?(200, 299)
          end

          def handle_error(error, approval)
            if defined?(Rails) && Rails.logger
              Rails.logger.error(
                "[RubyLLM::Agents] Webhook notification failed for approval #{approval.id}: #{error.message}"
              )
            end
          end
        end
      end
    end
  end
end
