# frozen_string_literal: true

module RubyLLM
  module Agents
    # ActionCable channel for real-time execution updates
    #
    # Broadcasts execution create/update events to subscribed clients.
    # Used by the dashboard to show live execution status changes.
    #
    # Inherits from the host app's ApplicationCable::Channel (note the :: prefix
    # to reference the root namespace, not the engine's namespace).
    #
    # @example JavaScript subscription
    #   import { createConsumer } from "@rails/actioncable"
    #   const consumer = createConsumer()
    #   consumer.subscriptions.create("RubyLLM::Agents::ExecutionsChannel", {
    #     received(data) {
    #       console.log("Execution update:", data)
    #     }
    #   })
    #
    # @see Execution#broadcast_execution Broadcast trigger
    # @api private
    class ExecutionsChannel < ::ApplicationCable::Channel
      # Subscribes the client to the executions broadcast stream
      #
      # Called automatically when a client connects to this channel.
      # Streams from the "ruby_llm_agents:executions" channel name.
      #
      # @return [void]
      def subscribed
        stream_from "ruby_llm_agents:executions"
        logger.info "[RubyLLM::Agents] Client subscribed to executions channel"
      end

      # Cleans up when a client disconnects
      #
      # Called automatically when the WebSocket connection is closed.
      #
      # @return [void]
      def unsubscribed
        logger.info "[RubyLLM::Agents] Client unsubscribed from executions channel"
      end
    end
  end
end
