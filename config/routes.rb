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

  resource :analytics, only: [:show]
  resource :settings, only: [:show]
end
