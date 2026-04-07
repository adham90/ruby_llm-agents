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

            # Single aggregated query for core metrics
            total, successful, failed, cost, tokens, avg_dur, avg_tok = scope.pick(
              Arel.sql("COUNT(*)"),
              Arel.sql("SUM(CASE WHEN status = 'success' THEN 1 ELSE 0 END)"),
              Arel.sql("SUM(CASE WHEN status IN ('error','timeout') THEN 1 ELSE 0 END)"),
              Arel.sql("COALESCE(SUM(total_cost), 0)"),
              Arel.sql("COALESCE(SUM(total_tokens), 0)"),
              Arel.sql("AVG(duration_ms)"),
              Arel.sql("AVG(total_tokens)")
            )

            total = total.to_i
            successful = successful.to_i
            failed = failed.to_i

            {
              date: Date.current,
              total_executions: total,
              successful: successful,
              failed: failed,
              total_cost: cost.to_f,
              total_tokens: tokens.to_i,
              avg_duration_ms: avg_dur.to_i,
              avg_tokens: avg_tok.to_i,
              error_rate: (total > 0) ? (failed.to_f / total * 100).round(2) : 0.0,
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
              avg_cost: (count > 0) ? (total_cost / count).round(6) : 0,
              total_tokens: scope.total_tokens_sum || 0,
              avg_tokens: scope.avg_tokens&.round || 0,
              avg_duration_ms: scope.avg_duration&.round || 0,
              success_rate: calculate_success_rate(scope),
              error_rate: calculate_error_rate(scope)
            }
          end

          # Compares performance between two agent versions
          # Analyzes trends over a time period
          #
          # @param agent_type [String, nil] Filter to specific agent, or nil for all
          # @param days [Integer] Number of days to analyze
          # @return [Array<Hash>] Daily metrics sorted oldest to newest
          def trend_analysis(agent_type: nil, days: 7)
            scope = agent_type ? by_agent(agent_type) : all
            end_date = Date.current
            start_date = end_date - (days - 1).days

            time_scope = scope.where(created_at: start_date.beginning_of_day..end_date.end_of_day)
            results = aggregated_chart_query(time_scope, granularity: :day)

            (0...days).map do |i|
              date = start_date + i.days
              key = date.to_s
              row = results[key] || {success: 0, failed: 0, cost: 0.0, duration: 0, tokens: 0}

              {
                date: date,
                count: row[:success] + row[:failed],
                total_cost: row[:cost],
                avg_duration_ms: row[:duration],
                error_count: row[:failed]
              }
            end
          end

          # Builds hourly activity chart data for today
          #
          # Cached for 5 minutes to reduce database load.
          #
          # @return [Array<Hash>] Chart series with success and failed counts per hour
          def hourly_activity_chart
            # No caching - always fresh data based on latest execution
            build_hourly_activity_data
          end

          # Returns chart data as arrays for Highcharts live updates
          # Format: { categories: [...], series: [...], range: ... }
          #
          # @param range [String] Time range: "today" (hourly), "7d", "30d", "60d", or "90d" (daily)
          # @param offset_days [Integer, nil] Optional offset for comparison data (shifts time window back)
          def activity_chart_json(range: "today", offset_days: nil)
            case range
            when "7d"
              build_daily_chart_data(7, offset_days: offset_days)
            when "30d"
              build_daily_chart_data(30, offset_days: offset_days)
            when "60d"
              build_daily_chart_data(60, offset_days: offset_days)
            when "90d"
              build_daily_chart_data(90, offset_days: offset_days)
            else
              build_hourly_chart_data(offset_days: offset_days)
            end
          end

          # Returns chart data for a custom date range
          # Format: { categories: [...], series: [...], range: ... }
          #
          # @param from [Date] Start date (inclusive)
          # @param to [Date] End date (inclusive)
          # @return [Hash] Chart data with series arrays
          def activity_chart_json_for_dates(from:, to:)
            build_daily_chart_data_for_dates(from, to)
          end

          # Alias for backwards compatibility
          def hourly_activity_chart_json
            activity_chart_json(range: "today")
          end

          private

          # Builds hourly chart data for last 24 hours
          # Optimized: Single SQL GROUP BY with conditional aggregation
          # Database-agnostic: works with both PostgreSQL and SQLite
          #
          # @param offset_days [Integer, nil] Optional offset for comparison data
          def build_hourly_chart_data(offset_days: nil)
            offset = offset_days ? offset_days.days : 0.days
            reference_time = (Time.current - offset).beginning_of_hour
            start_time = reference_time - 23.hours

            scope = where(created_at: start_time..(reference_time + 1.hour))
            results = aggregated_chart_query(scope, granularity: :hour)

            success_data = []
            failed_data = []
            cost_data = []
            duration_data = []
            tokens_data = []
            total_success = 0
            total_failed = 0
            total_cost = 0.0
            total_duration_sum = 0
            total_duration_count = 0
            total_tokens = 0

            23.downto(0).each do |hours_ago|
              bucket_time = (reference_time - hours_ago.hours).beginning_of_hour
              key = bucket_time.strftime("%Y-%m-%d %H:00:00")
              row = results[key] || {success: 0, failed: 0, cost: 0.0, duration: 0, tokens: 0}

              success_data << row[:success]
              failed_data << row[:failed]
              cost_data << row[:cost].round(4)
              duration_data << row[:duration]
              tokens_data << row[:tokens]

              total_success += row[:success]
              total_failed += row[:failed]
              total_cost += row[:cost]
              total_tokens += row[:tokens]
              if row[:duration] > 0
                total_duration_sum += row[:duration]
                total_duration_count += 1
              end
            end

            avg_duration_ms = (total_duration_count > 0) ? (total_duration_sum / total_duration_count).round : 0

            {
              range: "today",
              totals: {
                success: total_success,
                failed: total_failed,
                cost: total_cost.round(4),
                duration_ms: avg_duration_ms,
                tokens: total_tokens
              },
              series: [
                {name: "Success", data: success_data},
                {name: "Errors", data: failed_data},
                {name: "Cost", data: cost_data},
                {name: "Duration", data: duration_data},
                {name: "Tokens", data: tokens_data}
              ]
            }
          end

          # Builds daily chart data for specified number of days
          # Optimized: Single SQL GROUP BY with conditional aggregation
          # Database-agnostic: works with both PostgreSQL and SQLite
          #
          # @param days [Integer] Number of days to include
          # @param offset_days [Integer, nil] Optional offset for comparison data
          def build_daily_chart_data(days, offset_days: nil)
            offset = offset_days || 0
            end_date = Date.current - offset.days
            start_date = end_date - (days - 1).days

            scope = where(created_at: start_date.beginning_of_day..end_date.end_of_day)
            results = aggregated_chart_query(scope, granularity: :day)

            success_data = []
            failed_data = []
            cost_data = []
            duration_data = []
            tokens_data = []
            total_success = 0
            total_failed = 0
            total_cost = 0.0
            total_duration_sum = 0
            total_duration_count = 0
            total_tokens = 0

            (days - 1).downto(0).each do |i|
              date = end_date - i.days
              key = date.to_s
              row = results[key] || {success: 0, failed: 0, cost: 0.0, duration: 0, tokens: 0}

              success_data << row[:success]
              failed_data << row[:failed]
              cost_data << row[:cost].round(4)
              duration_data << row[:duration]
              tokens_data << row[:tokens]

              total_success += row[:success]
              total_failed += row[:failed]
              total_cost += row[:cost]
              total_tokens += row[:tokens]
              if row[:duration] > 0
                total_duration_sum += row[:duration]
                total_duration_count += 1
              end
            end

            avg_duration_ms = (total_duration_count > 0) ? (total_duration_sum / total_duration_count).round : 0

            {
              range: "#{days}d",
              days: days,
              totals: {
                success: total_success,
                failed: total_failed,
                cost: total_cost.round(4),
                duration_ms: avg_duration_ms,
                tokens: total_tokens
              },
              series: [
                {name: "Success", data: success_data},
                {name: "Errors", data: failed_data},
                {name: "Cost", data: cost_data},
                {name: "Duration", data: duration_data},
                {name: "Tokens", data: tokens_data}
              ]
            }
          end

          # Builds daily chart data for a custom date range
          # Optimized: Single SQL GROUP BY with conditional aggregation
          # Database-agnostic: works with both PostgreSQL and SQLite
          #
          # @param from_date [Date] Start date (inclusive)
          # @param to_date [Date] End date (inclusive)
          # @return [Hash] Chart data with series arrays
          def build_daily_chart_data_for_dates(from_date, to_date)
            days = (to_date - from_date).to_i + 1

            scope = where(created_at: from_date.beginning_of_day..to_date.end_of_day)
            results = aggregated_chart_query(scope, granularity: :day)

            success_data = []
            failed_data = []
            cost_data = []
            duration_data = []
            tokens_data = []
            total_success = 0
            total_failed = 0
            total_cost = 0.0
            total_duration_sum = 0
            total_duration_count = 0
            total_tokens = 0

            (0...days).each do |i|
              date = from_date + i.days
              key = date.to_s
              row = results[key] || {success: 0, failed: 0, cost: 0.0, duration: 0, tokens: 0}

              success_data << row[:success]
              failed_data << row[:failed]
              cost_data << row[:cost].round(4)
              duration_data << row[:duration]
              tokens_data << row[:tokens]

              total_success += row[:success]
              total_failed += row[:failed]
              total_cost += row[:cost]
              total_tokens += row[:tokens]
              if row[:duration] > 0
                total_duration_sum += row[:duration]
                total_duration_count += 1
              end
            end

            avg_duration_ms = (total_duration_count > 0) ? (total_duration_sum / total_duration_count).round : 0

            {
              range: "custom",
              days: days,
              from: from_date.to_s,
              to: to_date.to_s,
              totals: {
                success: total_success,
                failed: total_failed,
                cost: total_cost.round(4),
                duration_ms: avg_duration_ms,
                tokens: total_tokens
              },
              series: [
                {name: "Success", data: success_data},
                {name: "Errors", data: failed_data},
                {name: "Cost", data: cost_data},
                {name: "Duration", data: duration_data},
                {name: "Tokens", data: tokens_data}
              ]
            }
          end

          public

          # Builds the hourly activity data structure
          # Shows the last 24 hours with current hour on the right
          # Optimized: Single SQL GROUP BY instead of 48 individual queries
          #
          # @return [Array<Hash>] Success and failed series data
          # @api private
          def build_hourly_activity_data
            reference_time = Time.current.beginning_of_hour
            start_time = reference_time - 23.hours

            scope = where(created_at: start_time..(reference_time + 1.hour))
            results = aggregated_chart_query(scope, granularity: :hour)

            success_data = {}
            failed_data = {}

            23.downto(0).each do |hours_ago|
              bucket_time = (reference_time - hours_ago.hours).beginning_of_hour
              time_label = bucket_time.in_time_zone.strftime("%H:%M")
              key = bucket_time.strftime("%Y-%m-%d %H:00:00")
              row = results[key] || {success: 0, failed: 0}

              success_data[time_label] = row[:success]
              failed_data[time_label] = row[:failed]
            end

            [
              {name: "Success", data: success_data},
              {name: "Failed", data: failed_data}
            ]
          end

          # Retrieves hourly cost data for chart display
          #
          # Returns two series (input cost and output cost) with hourly breakdowns
          # for the current day. Results are cached for 5 minutes.
          #
          # @return [Array<Hash>] Chart series with input and output cost per hour
          def hourly_cost_chart
            cache_key = "ruby_llm_agents/hourly_cost/#{Date.current}"
            Rails.cache.fetch(cache_key, expires_in: 5.minutes) do
              build_hourly_cost_data
            end
          end

          # Builds the hourly cost data structure (uncached)
          # Optimized: Single SQL GROUP BY instead of 48 individual queries
          #
          # @return [Array<Hash>] Input and output cost series data
          # @api private
          def build_hourly_cost_data
            day_start = Time.current.beginning_of_day
            bucket = date_bucket_sql(:hour)

            rows = where(created_at: day_start..(day_start + 24.hours))
              .select(
                Arel.sql("#{bucket} AS bucket"),
                Arel.sql("SUM(COALESCE(input_cost, 0)) AS sum_input_cost"),
                Arel.sql("SUM(COALESCE(output_cost, 0)) AS sum_output_cost")
              )
              .group(Arel.sql("bucket"))

            cost_by_hour = rows.each_with_object({}) do |row, hash|
              hash[row["bucket"].to_s] = {
                input: row["sum_input_cost"].to_f.round(6),
                output: row["sum_output_cost"].to_f.round(6)
              }
            end

            input_cost_data = {}
            output_cost_data = {}

            (0..23).each do |hour|
              time_label = format("%02d:00", hour)
              key = (day_start + hour.hours).strftime("%Y-%m-%d %H:00:00")
              row = cost_by_hour[key] || {input: 0, output: 0}
              input_cost_data[time_label] = row[:input]
              output_cost_data[time_label] = row[:output]
            end

            [
              {name: "Input Cost", data: input_cost_data},
              {name: "Output Cost", data: output_cost_data}
            ]
          end

          # Cache hit rate percentage
          #
          # @return [Float] Percentage of executions that were cache hits (0.0-100.0)
          def cache_hit_rate
            total = count
            return 0.0 if total.zero?

            (cached.count.to_f / total * 100).round(1)
          end

          # Streaming execution rate percentage
          #
          # @return [Float] Percentage of executions that used streaming (0.0-100.0)
          def streaming_rate
            total = count
            return 0.0 if total.zero?

            (streaming.count.to_f / total * 100).round(1)
          end

          # Average time to first token for streaming executions
          #
          # time_to_first_token_ms is stored in metadata JSON, so we use
          # Ruby-level calculation instead of SQL aggregation.
          #
          # @return [Integer, nil] Average TTFT in milliseconds, or nil if no data
          def avg_time_to_first_token
            ttft_values = streaming
              .where("metadata IS NOT NULL")
              .pluck(:metadata)
              .filter_map { |m| m&.dig("time_to_first_token_ms") }
            return nil if ttft_values.empty?

            (ttft_values.sum.to_f / ttft_values.size).round(0)
          end

          # Finish reason distribution
          #
          # @return [Hash{String => Integer}] Counts grouped by finish reason, sorted descending
          def finish_reason_distribution
            group(:finish_reason).count.sort_by { |_, v| -v }.to_h
          end

          # Rate limited execution count
          #
          # rate_limited is stored in metadata JSON
          #
          # @return [Integer] Number of executions that were rate limited
          def rate_limited_count
            metadata_true("rate_limited").count
          end

          # Rate limited rate percentage
          #
          # @return [Float] Percentage of executions that were rate limited (0.0-100.0)
          def rate_limited_rate
            total = count
            return 0.0 if total.zero?

            (rate_limited_count.to_f / total * 100).round(1)
          end

          # Builds per-model statistics for model comparison
          # Optimized: Single SQL GROUP BY with conditional aggregation
          #
          # @param scope [ActiveRecord::Relation] Pre-filtered scope
          # @return [Array<Hash>] Model stats sorted by total cost descending
          def model_stats(scope: all)
            rows = scope.where.not(model_id: nil)
              .select(
                :model_id,
                Arel.sql("COUNT(*) AS exec_count"),
                Arel.sql("COALESCE(SUM(total_cost), 0) AS sum_cost"),
                Arel.sql("COALESCE(SUM(total_tokens), 0) AS sum_tokens"),
                Arel.sql("AVG(duration_ms) AS avg_dur"),
                Arel.sql("SUM(CASE WHEN status = 'success' THEN 1 ELSE 0 END) AS success_cnt")
              )
              .group(:model_id)

            total_cost = rows.sum { |r| r["sum_cost"].to_f }

            rows.map do |row|
              count = row["exec_count"].to_i
              model_cost = row["sum_cost"].to_f
              model_tokens = row["sum_tokens"].to_i
              successful = row["success_cnt"].to_i

              {
                model_id: row.model_id,
                executions: count,
                total_cost: model_cost,
                total_tokens: model_tokens,
                avg_duration_ms: row["avg_dur"].to_i,
                success_rate: (count > 0) ? (successful.to_f / count * 100).round(1) : 0,
                cost_per_1k_tokens: (model_tokens > 0) ? (model_cost / model_tokens * 1000).round(4) : 0,
                cost_percentage: (total_cost > 0) ? (model_cost / total_cost * 100).round(1) : 0
              }
            end.sort_by { |m| -(m[:total_cost] || 0) }
          end

          # Builds top errors list from error executions
          #
          # @param scope [ActiveRecord::Relation] Pre-filtered scope
          # @param limit [Integer] Max errors to return
          # @return [Array<Hash>] Top error classes with counts
          def top_errors(scope: all, limit: 5)
            error_scope = scope.where(status: "error")
            total_errors = error_scope.count

            error_scope.group(:error_class)
              .select("error_class, COUNT(*) as count, MAX(created_at) as last_seen")
              .order("count DESC")
              .limit(limit)
              .map do |row|
                {
                  error_class: row.error_class || "Unknown Error",
                  count: row.count,
                  percentage: (total_errors > 0) ? (row.count.to_f / total_errors * 100).round(1) : 0,
                  last_seen: row.last_seen
                }
            end
          end

          # Builds cache savings statistics
          # Optimized: Single SQL query with conditional aggregation
          #
          # @param scope [ActiveRecord::Relation] Pre-filtered scope
          # @return [Hash] Cache savings data
          def cache_savings(scope: all)
            cond = cache_hit_condition
            total_count, cache_count, cache_cost = scope.pick(
              Arel.sql("COUNT(*)"),
              Arel.sql("SUM(CASE WHEN #{cond} THEN 1 ELSE 0 END)"),
              Arel.sql("COALESCE(SUM(CASE WHEN #{cond} THEN total_cost ELSE 0 END), 0)")
            )

            total_count = total_count.to_i
            cache_count = cache_count.to_i

            return {count: 0, estimated_savings: 0, hit_rate: 0, total_executions: 0} if total_count.zero?

            {
              count: cache_count,
              estimated_savings: cache_cost.to_f,
              hit_rate: (cache_count.to_f / total_count * 100).round(1),
              total_executions: total_count
            }
          end

          # Batch fetches execution stats grouped by agent type
          # Optimized: Single SQL GROUP BY with conditional aggregation
          #
          # @param scope [ActiveRecord::Relation] Pre-filtered scope
          # @return [Hash<String, Hash>] Agent type => stats hash
          def batch_agent_stats(scope: all)
            rows = scope.select(
              :agent_type,
              Arel.sql("COUNT(*) AS exec_count"),
              Arel.sql("COALESCE(SUM(total_cost), 0) AS sum_cost"),
              Arel.sql("AVG(duration_ms) AS avg_dur"),
              Arel.sql("SUM(CASE WHEN status = 'success' THEN 1 ELSE 0 END) AS success_cnt")
            ).group(:agent_type)

            rows.each_with_object({}) do |row, hash|
              count = row["exec_count"].to_i
              total_cost = row["sum_cost"].to_f
              successful = row["success_cnt"].to_i

              hash[row.agent_type] = {
                count: count,
                total_cost: total_cost,
                avg_cost: (count > 0) ? (total_cost / count).round(6) : 0,
                avg_duration_ms: row["avg_dur"].to_i,
                success_rate: (count > 0) ? (successful.to_f / count * 100).round(1) : 0
              }
            end
          end

          # Cached daily statistics for dashboard
          #
          # @return [Hash] Daily stats with totals and rates
          def dashboard_daily_stats
            Rails.cache.fetch("ruby_llm_agents/daily_stats/#{Date.current}", expires_in: 1.minute) do
              scope = today
              total = scope.count
              {
                total_executions: total,
                successful: scope.successful.count,
                failed: scope.failed.count,
                total_cost: scope.total_cost_sum || 0,
                total_tokens: scope.total_tokens_sum || 0,
                avg_duration_ms: scope.avg_duration&.round || 0,
                success_rate: (total > 0) ? (scope.successful.count.to_f / total * 100).round(1) : 0.0
              }
            end
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
              avg_cost: (count > 0) ? (total_cost / count).round(6) : 0,
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

          # Returns a SQL expression for date/time bucketing
          #
          # Database-agnostic: uses strftime for SQLite, date_trunc for PostgreSQL.
          #
          # @param granularity [Symbol] :hour or :day
          # @return [Arel::Nodes::SqlLiteral] SQL fragment for SELECT/GROUP BY
          def date_bucket_sql(granularity)
            col = "#{table_name}.created_at"

            if connection.adapter_name.downcase.include?("sqlite")
              case granularity
              when :hour then Arel.sql("strftime('%Y-%m-%d %H:00:00', #{col})")
              when :day then Arel.sql("strftime('%Y-%m-%d', #{col})")
              else raise ArgumentError, "Unknown granularity: #{granularity}"
              end
            else
              case granularity
              when :hour then Arel.sql("to_char(date_trunc('hour', #{col}), 'YYYY-MM-DD HH24:00:00')")
              when :day then Arel.sql("to_char(#{col}::date, 'YYYY-MM-DD')")
              else raise ArgumentError, "Unknown granularity: #{granularity}"
              end
            end
          end

          # Runs a single aggregated query for chart data using SQL GROUP BY
          #
          # Replaces loading all records into Ruby memory. One SQL query returns
          # pre-aggregated metrics per time bucket.
          #
          # @param scope [ActiveRecord::Relation] Pre-filtered scope with time range
          # @param granularity [Symbol] :hour or :day
          # @return [Hash{String => Hash}] Bucket key => {success:, failed:, cost:, duration:, tokens:}
          def aggregated_chart_query(scope, granularity:)
            bucket = date_bucket_sql(granularity)

            rows = scope
              .select(
                Arel.sql("#{bucket} AS bucket"),
                Arel.sql("SUM(CASE WHEN status = 'success' THEN 1 ELSE 0 END) AS success_count"),
                Arel.sql("SUM(CASE WHEN status IN ('error','timeout') THEN 1 ELSE 0 END) AS failed_count"),
                Arel.sql("SUM(COALESCE(total_cost, 0)) AS sum_cost"),
                Arel.sql("AVG(CASE WHEN duration_ms > 0 THEN duration_ms ELSE NULL END) AS avg_dur"),
                Arel.sql("SUM(COALESCE(input_tokens, 0) + COALESCE(output_tokens, 0)) AS sum_tokens")
              )
              .group(Arel.sql("bucket"))
              .order(Arel.sql("bucket"))

            rows.each_with_object({}) do |row, hash|
              hash[row["bucket"].to_s] = {
                success: row["success_count"].to_i,
                failed: row["failed_count"].to_i,
                cost: row["sum_cost"].to_f,
                duration: row["avg_dur"].to_i,
                tokens: row["sum_tokens"].to_i
              }
            end
          end

          # SQL condition for boolean cache_hit column
          #
          # SQLite stores booleans as 1/0, PostgreSQL as TRUE/FALSE.
          #
          # @return [String] SQL condition fragment
          def cache_hit_condition
            if connection.adapter_name.downcase.include?("sqlite")
              "cache_hit = 1"
            else
              "cache_hit = TRUE"
            end
          end
        end
      end
    end
  end
end
