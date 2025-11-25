# frozen_string_literal: true

module RubyLLM
  module Agents
    module ApplicationHelper
      def ruby_llm_agents
        RubyLLM::Agents::Engine.routes.url_helpers
      end
    end
  end
end
