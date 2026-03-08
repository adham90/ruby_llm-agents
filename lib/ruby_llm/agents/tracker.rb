# frozen_string_literal: true

module RubyLLM
  module Agents
    # Internal collector used by RubyLLM::Agents.track to accumulate
    # Result objects produced during a tracked block.
    #
    # Not part of the public API — users interact with TrackReport instead.
    #
    # @api private
    class Tracker
      attr_reader :results, :defaults, :request_id, :tags

      def initialize(defaults: {}, request_id: nil, tags: {})
        @results = []
        @defaults = defaults
        @request_id = request_id || generate_request_id
        @tags = tags
      end

      def <<(result)
        @results << result
      end

      private

      def generate_request_id
        "track_#{SecureRandom.hex(8)}"
      end
    end
  end
end
