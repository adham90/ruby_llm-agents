# frozen_string_literal: true

module RubyLLM
  module Agents
    # Mixin that registers a result object with the active Tracker.
    #
    # Included in every result class so that RubyLLM::Agents.track
    # can collect results automatically.
    #
    # @api private
    module Trackable
      def self.included(base)
        base.attr_reader :agent_class_name unless base.method_defined?(:agent_class_name)
      end

      private

      # Call from the end of initialize to register with the active tracker
      def register_with_tracker
        tracker = Thread.current[:ruby_llm_agents_tracker]
        tracker << self if tracker
      end
    end
  end
end
