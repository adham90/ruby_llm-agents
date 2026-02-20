# frozen_string_literal: true

module RubyLLM
  module Agents
    class Execution
      # Adds replay capability to execution records.
      #
      # Allows re-executing a previous run with the same inputs,
      # or with tweaked parameters for A/B testing and debugging.
      #
      # @example Replay with same settings
      #   run = SupportAgent.last_run
      #   new_run = run.replay
      #
      # @example Replay with different model
      #   run.replay(model: "claude-sonnet-4-6")
      #
      # @example Compare two models
      #   run1 = SupportAgent.last_run
      #   run2 = run1.replay(model: "gpt-4o-mini")
      #   puts "Original: #{run1.total_cost} | Replay: #{run2.total_cost}"
      #
      module Replayable
        extend ActiveSupport::Concern

        # Re-executes this agent run with the same (or overridden) inputs.
        #
        # Loads the original agent class, reconstructs its parameters from
        # the execution detail record, and executes through the full pipeline.
        # The new execution is tracked separately and linked via metadata.
        #
        # @param model [String, nil] Override the model
        # @param temperature [Float, nil] Override the temperature
        # @param overrides [Hash] Additional parameter overrides
        # @return [Object] The result from the new execution
        #
        # @raise [ReplayError] If the agent class cannot be resolved or detail is missing
        #
        def replay(model: nil, temperature: nil, **overrides)
          validate_replayable!
          agent_klass = resolve_agent_class
          params = build_replay_params(overrides)

          opts = params.merge(_replay_source_id: id)
          opts[:model] = model if model
          opts[:temperature] = temperature if temperature

          agent_klass.call(**opts)
        end

        # Returns whether this execution can be replayed.
        #
        # @return [Boolean]
        #
        def replayable?
          return false if agent_type.blank?
          return false if detail.nil?

          resolve_agent_class
          true
        rescue
          false
        end

        # Returns all executions that are replays of this one.
        #
        # @return [ActiveRecord::Relation]
        #
        def replays
          self.class.replays_of(id)
        end

        # Returns the original execution this was replayed from.
        #
        # @return [RubyLLM::Agents::Execution, nil]
        #
        def replay_source
          source_id = metadata&.dig("replay_source_id")
          return nil unless source_id

          self.class.find_by(id: source_id)
        end

        # Returns whether this execution is a replay of another.
        #
        # @return [Boolean]
        #
        def replay?
          metadata&.dig("replay_source_id").present?
        end

        private

        def validate_replayable!
          if agent_type.blank?
            raise ReplayError, "Cannot replay: execution has no agent_type"
          end

          if detail.nil?
            raise ReplayError,
              "Cannot replay execution ##{id}: no detail record " \
              "(prompts and parameters are required for replay)"
          end

          resolve_agent_class
        end

        def resolve_agent_class
          agent_type.constantize
        rescue NameError => e
          raise ReplayError,
            "Cannot replay execution ##{id}: agent class '#{agent_type}' " \
            "not found (#{e.message})"
        end

        def build_replay_params(overrides)
          original_params = detail.parameters || {}
          symbolized = original_params.transform_keys(&:to_sym)
          symbolized.merge(overrides)
        end
      end
    end
  end
end
