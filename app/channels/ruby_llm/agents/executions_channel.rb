# frozen_string_literal: true

module RubyLLM
  module Agents
    # ActionCable channel for real-time execution updates
    #
    # Broadcasts execution create/update events to subscribed clients.
    # Used by the dashboard to show live execution status changes.
    #
    # Inherits from the host app's ApplicationCable::Channel (note the :: prefix)
    #
    class ExecutionsChannel < ::ApplicationCable::Channel
      def subscribed
        stream_from "ruby_llm_agents:executions"
        logger.info "[RubyLLM::Agents] Client subscribed to executions channel"
      end

      def unsubscribed
        logger.info "[RubyLLM::Agents] Client unsubscribed from executions channel"
      end
    end
  end
end
