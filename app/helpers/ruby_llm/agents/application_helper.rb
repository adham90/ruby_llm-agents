# frozen_string_literal: true

module RubyLLM
  module Agents
    module ApplicationHelper
      include Chartkick::Helper if defined?(Chartkick)

      def ruby_llm_agents
        RubyLLM::Agents::Engine.routes.url_helpers
      end

      def number_to_human_short(number, prefix: nil, precision: 1)
        return "#{prefix}0" if number.nil? || number.zero?

        abs_number = number.to_f.abs
        formatted = if abs_number >= 1_000_000_000
          "#{(number / 1_000_000_000.0).round(precision)}B"
        elsif abs_number >= 1_000_000
          "#{(number / 1_000_000.0).round(precision)}M"
        elsif abs_number >= 1_000
          "#{(number / 1_000.0).round(precision)}K"
        elsif abs_number < 1 && abs_number > 0
          number.round(precision + 3).to_s
        else
          number.round(precision).to_s
        end

        "#{prefix}#{formatted}"
      end
    end
  end
end
