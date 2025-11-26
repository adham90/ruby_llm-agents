# frozen_string_literal: true

module RubyLLM
  module Agents
    class ApplicationController < ActionController::Base
      layout "rubyllm/agents/application"

      before_action :authenticate_dashboard!

      private

      def authenticate_dashboard!
        if basic_auth_configured?
          authenticate_with_http_basic_auth
        else
          auth_proc = RubyLLM::Agents.configuration.dashboard_auth
          return if auth_proc.call(self)

          render plain: "Unauthorized", status: :unauthorized
        end
      end

      def basic_auth_configured?
        config = RubyLLM::Agents.configuration
        config.basic_auth_username.present? && config.basic_auth_password.present?
      end

      def authenticate_with_http_basic_auth
        config = RubyLLM::Agents.configuration
        authenticate_or_request_with_http_basic("RubyLLM Agents") do |username, password|
          ActiveSupport::SecurityUtils.secure_compare(username, config.basic_auth_username) &&
            ActiveSupport::SecurityUtils.secure_compare(password, config.basic_auth_password)
        end
      end
    end
  end
end
