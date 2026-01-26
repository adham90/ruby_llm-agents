# frozen_string_literal: true

module RubyLLM
  module Agents
    class Workflow
      module Notifiers
        # Email notification adapter for approval requests
        #
        # Uses ActionMailer if available, or a configured mailer class.
        # Can be configured with custom templates and delivery options.
        #
        # @example Configuration
        #   RubyLLM::Agents::Workflow::Notifiers::Email.configure do |config|
        #     config.mailer_class = ApprovalMailer
        #     config.from = "approvals@example.com"
        #   end
        #
        # @api public
        class Email < Base
          class << self
            attr_accessor :mailer_class, :from_address, :subject_prefix

            # Configure the email notifier
            #
            # @yield [self] The email notifier class
            # @return [void]
            def configure
              yield self
            end

            # Reset configuration to defaults
            #
            # @return [void]
            def reset!
              @mailer_class = nil
              @from_address = nil
              @subject_prefix = nil
            end
          end

          # @param mailer_class [Class, nil] Custom mailer class
          # @param from [String, nil] From address
          # @param subject_prefix [String, nil] Subject line prefix
          def initialize(mailer_class: nil, from: nil, subject_prefix: nil)
            @mailer_class = mailer_class || self.class.mailer_class
            @from_address = from || self.class.from_address || "noreply@example.com"
            @subject_prefix = subject_prefix || self.class.subject_prefix || "[Approval Required]"
          end

          # Send an email notification
          #
          # @param approval [Approval] The approval request
          # @param message [String] The notification message
          # @return [Boolean] true if email was queued
          def notify(approval, message)
            if @mailer_class
              send_via_mailer(approval, message)
            elsif defined?(ActionMailer)
              send_via_action_mailer(approval, message)
            else
              log_notification(approval, message)
              false
            end
          rescue StandardError => e
            handle_error(e, approval)
            false
          end

          private

          def send_via_mailer(approval, message)
            if @mailer_class.respond_to?(:approval_request)
              mail = @mailer_class.approval_request(approval, message)
              deliver_mail(mail)
              true
            else
              false
            end
          end

          def send_via_action_mailer(approval, message)
            # Generic ActionMailer support if no custom mailer is configured
            # Applications should configure a mailer_class for production use
            log_notification(approval, message)
            false
          end

          def deliver_mail(mail)
            if mail.respond_to?(:deliver_later)
              mail.deliver_later
            elsif mail.respond_to?(:deliver_now)
              mail.deliver_now
            elsif mail.respond_to?(:deliver)
              mail.deliver
            end
          end

          def log_notification(approval, message)
            if defined?(Rails) && Rails.logger
              Rails.logger.info(
                "[RubyLLM::Agents] Email notification for approval #{approval.id}: #{message}"
              )
            end
          end

          def handle_error(error, approval)
            if defined?(Rails) && Rails.logger
              Rails.logger.error(
                "[RubyLLM::Agents] Failed to send email for approval #{approval.id}: #{error.message}"
              )
            end
          end
        end
      end
    end
  end
end
