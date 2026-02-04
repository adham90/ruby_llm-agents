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
        require_relative "../infrastructure/execution_logger_job"
        require_relative "../core/instrumentation"
        require_relative "../core/base"
        require_relative "../workflow/orchestrator"

        # Resolve the parent controller class from configuration
        # Default is ActionController::Base, but can be set to inherit from app controllers
        parent_class = RubyLLM::Agents.configuration.dashboard_parent_controller.constantize

        # Remove existing constant to allow redefinition on configuration change
        # This is necessary for Rails reloading in development
        RubyLLM::Agents.send(:remove_const, :ApplicationController) if RubyLLM::Agents.const_defined?(:ApplicationController, false)

        # Define the ApplicationController dynamically with the configured parent
        RubyLLM::Agents.const_set(:ApplicationController, Class.new(parent_class) do
          # Prepend the engine's view path so templates are found correctly
          prepend_view_path RubyLLM::Agents::Engine.root.join("app/views")

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

          # Returns whether multi-tenancy filtering is enabled
          #
          # @return [Boolean] true if multi-tenancy is enabled
          # @api public
          def tenant_filter_enabled?
            RubyLLM::Agents.configuration.multi_tenancy_enabled?
          end
          helper_method :tenant_filter_enabled?

          # Returns the current tenant ID for filtering
          #
          # Priority:
          # 1. Explicit tenant_id param (for admin filtering)
          # 2. Resolved from tenant_resolver
          #
          # @return [String, nil] Current tenant identifier
          # @api public
          def current_tenant_id
            return @current_tenant_id if defined?(@current_tenant_id)

            @current_tenant_id = if params[:tenant_id].present?
              params[:tenant_id]
            else
              RubyLLM::Agents.configuration.current_tenant_id
            end
          end
          helper_method :current_tenant_id

          # Returns a tenant-scoped base query for executions
          #
          # If multi-tenancy is enabled and a tenant is selected,
          # returns executions filtered by that tenant.
          # Otherwise returns all executions.
          #
          # @return [ActiveRecord::Relation] Scoped executions
          # @api public
          def tenant_scoped_executions
            if tenant_filter_enabled? && current_tenant_id.present?
              RubyLLM::Agents::Execution.by_tenant(current_tenant_id)
            else
              RubyLLM::Agents::Execution.all
            end
          end
          helper_method :tenant_scoped_executions

          # Returns list of available tenants for filtering dropdown
          #
          # @return [Array<String>] Unique tenant IDs from executions
          # @api public
          def available_tenants
            return @available_tenants if defined?(@available_tenants)

            @available_tenants = RubyLLM::Agents::Execution
              .where.not(tenant_id: nil)
              .distinct
              .pluck(:tenant_id)
              .sort
          end
          helper_method :available_tenants
        end)
      end

      # Load rake tasks from lib/tasks
      rake_tasks do
        tasks_path = File.expand_path("../../../tasks", __dir__)
        Dir[File.join(tasks_path, "**", "*.rake")].each { |f| load f }
      end

      # Configures default generators for the engine
      # Sets up RSpec and FactoryBot for generated specs
      # @api private
      config.generators do |g|
        g.test_framework :rspec
        g.fixture_replacement :factory_bot
        g.factory_bot dir: "spec/factories"
      end

      # Adds the host app's agent directories to Rails autoload paths
      #
      # This allows agent classes and other components defined in app/agents/
      # to be automatically loaded without explicit requires.
      #
      # Supports subdirectory namespacing:
      # - app/agents/ (top-level, no namespace)
      # - app/agents/embedders/ -> Embedders namespace
      # - app/agents/images/ -> Images namespace
      # - app/workflows/ (top-level, no namespace)
      #
      # @api private
      initializer "ruby_llm_agents.autoload_agents", before: :set_autoload_paths do |app|
        config = RubyLLM::Agents.configuration

        # Check for new grouped structure (app/llm/*)
        root_path = app.root.join("app", config.root_directory)
        if root_path.exist?
          # Add each configured path that exists
          config.all_autoload_paths.each do |relative_path|
            full_path = app.root.join(relative_path)
            if full_path.exist?
              # Configure namespace for the path
              namespace = self.class.namespace_for_path(relative_path, config)
              if namespace
                Rails.autoloaders.main.push_dir(full_path.to_s, namespace: namespace)
              else
                Rails.autoloaders.main.push_dir(full_path.to_s)
              end
            end
          end
        else
          # Fallback to legacy flat structure (app/agents/)
          agents_path = app.root.join("app/agents")
          if agents_path.exist?
            Rails.autoloaders.main.push_dir(agents_path.to_s)
          end
        end
      end

      # Determines the namespace constant for a given path
      #
      # @param path [String] Relative path like "app/agents/embedders"
      # @param config [Configuration] Current configuration
      # @return [Module, nil] Namespace module or nil for top-level
      # @api private
      def self.namespace_for_path(path, config)
        parts = path.split("/")

        # app/workflows -> no namespace (top-level workflows)
        return nil if parts == ["app", "workflows"]

        # Need at least app/{root_directory}
        return nil unless parts.length >= 2 && parts[0] == "app"
        return nil unless parts[1] == config.root_directory

        # app/agents -> no namespace (root level)
        return nil if parts.length == 2

        # app/agents/embedders -> Embedders namespace
        subdirectory = parts[2]
        namespace_name = if config.root_namespace.blank?
          subdirectory.camelize
        else
          "#{config.root_namespace}::#{subdirectory.camelize}"
        end

        # Create the namespace module if needed
        namespace_name.constantize
      rescue NameError
        namespace_name.split("::").inject(Object) do |mod, name|
          mod.const_defined?(name, false) ? mod.const_get(name) : mod.const_set(name, Module.new)
        end
      end
    end
  end
end
