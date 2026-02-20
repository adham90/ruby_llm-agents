# frozen_string_literal: true

module RubyLLM
  module Agents
    module DSL
      # Adds execution querying capabilities to agent classes.
      #
      # Mixed into BaseAgent via `extend DSL::Queryable`, making all methods
      # available as class methods on agent classes.
      #
      # @example Basic queries
      #   SupportAgent.executions.successful.recent
      #   SupportAgent.executions.today.expensive(0.50)
      #
      # @example Convenience methods
      #   SupportAgent.last_run
      #   SupportAgent.stats
      #   SupportAgent.total_spent(since: 1.week)
      #
      module Queryable
        # Returns an ActiveRecord::Relation scoped to this agent's executions.
        #
        # @return [ActiveRecord::Relation]
        #
        # @example
        #   SupportAgent.executions.successful.last(5)
        #   SupportAgent.executions.where("total_cost > ?", 0.01)
        #
        def executions
          RubyLLM::Agents::Execution.by_agent(name)
        end

        # Returns the most recent execution for this agent.
        #
        # @return [RubyLLM::Agents::Execution, nil]
        #
        def last_run
          executions.order(created_at: :desc).first
        end

        # Returns recent failed executions.
        #
        # @param since [ActiveSupport::Duration] Time window (default: 24.hours)
        # @return [ActiveRecord::Relation]
        #
        def failures(since: 24.hours)
          executions.failed.where("created_at > ?", since.ago)
        end

        # Returns total cost spent by this agent.
        #
        # @param since [ActiveSupport::Duration, nil] Optional time window
        # @return [BigDecimal] Total cost in USD
        #
        def total_spent(since: nil)
          scope = executions
          scope = scope.where("created_at > ?", since.ago) if since
          scope.sum(:total_cost)
        end

        # Returns a stats summary hash for this agent.
        #
        # @param since [ActiveSupport::Duration, nil] Time window
        # @return [Hash] Stats summary
        #
        def stats(since: nil)
          scope = executions
          scope = scope.where("created_at > ?", since.ago) if since

          total = scope.count
          successful = scope.successful.count

          {
            total: total,
            successful: successful,
            failed: scope.failed.count,
            success_rate: total.zero? ? 0.0 : (successful.to_f / total * 100).round(1),
            avg_duration_ms: scope.average(:duration_ms)&.round,
            avg_cost: total.zero? ? 0 : (scope.sum(:total_cost).to_f / total).round(6),
            total_cost: scope.sum(:total_cost),
            total_tokens: scope.sum(:total_tokens),
            avg_tokens: scope.average(:total_tokens)&.round
          }
        end

        # Returns cost breakdown by model for this agent.
        #
        # @param since [ActiveSupport::Duration, nil] Time window
        # @return [Hash{String => Hash}] Costs per model
        #
        def cost_by_model(since: nil)
          scope = executions
          scope = scope.where("created_at > ?", since.ago) if since

          scope.group(:model_id).pluck(
            :model_id,
            Arel.sql("COUNT(*)"),
            Arel.sql("SUM(total_cost)"),
            Arel.sql("AVG(total_cost)")
          ).each_with_object({}) do |(model, count, total, avg), hash|
            hash[model] = {
              count: count,
              total_cost: total&.to_f&.round(6) || 0,
              avg_cost: avg&.to_f&.round(6) || 0
            }
          end
        end

        # Returns executions matching specific parameter values.
        #
        # @param params [Hash] Parameter key-value pairs to match
        # @return [ActiveRecord::Relation]
        #
        def with_params(**params)
          scope = executions
          params.each do |key, value|
            scope = scope.with_parameter(key, value)
          end
          scope
        end
      end
    end
  end
end
