# frozen_string_literal: true

module RubyLLM
  module Agents
    class Execution
      # Analytics concern for advanced reporting and analysis
      #
      # Provides class methods for generating reports, analyzing trends,
      # comparing versions, and building chart data.
      #
      # @see RubyLLM::Agents::Execution::Scopes
      # @api public
      module Analytics
        extend ActiveSupport::Concern

        class_methods do
          # Generates a daily report with key metrics for today
          #
          # @return [Hash] Report containing:
          #   - :date [Date] Current date
          #   - :total_executions [Integer] Total execution count
          #   - :successful [Integer] Successful execution count
          #   - :failed [Integer] Failed execution count
          #   - :total_cost [Float] Sum of all costs
          #   - :total_tokens [Integer] Sum of all tokens
          #   - :avg_duration_ms [Integer] Average duration
          #   - :error_rate [Float] Percentage of failures
          #   - :by_agent [Hash] Counts grouped by agent type
          #   - :top_errors [Hash] Top 5 error classes
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

          # Returns cost breakdown grouped by agent type
          #
          # @param period [Symbol] Time scope (:today, :this_week, :this_month, :all_time)
          # @return [Hash{String => Float}] Agent types mapped to total cost, sorted descending
          def cost_by_agent(period: :today)
            public_send(period)
              .group(:agent_type)
              .sum(:total_cost)
              .sort_by { |_, cost| -(cost || 0) }
              .to_h
          end

          # Returns performance statistics for a specific agent
          #
          # @param agent_type [String] The agent class name
          # @param period [Symbol] Time scope (:today, :this_week, :this_month, :all_time)
          # @return [Hash] Statistics including count, costs, tokens, duration, rates
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

          # Compares performance between two agent versions
          #
          # @param agent_type [String] The agent class name
          # @param version1 [String] First version to compare (baseline)
          # @param version2 [String] Second version to compare
          # @param period [Symbol] Time scope for comparison
          # @return [Hash] Comparison data with stats for each version and improvement percentages
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

          # Analyzes trends over a time period
          #
          # @param agent_type [String, nil] Filter to specific agent, or nil for all
          # @param days [Integer] Number of days to analyze
          # @return [Array<Hash>] Daily metrics sorted oldest to newest
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

          # Builds hourly activity chart data for today
          #
          # Cached for 5 minutes to reduce database load.
          #
          # @return [Array<Hash>] Chart series with success and failed counts per hour
          def hourly_activity_chart
            cache_key = "ruby_llm_agents/hourly_activity/#{Date.current}"
            Rails.cache.fetch(cache_key, expires_in: 5.minutes) do
              build_hourly_activity_data
            end
          end

          # Builds the hourly activity data structure (uncached)
          #
          # @return [Array<Hash>] Success and failed series data
          # @api private
          def build_hourly_activity_data
            success_data = {}
            failed_data = {}

            # Create entries for each hour of the day (0-23)
            (0..23).each do |hour|
              time_label = format("%02d:00", hour)
              start_time = Time.current.beginning_of_day + hour.hours
              end_time = start_time + 1.hour

              hour_scope = where(created_at: start_time...end_time)
              total = hour_scope.count
              failed = hour_scope.failed.count

              success_data[time_label] = total - failed
              failed_data[time_label] = failed
            end

            [
              { name: "Success", data: success_data },
              { name: "Failed", data: failed_data }
            ]
          end

          private

          # Calculates success rate percentage for a scope
          #
          # @param scope [ActiveRecord::Relation] The scope to calculate from
          # @return [Float] Success rate as percentage (0.0-100.0)
          def calculate_success_rate(scope)
            total = scope.count
            return 0.0 if total.zero?
            (scope.successful.count.to_f / total * 100).round(2)
          end

          # Calculates error rate percentage for a scope
          #
          # @param scope [ActiveRecord::Relation] The scope to calculate from
          # @return [Float] Error rate as percentage (0.0-100.0)
          def calculate_error_rate(scope)
            total = scope.count
            return 0.0 if total.zero?
            (scope.failed.count.to_f / total * 100).round(2)
          end

          # Calculates statistics for an arbitrary scope
          #
          # @param scope [ActiveRecord::Relation] The scope to analyze
          # @return [Hash] Statistics hash
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

          # Calculates percentage change between two values
          #
          # @param old_value [Numeric, nil] Baseline value
          # @param new_value [Numeric] New value
          # @return [Float] Percentage change (negative = improvement for costs/duration)
          def percent_change(old_value, new_value)
            return 0.0 if old_value.nil? || old_value.zero?
            ((new_value - old_value).to_f / old_value * 100).round(2)
          end
        end
      end
    end
  end
end
