# frozen_string_literal: true

Rails.application.routes.draw do
  mount RubyLLM::Agents::Engine => "/agents"
end
