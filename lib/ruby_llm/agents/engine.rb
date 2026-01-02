# frozen_string_literal: true

module RubyLLM
  module Agents
    # Rails Engine for RubyLLM::Agents
    #
    # Provides a mountable dashboard for monitoring agent executions,
    # with configurable authentication and automatic agent autoloading.
    #
    # @example Mounting the engine in routes.rb
    #   Rails.application.routes.draw do
    #     mount RubyLLM::Agents::Engine => "/agents"
    #   end
    #
    # @example With authentication via parent controller
    #   RubyLLM::Agents.configure do |config|
    #     config.dashboard_parent_controller = "AdminController"
    #   end
    #
    # @see RubyLLM::Agents::Configuration
    # @api public
    class Engine < ::Rails::Engine
      isolate_namespace RubyLLM::Agents

      # Dynamically creates the ApplicationController after Rails autoloading is ready.
      # This allows the parent controller to be configured at runtime.
      #
      # The generated controller:
      # - Inherits from the configured dashboard_parent_controller
      # - Uses the engine's layout and helpers
      # - Applies authentication via before_action
      #
      # @api private
      config.to_prepare do
        require_relative "execution_logger_job"
        require_relative "instrumentation"
        require_relative "base"

        # Resolve the parent controller class from configuration
        # Default is ActionController::Base, but can be set to inherit from app controllers
        parent_class = RubyLLM::Agents.configuration.dashboard_parent_controller.constantize

        # Remove existing constant to allow redefinition on configuration change
        # This is necessary for Rails reloading in development
        RubyLLM::Agents.send(:remove_const, :ApplicationController) if RubyLLM::Agents.const_defined?(:ApplicationController, false)

        # Define the ApplicationController dynamically with the configured parent
        RubyLLM::Agents.const_set(:ApplicationController, Class.new(parent_class) do
          layout "ruby_llm/agents/application"
          helper RubyLLM::Agents::ApplicationHelper
          before_action :authenticate_dashboard!

          private

          # Authenticates dashboard access using configured method
          #
          # Authentication priority:
          # 1. HTTP Basic Auth (if username/password configured)
          # 2. Custom auth proc (dashboard_auth lambda)
          #
          # @return [void]
          # @api private
          def authenticate_dashboard!
            if basic_auth_configured?
              authenticate_with_http_basic_auth
            else
              auth_proc = RubyLLM::Agents.configuration.dashboard_auth
              return if auth_proc.call(self)

              render plain: "Unauthorized", status: :unauthorized
            end
          end

          # Checks if HTTP Basic Auth credentials are configured
          #
          # @return [Boolean] true if both username and password are present
          # @api private
          def basic_auth_configured?
            config = RubyLLM::Agents.configuration
            config.basic_auth_username.present? && config.basic_auth_password.present?
          end

          # Performs HTTP Basic Auth with timing-safe comparison
          #
          # Uses secure_compare to prevent timing attacks on credentials.
          #
          # @return [void]
          # @api private
          def authenticate_with_http_basic_auth
            config = RubyLLM::Agents.configuration
            authenticate_or_request_with_http_basic("RubyLLM Agents") do |username, password|
              ActiveSupport::SecurityUtils.secure_compare(username, config.basic_auth_username) &&
                ActiveSupport::SecurityUtils.secure_compare(password, config.basic_auth_password)
            end
          end
        end)
      end

      # Configures default generators for the engine
      # Sets up RSpec and FactoryBot for generated specs
      # @api private
      config.generators do |g|
        g.test_framework :rspec
        g.fixture_replacement :factory_bot
        g.factory_bot dir: "spec/factories"
      end

      # Adds the host app's app/agents directory to Rails autoload paths
      #
      # This allows agent classes defined in app/agents/ to be automatically
      # loaded without explicit requires. Must run before set_autoload_paths.
      #
      # @api private
      initializer "ruby_llm_agents.autoload_agents", before: :set_autoload_paths do |app|
        agents_path = app.root.join("app/agents")
        if agents_path.exist?
          Rails.autoloaders.main.push_dir(agents_path.to_s)
        end
      end
    end
  end
end
