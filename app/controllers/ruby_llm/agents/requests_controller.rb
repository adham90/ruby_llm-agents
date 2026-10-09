# frozen_string_literal: true

module RubyLLM
  module Agents
    # Controller for browsing tracked request groups
    #
    # Provides listing and detail views for executions grouped by
    # request_id, as set by RubyLLM::Agents.track blocks.
    #
    # @api private
    class RequestsController < ApplicationController
      include Paginatable

      # Seconds the header totals may spend before the list renders without them
      TOTALS_TIMEOUT = 1

      # Progressively wider windows searched for the most recent requests
      RECENT_WINDOWS = [1.day, 7.days, 30.days].freeze

      # Lists all tracked requests with aggregated stats
      #
      # A request is a GROUP BY over its executions, so listing "the latest
      # 25" naively aggregates every tracked execution ever recorded before
      # it can sort. Two things keep the default view off that path: the
      # page of request ids is found in a recent window first (see
      # #recent_request_ids) and only those requests are aggregated, and the
      # header totals are best-effort.
      #
      # @return [void]
      def index
        @sort_column = sanitize_sort_column(params[:sort])
        @sort_direction = (params[:direction] == "asc") ? "asc" : "desc"

        tracked = Execution.where.not(request_id: [nil, ""])
        days = params[:days].to_i
        tracked = tracked.where("created_at >= ?", days.days.ago) if days > 0

        # One query for the distinct request count and total cost; the count
        # is shared with pagination instead of being run a second time.
        @stats = cached_stats(:requests_totals, days) do
          Execution.best_effort(timeout: TOTALS_TIMEOUT) do
            total_requests, total_cost = tracked
              .pick(Arel.sql("COUNT(DISTINCT request_id)"), Arel.sql("COALESCE(SUM(total_cost), 0)"))
            {total_requests: total_requests.to_i, total_cost: (total_cost || 0).to_d.round(6)}
          end
        end

        result = paginate_requests(tracked, total_count: @stats&.fetch(:total_requests))
        @requests = result[:records]
        @pagination = result[:pagination]
      end

      # Shows a single tracked request with all its executions
      #
      # @return [void]
      def show
        @request_id = params[:id]

        # Loaded once: the summary is derived from the same handful of rows
        # the page lists, instead of nine more queries against them. (Two of
        # those were DISTINCT plucks on an ordered relation, which PostgreSQL
        # rejects, so this page raised there.)
        @executions = Execution
          .where(request_id: @request_id)
          .preload(:error_detail)
          .order(started_at: :asc)
          .to_a

        if @executions.empty?
          redirect_to ruby_llm_agents.requests_path,
            alert: "Request not found: #{@request_id}"
          return
        end

        @summary = {
          call_count: @executions.size,
          total_cost: @executions.sum { |e| e.total_cost || 0 },
          total_tokens: @executions.sum { |e| e.total_tokens || 0 },
          started_at: @executions.filter_map(&:started_at).min,
          completed_at: @executions.filter_map(&:completed_at).max,
          agent_types: @executions.map(&:agent_type).uniq,
          models_used: @executions.map(&:model_id).uniq,
          all_successful: @executions.all?(&:status_success?),
          error_count: @executions.count(&:status_error?)
        }

        if @summary[:started_at] && @summary[:completed_at]
          @summary[:duration_ms] = ((@summary[:completed_at] - @summary[:started_at]) * 1000).to_i
        end
      end

      private

      ALLOWED_SORT_COLUMNS = %w[latest_created_at call_count total_cost total_tokens total_duration_ms].freeze

      def sanitize_sort_column(column)
        ALLOWED_SORT_COLUMNS.include?(column) ? column : "latest_created_at"
      end

      # Comma-separated DISTINCT values of a column per group.
      # GROUP_CONCAT exists on SQLite and MySQL; PostgreSQL spells it STRING_AGG.
      def distinct_list_sql(column)
        if Execution.connection.adapter_name.downcase.include?("postg")
          "STRING_AGG(DISTINCT #{column}, ',')"
        else
          "GROUP_CONCAT(DISTINCT #{column})"
        end
      end

      # Aggregates executions into one row per request
      def request_rows(scope)
        scope
          .select(
            "request_id",
            "COUNT(*) AS call_count",
            "SUM(total_cost) AS total_cost",
            "SUM(total_tokens) AS total_tokens",
            "MIN(started_at) AS started_at",
            "MAX(completed_at) AS completed_at",
            "SUM(duration_ms) AS total_duration_ms",
            "#{distinct_list_sql("agent_type")} AS agent_types_list",
            "#{distinct_list_sql("status")} AS statuses_list",
            "MAX(created_at) AS latest_created_at"
          )
          .group(:request_id)
      end

      # Request ids for one page of the newest-first list
      #
      # The requests active most recently are, by definition, the ones with
      # an execution in the most recent stretch of time. So instead of
      # ranking every request, rank the ones seen in the last day; if that
      # does not fill the page, the last week; and so on, ending with no
      # bound at all. Each attempt is a bounded read of the created_at index,
      # and the first one that fills the page is exact.
      #
      # @param tracked [ActiveRecord::Relation] Executions that carry a request_id
      # @param offset [Integer] Requests to skip
      # @param limit [Integer] Requests to return
      # @return [Array<String>] Request ids, newest activity first
      def recent_request_ids(tracked, offset:, limit:)
        [*RECENT_WINDOWS, nil].each do |window|
          scope = window ? tracked.where("created_at >= ?", window.ago) : tracked
          ids = scope.group(:request_id)
            .order(Arel.sql("MAX(created_at) DESC"))
            .offset(offset).limit(limit)
            .pluck(:request_id)

          return ids if ids.size >= limit || window.nil?
        end
      end

      # Loads one page of requests
      #
      # Fetches one row more than the page holds, so a next page can be
      # detected when the total count is unavailable.
      #
      # @param tracked [ActiveRecord::Relation] Executions that carry a request_id
      # @param total_count [Integer, nil] Distinct requests, when known
      # @return [Hash] :records and :pagination, as Paginatable#paginate
      def paginate_requests(tracked, total_count:)
        page = [(params[:page] || 1).to_i, 1].max
        per_page = RubyLLM::Agents.configuration.per_page
        offset = (page - 1) * per_page

        records = if @sort_column == "latest_created_at" && @sort_direction == "desc"
          ids = recent_request_ids(tracked, offset: offset, limit: per_page + 1)
          request_rows(tracked.where(request_id: ids)).sort_by { |row| ids.index(row.request_id) }
        else
          # Sorting on an aggregate has to aggregate every request first.
          request_rows(tracked)
            .order("#{@sort_column} #{@sort_direction.upcase}")
            .offset(offset).limit(per_page + 1).to_a
        end

        {
          records: records.first(per_page),
          pagination: {
            current_page: page,
            per_page: per_page,
            total_count: total_count,
            total_pages: total_count && (total_count.to_f / per_page).ceil,
            next_page: records.size > per_page
          }
        }
      end
    end
  end
end
