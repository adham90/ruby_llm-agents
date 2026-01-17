# frozen_string_literal: true

module RubyLLM
  module Agents
    # Controller for displaying system configuration
    #
    # Shows all configuration options from RubyLLM::Agents.configuration
    # in a read-only dashboard view.
    #
    # @api private
    class SystemConfigController < ApplicationController
      # Displays the system configuration
      #
      # @return [void]
      def show
        @config = RubyLLM::Agents.configuration
      end
    end
  end
end
