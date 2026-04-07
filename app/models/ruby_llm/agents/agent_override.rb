# frozen_string_literal: true

module RubyLLM
  module Agents
    # Stores dashboard-managed overrides for agent settings.
    #
    # When an agent declares a field as `overridable: true` in its DSL,
    # the dashboard can persist an override value in this table. The DSL
    # getter merges the override on top of the code-defined default.
    #
    # Each row maps one agent class name to a JSON hash of overridden fields.
    #
    # @example
    #   AgentOverride.create!(
    #     agent_type: "SupportAgent",
    #     settings: { "model" => "claude-sonnet-4-5", "temperature" => 0.3 }
    #   )
    #
    # @see DSL::Base#resolve_override
    # @api private
    class AgentOverride < ::ActiveRecord::Base
      self.table_name = "ruby_llm_agents_overrides"

      validates :agent_type, presence: true, uniqueness: true

      after_save :bust_agent_cache
      after_destroy :bust_agent_cache

      # Returns the override value for a single field, or nil
      #
      # @param field [Symbol, String] The field name
      # @return [Object, nil] The override value
      def [](field)
        (settings || {})[field.to_s]
      end

      private

      # Clears the in-memory override cache on the agent class so the
      # next call picks up the new values.
      def bust_agent_cache
        klass = agent_type.safe_constantize
        klass&.clear_override_cache! if klass.respond_to?(:clear_override_cache!)
      end
    end
  end
end
