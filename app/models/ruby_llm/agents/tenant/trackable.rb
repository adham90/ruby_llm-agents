# frozen_string_literal: true

module RubyLLM
  module Agents
    class Tenant
      # Tracks LLM usage for a tenant including costs, tokens, and execution counts.
      #
      # Provides methods for querying usage data with various time periods:
      # - :today, :yesterday, :this_week, :last_week
      # - :this_month, :last_month
      # - Custom date ranges
      #
      # @example Querying costs
      #   tenant.cost                    # Total cost all time
      #   tenant.cost_today              # Today's cost
      #   tenant.cost_this_month         # This month's cost
      #   tenant.cost(period: 1.week.ago..Time.current)
      #
      # @example Usage summary
      #   tenant.usage_summary
      #   # => { tenant_id: "acme", cost: 123.45, tokens: 50000, executions: 100 }
      #
      # @example Usage breakdown
      #   tenant.usage_by_agent
      #   # => { "ChatAgent" => { cost: 50.0, tokens: 20000, count: 40 } }
      #
      # @see Execution
      # @api public
      module Trackable
        extend ActiveSupport::Concern

        included do
          # Association to executions via tenant_id
          has_many :executions,
                   class_name: "RubyLLM::Agents::Execution",
                   primary_key: :tenant_id,
                   foreign_key: :tenant_id,
                   inverse_of: false
        end

        # Cost queries

        # Returns total cost for the given period
        #
        # @param period [Symbol, Range, nil] Time period (:today, :this_month, etc.) or date range
        # @return [Float] Total cost in USD
        def cost(period: nil)
          scope = executions
          scope = apply_period_scope(scope, period) if period
          scope.sum(:total_cost) || 0
        end

        # Returns today's cost from counter columns
        #
        # @return [Float]
        def cost_today
          ensure_daily_reset!
          daily_cost_spent
        end

        # Returns yesterday's cost
        #
        # @return [Float]
        def cost_yesterday
          cost(period: :yesterday)
        end

        # Returns this week's cost
        #
        # @return [Float]
        def cost_this_week
          cost(period: :this_week)
        end

        # Returns last week's cost
        #
        # @return [Float]
        def cost_last_week
          cost(period: :last_week)
        end

        # Returns this month's cost from counter columns
        #
        # @return [Float]
        def cost_this_month
          ensure_monthly_reset!
          monthly_cost_spent
        end

        # Returns last month's cost
        #
        # @return [Float]
        def cost_last_month
          cost(period: :last_month)
        end

        # Token queries

        # Returns total tokens for the given period
        #
        # @param period [Symbol, Range, nil] Time period or date range
        # @return [Integer] Total tokens
        def tokens(period: nil)
          scope = executions
          scope = apply_period_scope(scope, period) if period
          scope.sum(:total_tokens) || 0
        end

        # Returns today's token usage from counter columns
        #
        # @return [Integer]
        def tokens_today
          ensure_daily_reset!
          daily_tokens_used
        end

        # Returns yesterday's token usage
        #
        # @return [Integer]
        def tokens_yesterday
          tokens(period: :yesterday)
        end

        # Returns this week's token usage
        #
        # @return [Integer]
        def tokens_this_week
          tokens(period: :this_week)
        end

        # Returns this month's token usage from counter columns
        #
        # @return [Integer]
        def tokens_this_month
          ensure_monthly_reset!
          monthly_tokens_used
        end

        # Returns last month's token usage
        #
        # @return [Integer]
        def tokens_last_month
          tokens(period: :last_month)
        end

        # Execution count queries

        # Returns execution count for the given period
        #
        # @param period [Symbol, Range, nil] Time period or date range
        # @return [Integer] Execution count
        def execution_count(period: nil)
          scope = executions
          scope = apply_period_scope(scope, period) if period
          scope.count
        end

        # Returns today's execution count from counter columns
        #
        # @return [Integer]
        def executions_today
          ensure_daily_reset!
          daily_executions_count
        end

        # Returns yesterday's execution count
        #
        # @return [Integer]
        def executions_yesterday
          execution_count(period: :yesterday)
        end

        # Returns this week's execution count
        #
        # @return [Integer]
        def executions_this_week
          execution_count(period: :this_week)
        end

        # Returns this month's execution count from counter columns
        #
        # @return [Integer]
        def executions_this_month
          ensure_monthly_reset!
          monthly_executions_count
        end

        # Returns last month's execution count
        #
        # @return [Integer]
        def executions_last_month
          execution_count(period: :last_month)
        end

        # Error count queries

        # Returns today's error count from counter columns
        #
        # @return [Integer]
        def errors_today
          ensure_daily_reset!
          daily_error_count
        end

        # Returns this month's error count from counter columns
        #
        # @return [Integer]
        def errors_this_month
          ensure_monthly_reset!
          monthly_error_count
        end

        # Returns today's success rate from counter columns
        #
        # @return [Float] Percentage (0.0-100.0)
        def success_rate_today
          ensure_daily_reset!
          return 100.0 if daily_executions_count.zero?

          ((daily_executions_count - daily_error_count).to_f / daily_executions_count * 100).round(1)
        end

        # Usage summaries

        # Returns a complete usage summary for the tenant
        #
        # @param period [Symbol, Range] Time period (default: :this_month)
        # @return [Hash] Usage summary
        def usage_summary(period: :this_month)
          {
            tenant_id: tenant_id,
            name: display_name,
            period: period,
            cost: cost(period: period),
            tokens: tokens(period: period),
            executions: execution_count(period: period)
          }
        end

        # Returns usage broken down by agent type
        #
        # @param period [Symbol, Range] Time period (default: :this_month)
        # @return [Hash] Usage by agent { "AgentName" => { cost:, tokens:, count: } }
        def usage_by_agent(period: :this_month)
          scope = executions
          scope = apply_period_scope(scope, period) if period

          scope.group(:agent_type).pluck(
            :agent_type,
            Arel.sql("SUM(total_cost)"),
            Arel.sql("SUM(total_tokens)"),
            Arel.sql("COUNT(*)")
          ).to_h do |agent_type, total_cost, total_tokens, count|
            [agent_type, { cost: total_cost || 0, tokens: total_tokens || 0, count: count }]
          end
        end

        # Returns usage broken down by model
        #
        # @param period [Symbol, Range] Time period (default: :this_month)
        # @return [Hash] Usage by model { "model-id" => { cost:, tokens:, count: } }
        def usage_by_model(period: :this_month)
          scope = executions
          scope = apply_period_scope(scope, period) if period

          scope.group(:model_id).pluck(
            :model_id,
            Arel.sql("SUM(total_cost)"),
            Arel.sql("SUM(total_tokens)"),
            Arel.sql("COUNT(*)")
          ).to_h do |model_id, total_cost, total_tokens, count|
            [model_id, { cost: total_cost || 0, tokens: total_tokens || 0, count: count }]
          end
        end

        # Returns usage broken down by day for a given period
        #
        # @param period [Symbol, Range] Time period (default: :this_month)
        # @return [Hash] Daily usage { Date => { cost:, tokens:, count: } }
        def usage_by_day(period: :this_month)
          scope = executions
          scope = apply_period_scope(scope, period) if period

          scope.group("DATE(created_at)").pluck(
            Arel.sql("DATE(created_at)"),
            Arel.sql("SUM(total_cost)"),
            Arel.sql("SUM(total_tokens)"),
            Arel.sql("COUNT(*)")
          ).to_h do |date, total_cost, total_tokens, count|
            [date.to_date, { cost: total_cost || 0, tokens: total_tokens || 0, count: count }]
          end
        end

        # Returns the most recent executions for this tenant
        #
        # @param limit [Integer] Number of executions to return (default: 10)
        # @return [Array<Execution>]
        def recent_executions(limit: 10)
          executions.order(created_at: :desc).limit(limit)
        end

        # Returns failed executions for this tenant
        #
        # @param period [Symbol, Range, nil] Time period
        # @param limit [Integer, nil] Optional limit
        # @return [ActiveRecord::Relation]
        def failed_executions(period: nil, limit: nil)
          scope = executions.where(status: "error")
          scope = apply_period_scope(scope, period) if period
          scope = scope.limit(limit) if limit
          scope.order(created_at: :desc)
        end

        private

        # Applies time period scope to a query
        #
        # @param scope [ActiveRecord::Relation]
        # @param period [Symbol, Range]
        # @return [ActiveRecord::Relation]
        def apply_period_scope(scope, period)
          case period
          when :today
            scope.where(created_at: Time.current.all_day)
          when :yesterday
            scope.where(created_at: 1.day.ago.all_day)
          when :this_week
            scope.where(created_at: Time.current.all_week)
          when :last_week
            scope.where(created_at: 1.week.ago.all_week)
          when :this_month
            scope.where(created_at: Time.current.all_month)
          when :last_month
            scope.where(created_at: 1.month.ago.all_month)
          when Range
            scope.where(created_at: period)
          else
            scope
          end
        end
      end
    end
  end
end
