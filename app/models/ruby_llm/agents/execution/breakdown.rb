# frozen_string_literal: true

module RubyLLM
  module Agents
    class Execution
      # Every dashboard figure for a set of executions, from one scan
      #
      # The dashboard and analytics pages each show half a dozen sections over
      # the same time window: totals, per-agent stats, per-model stats, top
      # errors, cache savings, error cost. Computed separately, that is one
      # pass over the window per section — and on a table with millions of
      # executions each pass takes seconds. A Breakdown reads the window once,
      # grouped by the few low-cardinality columns the sections slice on, and
      # derives each section from those groups in Ruby.
      #
      # @example
      #   breakdown = Execution.last_n_days(30).breakdown
      #   breakdown.totals       #=> { total: 1200, cost: 4.2, success_rate: 97.1, ... }
      #   breakdown.model_stats  #=> [{ model_id: "gpt-4o", executions: 800, ... }]
      #   breakdown.top_errors   #=> [{ error_class: "Timeout::Error", count: 12, ... }]
      #
      # @see Execution::Analytics::ClassMethods#breakdown
      # @api public
      class Breakdown
        Group = Struct.new(
          :agent_type, :model_id, :billed_model_id, :status, :error_class,
          :count, :cost, :tokens, :duration_sum, :duration_count,
          :cache_hits, :miss_cost, :last_seen
        )

        # Raw grouped rows, as plain arrays so a breakdown can be cached and
        # rebuilt with {.new}.
        #
        # @return [Array<Array>]
        attr_reader :rows

        # @param rows [Array<Array>] One array per group, in {Group} member
        #   order, as selected by {Execution::Analytics::ClassMethods#breakdown}
        def initialize(rows)
          @rows = rows
          @groups = rows.map do |row|
            Group.new(*row[0, 5], row[5].to_i, row[6].to_f, row[7].to_i, row[8].to_i,
              row[9].to_i, row[10].to_i, row[11].to_f, parse_time(row[12]))
          end
        end

        # A breakdown narrowed to some agents
        #
        # @param agent_types [Array<String>] Agent class names to keep
        # @return [Breakdown]
        def for_agents(agent_types)
          names = Array(agent_types)
          self.class.new(@rows.select { |row| names.include?(row[0]) })
        end

        # Headline figures across the whole scope
        #
        # @return [Hash] :total, :success, :errors, :timeouts, :cost, :tokens,
        #   :avg_duration_ms, :success_rate, :error_rate, :last_seen
        def totals
          total = sum(@groups, :count)
          success = sum(with_status("success"), :count)
          errors = sum(with_status("error"), :count)
          timeouts = sum(with_status("timeout"), :count)

          {
            total: total,
            success: success,
            errors: errors,
            timeouts: timeouts,
            cost: sum(@groups, :cost),
            tokens: sum(@groups, :tokens),
            avg_duration_ms: avg_duration(@groups),
            success_rate: rate(success, total),
            error_rate: rate(errors + timeouts, total),
            last_seen: @groups.filter_map(&:last_seen).max
          }
        end

        # Per-agent stats
        #
        # @return [Hash{String => Hash}] Agent type => :count, :total_cost,
        #   :total_tokens, :avg_cost, :avg_duration_ms, :success_rate
        def agent_stats
          @groups.group_by(&:agent_type).transform_values do |groups|
            count = sum(groups, :count)
            cost = sum(groups, :cost)

            {
              count: count,
              total_cost: cost,
              total_tokens: sum(groups, :tokens),
              avg_cost: (count > 0) ? (cost / count).round(6) : 0,
              avg_duration_ms: avg_duration(groups),
              success_rate: rate(sum(groups.select { |g| g.status == "success" }, :count), count)
            }
          end
        end

        # Per-model stats, attributed to the model that actually ran
        #
        # @return [Array<Hash>] Sorted by total cost, most expensive first
        def model_stats
          overall_cost = sum(@groups, :cost)

          @groups.group_by(&:billed_model_id).map do |model_id, groups|
            count = sum(groups, :count)
            cost = sum(groups, :cost)
            tokens = sum(groups, :tokens)

            {
              model_id: model_id,
              executions: count,
              total_cost: cost,
              total_tokens: tokens,
              avg_duration_ms: avg_duration(groups),
              success_rate: rate(sum(groups.select { |g| g.status == "success" }, :count), count),
              cost_per_1k_tokens: (tokens > 0) ? (cost / tokens * 1000).round(4) : 0,
              cost_percentage: (overall_cost > 0) ? (cost / overall_cost * 100).round(1) : 0
            }
          end.sort_by { |m| -m[:total_cost] }
        end

        # Usage per configured model, most expensive first
        #
        # Unlike {#model_stats} this groups on the model the agent asked for,
        # which is what the "move these runs to a cheaper model" comparison
        # needs.
        #
        # @return [Array<Hash>] :model_id, :runs, :cost, :tokens, :cost_per_run,
        #   :cost_per_1k_tokens
        def configured_model_usage
          @groups.group_by(&:model_id).map do |model_id, groups|
            count = sum(groups, :count)
            cost = sum(groups, :cost)
            tokens = sum(groups, :tokens)

            {
              model_id: model_id,
              runs: count,
              cost: cost,
              tokens: tokens,
              cost_per_run: (count > 0) ? (cost / count) : 0,
              cost_per_1k_tokens: (tokens > 0) ? (cost / tokens * 1000) : 0
            }
          end.sort_by { |m| -m[:cost] }
        end

        # Most frequent error classes
        #
        # @param limit [Integer] Max error classes to return
        # @return [Array<Hash>] :error_class, :count, :percentage, :last_seen
        def top_errors(limit: 5)
          errors = with_status("error")
          total = sum(errors, :count)

          errors.group_by(&:error_class).map do |error_class, groups|
            count = sum(groups, :count)

            {
              error_class: error_class || "Unknown Error",
              count: count,
              percentage: rate(count, total),
              last_seen: groups.filter_map(&:last_seen).max
            }
          end.sort_by { |e| -e[:count] }.first(limit)
        end

        # Money spent on executions that ended in an error
        #
        # @param limit [Integer] Max (error class, agent) pairs to return
        # @return [Hash] :total_cost, :total_count, and :breakdown — the
        #   costliest (error class, agent) pairs
        def error_cost(limit: 10)
          errors = with_status("error")

          pairs = errors.group_by { |g| [g.error_class, g.agent_type] }.map do |(error_class, agent_type), groups|
            {
              error_class: error_class || "Unknown",
              agent_type: agent_type,
              count: sum(groups, :count),
              cost: sum(groups, :cost),
              last_seen: groups.filter_map(&:last_seen).max
            }
          end

          {
            total_cost: sum(errors, :cost),
            total_count: sum(errors, :count),
            breakdown: pairs.sort_by { |e| -e[:cost] }.first(limit)
          }
        end

        # Cache hit rate and the spend those hits avoided
        #
        # A cache hit makes no API call, so its own cost is always zero; the
        # saving is estimated at the mean cost of the misses in the same scope.
        #
        # @return [Hash] :count, :estimated_savings, :hit_rate, :total_executions
        def cache_savings
          total = sum(@groups, :count)
          return {count: 0, estimated_savings: 0, hit_rate: 0, total_executions: 0} if total.zero?

          hits = sum(@groups, :cache_hits)
          misses = total - hits
          avg_miss_cost = misses.positive? ? (sum(@groups, :miss_cost) / misses) : 0.0

          {
            count: hits,
            estimated_savings: (hits * avg_miss_cost).round(6),
            hit_rate: rate(hits, total),
            total_executions: total
          }
        end

        private

        def with_status(status)
          @groups.select { |g| g.status == status }
        end

        def sum(groups, field)
          groups.sum { |g| g[field] }
        end

        def rate(part, whole)
          (whole > 0) ? (part.to_f / whole * 100).round(1) : 0.0
        end

        def avg_duration(groups)
          samples = sum(groups, :duration_count)
          (samples > 0) ? (sum(groups, :duration_sum) / samples) : 0
        end

        # MAX(created_at) comes back as a Time on PostgreSQL and as a UTC
        # string on SQLite.
        def parse_time(value)
          value.is_a?(String) ? ActiveSupport::TimeZone["UTC"].parse(value) : value
        end
      end
    end
  end
end
