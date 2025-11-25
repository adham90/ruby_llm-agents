# frozen_string_literal: true

Rails.application.routes.draw do
  # Mount ActionCable for WebSocket connections
  mount ActionCable.server => "/cable"

  # Mount the RubyLLM Agents dashboard
  mount RubyLLM::Agents::Engine => "/agents"
end
