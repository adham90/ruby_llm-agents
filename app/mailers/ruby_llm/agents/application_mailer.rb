# frozen_string_literal: true

module RubyLLM
  module Agents
    # Base mailer class for RubyLLM::Agents
    #
    # Host application must configure ActionMailer with SMTP settings
    # for email delivery to work.
    #
    # @api private
    class ApplicationMailer < ::ActionMailer::Base
      default from: -> { default_from_address }

      layout false  # Templates are self-contained

      private

      def default_from_address
        RubyLLM::Agents.configuration.alerts&.dig(:email_from) ||
          "noreply@#{default_host}"
      end

      def default_host
        ::ActionMailer::Base.default_url_options[:host] || "example.com"
      end
    end
  end
end
