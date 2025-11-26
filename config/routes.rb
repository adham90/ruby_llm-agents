# frozen_string_literal: true

RubyLLM::Agents::Engine.routes.draw do
  root to: "dashboard#index"

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

  resource :settings, only: [:show]
end
