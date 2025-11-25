# frozen_string_literal: true

module RubyLLM
  module Agents
    module ApplicationHelper
      include Chartkick::Helper if defined?(Chartkick)

      def ruby_llm_agents
        RubyLLM::Agents::Engine.routes.url_helpers
      end
    end
  end
end
