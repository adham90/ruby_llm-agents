# frozen_string_literal: true

module RubyLLM
  module Agents
    # Controller for displaying global configuration settings
    #
    # Shows all configuration options from RubyLLM::Agents.configuration
    # in a read-only dashboard view.
    #
    # @api private
    class SettingsController < ApplicationController
      # Displays the global configuration settings
      #
      # @return [void]
      def show
        @config = RubyLLM::Agents.configuration
      end
    end
  end
end
