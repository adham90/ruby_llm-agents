# frozen_string_literal: true

RubyLLM::Agents::Engine.routes.draw do
  root to: "dashboard#index"

  resources :executions, only: [:index, :show] do
    collection do
      get :search
    end
  end
end
