# frozen_string_literal: true

RubyLLM::Agents::Engine.routes.draw do
  root to: "dashboard#index"
  get "chart_data", to: "dashboard#chart_data"

  resources :agents, only: [:index, :show]
  resources :workflows, only: [:index, :show]

  resources :executions, only: [:index, :show] do
    collection do
      get :search
      get :export
    end
  end

  resources :tenants, only: [:index, :show, :edit, :update]

  # Redirect old analytics route to dashboard
  get "analytics", to: redirect("/")
  resource :system_config, only: [:show], controller: "system_config"
end
