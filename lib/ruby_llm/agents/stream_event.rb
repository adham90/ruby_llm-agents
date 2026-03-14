# frozen_string_literal: true

module RubyLLM
  module Agents
    # Typed event emitted during streaming execution.
    #
    # When `stream_events: true` is passed to an agent call, the stream
    # block receives StreamEvent objects instead of raw RubyLLM chunks.
    # This provides visibility into the full execution lifecycle —
    # text chunks, tool invocations, and errors.
    #
    # @example Basic usage
    #   MyAgent.call(query: "test", stream_events: true) do |event|
    #     case event.type
    #     when :chunk       then print event.data[:content]
    #     when :tool_start  then puts "Running #{event.data[:tool_name]}..."
    #     when :tool_end    then puts "Done (#{event.data[:duration_ms]}ms)"
    #     when :error       then puts "Error: #{event.data[:message]}"
    #     end
    #   end
    #
    class StreamEvent
      # @return [Symbol] Event type (:chunk, :tool_start, :tool_end, :error)
      attr_reader :type

      # @return [Hash] Event-specific data
      attr_reader :data

      # Creates a new StreamEvent
      #
      # @param type [Symbol] The event type
      # @param data [Hash] Event-specific data
      def initialize(type, data = {})
        @type = type
        @data = data
      end

      # @return [Boolean] Whether this is a text chunk event
      def chunk?
        @type == :chunk
      end

      # @return [Boolean] Whether this is a tool lifecycle event
      def tool_event?
        @type == :tool_start || @type == :tool_end
      end

      # @return [Boolean] Whether this is an error event
      def error?
        @type == :error
      end

      def to_h
        {type: @type, data: @data}
      end
    end
  end
end
