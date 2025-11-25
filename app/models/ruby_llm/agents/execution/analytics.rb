# frozen_string_literal: true

module RubyLLM
  module Agents
    class Execution
      # Analytics concern for advanced reporting and analysis
      #
      # Provides class methods for:
      # - Daily reports with key metrics
      # - Cost breakdown by agent type
      # - Performance stats for specific agents
      # - Version comparison
      # - Trend analysis over time
      #
      module Analytics
        extend ActiveSupport::Concern

        class_methods do
          # Daily report with key metrics
          def daily_report
            scope = today

            {
              date: Date.current,
              total_executions: scope.count,
              successful: scope.successful.count,
              failed: scope.failed.count,
              total_cost: scope.total_cost_sum || 0,
              total_tokens: scope.total_tokens_sum || 0,
              avg_duration_ms: scope.avg_duration&.round || 0,
              avg_tokens: scope.avg_tokens&.round || 0,
              error_rate: calculate_error_rate(scope),
              by_agent: scope.group(:agent_type).count,
              top_errors: scope.errors.group(:error_class).count.sort_by { |_, v| -v }.first(5).to_h
            }
          end

          # Cost breakdown by agent type
          def cost_by_agent(period: :today)
            public_send(period)
              .group(:agent_type)
              .sum(:total_cost)
              .sort_by { |_, cost| -(cost || 0) }
              .to_h
          end

          # Performance stats for specific agent
          def stats_for(agent_type, period: :today)
            scope = by_agent(agent_type).public_send(period)
            count = scope.count
            total_cost = scope.total_cost_sum || 0

            {
              agent_type: agent_type,
              period: period,
              count: count,
              total_cost: total_cost,
              avg_cost: count > 0 ? (total_cost / count).round(6) : 0,
              total_tokens: scope.total_tokens_sum || 0,
              avg_tokens: scope.avg_tokens&.round || 0,
              avg_duration_ms: scope.avg_duration&.round || 0,
              success_rate: calculate_success_rate(scope),
              error_rate: calculate_error_rate(scope)
            }
          end

          # Compare versions of the same agent
          def compare_versions(agent_type, version1, version2, period: :this_week)
            base_scope = by_agent(agent_type).public_send(period)

            v1_stats = stats_for_scope(base_scope.by_version(version1))
            v2_stats = stats_for_scope(base_scope.by_version(version2))

            {
              agent_type: agent_type,
              period: period,
              version1: { version: version1, **v1_stats },
              version2: { version: version2, **v2_stats },
              improvements: {
                cost_change_pct: percent_change(v1_stats[:avg_cost], v2_stats[:avg_cost]),
                token_change_pct: percent_change(v1_stats[:avg_tokens], v2_stats[:avg_tokens]),
                speed_change_pct: percent_change(v1_stats[:avg_duration_ms], v2_stats[:avg_duration_ms])
              }
            }
          end

          # Trend analysis over time
          def trend_analysis(agent_type: nil, days: 7)
            scope = agent_type ? by_agent(agent_type) : all

            (0...days).map do |days_ago|
              date = days_ago.days.ago.to_date
              day_scope = scope.where(created_at: date.beginning_of_day..date.end_of_day)

              {
                date: date,
                count: day_scope.count,
                total_cost: day_scope.total_cost_sum || 0,
                avg_duration_ms: day_scope.avg_duration&.round || 0,
                error_count: day_scope.failed.count
              }
            end.reverse
          end

          private

          def calculate_success_rate(scope)
            total = scope.count
            return 0.0 if total.zero?
            (scope.successful.count.to_f / total * 100).round(2)
          end

          def calculate_error_rate(scope)
            total = scope.count
            return 0.0 if total.zero?
            (scope.failed.count.to_f / total * 100).round(2)
          end

          def stats_for_scope(scope)
            count = scope.count
            total_cost = scope.total_cost_sum || 0

            {
              count: count,
              total_cost: total_cost,
              avg_cost: count > 0 ? (total_cost / count).round(6) : 0,
              avg_tokens: scope.avg_tokens&.round || 0,
              avg_duration_ms: scope.avg_duration&.round || 0,
              success_rate: calculate_success_rate(scope)
            }
          end

          def percent_change(old_value, new_value)
            return 0.0 if old_value.nil? || old_value.zero?
            ((new_value - old_value).to_f / old_value * 100).round(2)
          end
        end
      end
    end
  end
end
