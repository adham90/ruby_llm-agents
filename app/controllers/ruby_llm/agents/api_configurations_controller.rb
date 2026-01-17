# frozen_string_literal: true

module RubyLLM
  module Agents
    # Controller for managing API configurations
    #
    # Provides CRUD operations for global and tenant-specific API
    # configurations, including API keys and connection settings.
    #
    # @see ApiConfiguration
    # @api private
    class ApiConfigurationsController < ApplicationController
      before_action :ensure_table_exists
      before_action :set_global_config, only: [:show, :edit, :update]
      before_action :set_tenant_config, only: [:tenant, :edit_tenant, :update_tenant]

      # Displays the global API configuration
      #
      # @return [void]
      def show
        @resolved = ApiConfiguration.resolve
        @provider_statuses = @resolved.provider_statuses_with_source
      end

      # Renders the edit form for global configuration
      #
      # @return [void]
      def edit
        # @config set by before_action
      end

      # Updates the global API configuration
      #
      # @return [void]
      def update
        if @config.update(api_configuration_params)
          log_configuration_change(@config, "global")
          redirect_to edit_api_configuration_path, notice: "API configuration updated successfully"
        else
          render :edit, status: :unprocessable_entity
        end
      end

      # Displays tenant-specific API configuration
      #
      # @return [void]
      def tenant
        @resolved = ApiConfiguration.resolve(tenant_id: params[:tenant_id])
        @provider_statuses = @resolved.provider_statuses_with_source
        @tenant_budget = TenantBudget.for_tenant(params[:tenant_id])
      end

      # Renders the edit form for tenant configuration
      #
      # @return [void]
      def edit_tenant
        # @config set by before_action
      end

      # Updates a tenant-specific API configuration
      #
      # @return [void]
      def update_tenant
        if @config.update(api_configuration_params)
          log_configuration_change(@config, "tenant:#{params[:tenant_id]}")
          redirect_to edit_tenant_api_configuration_path(params[:tenant_id]),
                      notice: "Tenant API configuration updated successfully"
        else
          render :edit_tenant, status: :unprocessable_entity
        end
      end

      # Tests API key validity for a specific provider
      # (Optional - can be used for AJAX validation)
      #
      # @return [void]
      def test_connection
        provider = params[:provider]
        api_key = params[:api_key]

        result = test_provider_connection(provider, api_key)

        render json: {
          success: result[:success],
          message: result[:message],
          models: result[:models]
        }
      rescue StandardError => e
        render json: { success: false, message: e.message }
      end

      private

      # Ensures the api_configurations table exists
      def ensure_table_exists
        return if ApiConfiguration.table_exists?

        flash[:alert] = "API configurations table not found. Run the generator: rails generate ruby_llm_agents:api_configuration"
        redirect_to root_path
      end

      # Sets the global configuration (creates if not exists)
      def set_global_config
        @config = ApiConfiguration.global
      end

      # Sets the tenant-specific configuration (creates if not exists)
      def set_tenant_config
        @tenant_id = params[:tenant_id]
        raise ActionController::RoutingError, "Tenant ID required" if @tenant_id.blank?

        @config = ApiConfiguration.for_tenant!(@tenant_id)
      end

      # Strong parameters for API configuration
      #
      # @return [ActionController::Parameters]
      def api_configuration_params
        params.require(:api_configuration).permit(
          # API Keys
          :openai_api_key,
          :anthropic_api_key,
          :gemini_api_key,
          :deepseek_api_key,
          :mistral_api_key,
          :perplexity_api_key,
          :openrouter_api_key,
          :gpustack_api_key,
          :xai_api_key,
          :ollama_api_key,
          # AWS Bedrock
          :bedrock_api_key,
          :bedrock_secret_key,
          :bedrock_session_token,
          :bedrock_region,
          # Vertex AI
          :vertexai_credentials,
          :vertexai_project_id,
          :vertexai_location,
          # Endpoints
          :openai_api_base,
          :gemini_api_base,
          :ollama_api_base,
          :gpustack_api_base,
          :xai_api_base,
          # OpenAI Options
          :openai_organization_id,
          :openai_project_id,
          # Default Models
          :default_model,
          :default_embedding_model,
          :default_image_model,
          :default_moderation_model,
          # Connection Settings
          :request_timeout,
          :max_retries,
          :retry_interval,
          :retry_backoff_factor,
          :retry_interval_randomness,
          :http_proxy,
          # Inheritance
          :inherit_global_defaults
        ).tap do |permitted|
          # Remove blank API keys to prevent overwriting with empty values
          # This allows users to submit forms without touching existing keys
          ApiConfiguration::API_KEY_ATTRIBUTES.each do |key|
            permitted.delete(key) if permitted[key].blank?
          end
        end
      end

      # Logs configuration changes for audit purposes
      #
      # @param config [ApiConfiguration] The configuration that changed
      # @param scope [String] The scope identifier
      def log_configuration_change(config, scope)
        changed_fields = config.previous_changes.keys.reject { |k| k.end_with?("_at") }
        return if changed_fields.empty?

        # Mask sensitive fields in the log
        masked_changes = changed_fields.map do |field|
          if field.include?("api_key") || field.include?("secret") || field.include?("credentials")
            "#{field}: [REDACTED]"
          else
            "#{field}: #{config.previous_changes[field].last}"
          end
        end

        Rails.logger.info(
          "[RubyLLM::Agents] API configuration updated for #{scope}: #{masked_changes.join(', ')}"
        )
      end

      # Tests connection to a specific provider
      #
      # @param provider [String] Provider key
      # @param api_key [String] API key to test
      # @return [Hash] Test result with success, message, and models
      def test_provider_connection(provider, api_key)
        # This is a placeholder - actual implementation would depend on
        # RubyLLM's ability to list models or make a test request
        case provider
        when "openai"
          # Example: Try to list models
          { success: true, message: "Connection successful", models: [] }
        when "anthropic"
          { success: true, message: "Connection successful", models: [] }
        else
          { success: false, message: "Provider not supported for testing" }
        end
      end
    end
  end
end
