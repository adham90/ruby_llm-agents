# frozen_string_literal: true

module RubyLLM
  module Agents
    class ApplicationController < ActionController::Base
      layout "rubyllm/agents/application"

      before_action :authenticate_dashboard!

      private

      def authenticate_dashboard!
        auth_proc = RubyLLM::Agents.configuration.dashboard_auth
        return if auth_proc.call(self)

        render plain: "Unauthorized", status: :unauthorized
      end
    end
  end
end
