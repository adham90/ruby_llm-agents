# frozen_string_literal: true

module RubyLLM
  module Agents
    class Engine < ::Rails::Engine
      isolate_namespace RubyLLM::Agents

      # Use to_prepare to load classes after autoloading is set up
      # This ensures app/models are available when referenced
      config.to_prepare do
        require_relative "execution_logger_job"
        require_relative "instrumentation"
        require_relative "base"

        # Dynamically set parent controller based on configuration
        parent_class = RubyLLM::Agents.configuration.dashboard_parent_controller.constantize

        # Remove existing constant if defined, then redefine with correct parent
        RubyLLM::Agents.send(:remove_const, :ApplicationController) if RubyLLM::Agents.const_defined?(:ApplicationController, false)

        RubyLLM::Agents.const_set(:ApplicationController, Class.new(parent_class) do
          layout "rubyllm/agents/application"
          helper RubyLLM::Agents::ApplicationHelper
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
        end)
      end

      # Configure generators
      config.generators do |g|
        g.test_framework :rspec
        g.fixture_replacement :factory_bot
        g.factory_bot dir: "spec/factories"
      end

      # Add app/agents to autoload paths for host app (must be done before initialization)
      initializer "ruby_llm_agents.autoload_agents", before: :set_autoload_paths do |app|
        agents_path = app.root.join("app/agents")
        if agents_path.exist?
          Rails.autoloaders.main.push_dir(agents_path.to_s)
        end
      end
    end
  end
end
