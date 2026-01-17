# frozen_string_literal: true

RubyLLM::Agents::Engine.routes.draw do
  root to: "dashboard#index"
  get "chart_data", to: "dashboard#chart_data"

  resources :agents, only: [:index, :show]

  resources :executions, only: [:index, :show] do
    collection do
      get :search
      get :export
    end
    member do
      post :rerun
    end
  end

  resources :tenants, only: [:index, :show, :edit, :update]

  # Global API Configuration
  resource :api_configuration, only: [:show, :edit, :update]

  # Tenant API Configurations
  get "tenants/:tenant_id/api_configuration", to: "api_configurations#tenant", as: :tenant_api_configuration
  get "tenants/:tenant_id/api_configuration/edit", to: "api_configurations#edit_tenant", as: :edit_tenant_api_configuration
  patch "tenants/:tenant_id/api_configuration", to: "api_configurations#update_tenant"
  post "api_configuration/test_connection", to: "api_configurations#test_connection", as: :test_api_connection

  # Redirect old analytics route to dashboard
  get "analytics", to: redirect("/")
  resource :system_config, only: [:show], controller: "system_config"
end
