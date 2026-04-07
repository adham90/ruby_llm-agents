# frozen_string_literal: true

RubyLLM::Agents::Engine.routes.draw do
  root to: "dashboard#index"
  get "chart_data", to: "dashboard#chart_data"

  resources :agents, only: [:index, :show, :update] do
    member do
      delete :reset_overrides
    end
  end

  resources :executions, only: [:index, :show] do
    collection do
      get :search
      get :export
    end
  end

  resources :requests, only: [:index, :show]

  resources :tenants, only: [:index, :show, :edit, :update] do
    member do
      post :refresh_counters
    end
  end

  get "analytics", to: "analytics#index", as: :analytics
  get "analytics/chart_data", to: "analytics#chart_data", as: :analytics_chart_data
  resource :system_config, only: [:show], controller: "system_config"
end
