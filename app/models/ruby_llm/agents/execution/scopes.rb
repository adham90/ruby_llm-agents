# frozen_string_literal: true

module RubyLLM
  module Agents
    class Execution
      # Query scopes for filtering and aggregating executions
      #
      # All scopes are chainable and return ActiveRecord::Relation objects.
      #
      # @example Chaining scopes
      #   Execution.by_agent("SearchAgent").today.successful
      #   Execution.expensive(2.00).slow(10_000)
      #
      # @see RubyLLM::Agents::Execution::Analytics
      # @api public
      module Scopes
        extend ActiveSupport::Concern

        included do
          # @!group Time-based Scopes

          # @!method recent(limit = 100)
          #   Returns most recent executions
          #   @param limit [Integer] Maximum records to return
          #   @return [ActiveRecord::Relation]

          # @!method today
          #   Returns executions from today
          #   @return [ActiveRecord::Relation]

          # @!method this_week
          #   Returns executions from current week
          #   @return [ActiveRecord::Relation]

          # @!method last_n_days(n)
          #   Returns executions from the last n days
          #   @param n [Integer] Number of days
          #   @return [ActiveRecord::Relation]
          scope :recent, ->(limit = 100) { order(created_at: :desc).limit(limit) }
          scope :oldest, ->(limit = 100) { order(created_at: :asc).limit(limit) }
          scope :all_time, -> { all }  # Explicit scope for all-time queries (used by analytics)
          scope :today, -> { where("created_at >= ?", Time.current.beginning_of_day) }
          scope :yesterday, -> { where(created_at: 1.day.ago.beginning_of_day..1.day.ago.end_of_day) }
          scope :this_week, -> { where("created_at >= ?", Time.current.beginning_of_week) }
          scope :this_month, -> { where("created_at >= ?", Time.current.beginning_of_month) }
          scope :last_n_days, ->(n) { where("created_at >= ?", n.days.ago) }

          # @!endgroup

          # @!group Agent-based Scopes

          # @!method by_agent(agent_type)
          #   Filters to a specific agent type
          #   @param agent_type [String] The agent class name
          #   @return [ActiveRecord::Relation]

          # @!method by_version(version)
          #   Filters to a specific agent version
          #   @param version [String] The version string
          #   @return [ActiveRecord::Relation]

          # @!method by_model(model_id)
          #   Filters to a specific LLM model
          #   @param model_id [String] The model identifier
          #   @return [ActiveRecord::Relation]
          scope :by_agent, ->(agent_type) { where(agent_type: agent_type.to_s) }
          scope :by_version, ->(version) { where(agent_version: version.to_s) }
          scope :by_model, ->(model_id) { where(model_id: model_id.to_s) }

          # @!endgroup

          # @!group Status Scopes

          # @!method successful
          #   Returns executions with success status
          #   @return [ActiveRecord::Relation]

          # @!method failed
          #   Returns executions with error or timeout status
          #   @return [ActiveRecord::Relation]

          # @!method errors
          #   Returns executions with error status only
          #   @return [ActiveRecord::Relation]
          scope :running, -> { where(status: "running") }
          scope :in_progress, -> { running }  # alias
          scope :completed, -> { where.not(status: "running") }
          scope :successful, -> { where(status: "success") }
          scope :failed, -> { where(status: %w[error timeout]) }
          scope :errors, -> { where(status: "error") }
          scope :timeouts, -> { where(status: "timeout") }

          # @!endgroup

          # @!group Performance Scopes

          # @!method expensive(threshold_dollars = 1.00)
          #   Returns executions exceeding cost threshold
          #   @param threshold_dollars [Float] Cost threshold in USD
          #   @return [ActiveRecord::Relation]

          # @!method slow(threshold_ms = 5000)
          #   Returns executions exceeding duration threshold
          #   @param threshold_ms [Integer] Duration threshold in milliseconds
          #   @return [ActiveRecord::Relation]

          # @!method high_token(threshold = 10_000)
          #   Returns executions exceeding token threshold
          #   @param threshold [Integer] Token count threshold
          #   @return [ActiveRecord::Relation]
          scope :expensive, ->(threshold_dollars = 1.00) { where("total_cost >= ?", threshold_dollars) }
          scope :slow, ->(threshold_ms = 5000) { where("duration_ms >= ?", threshold_ms) }
          scope :high_token, ->(threshold = 10_000) { where("total_tokens >= ?", threshold) }

          # @!endgroup

          # @!group Parameter Scopes

          # @!method with_parameter(key, value = nil)
          #   Filters by JSONB parameter key/value
          #   @param key [String, Symbol] Parameter key to check
          #   @param value [Object, nil] Optional value to match
          #   @return [ActiveRecord::Relation]
          scope :with_parameter, ->(key, value = nil) do
            if value
              where("parameters @> ?", { key => value }.to_json)
            else
              where("parameters ? :key", key: key.to_s)
            end
          end

          # @!endgroup

          # @!group Search Scopes

          # @!method search(query)
          #   Free-text search across error fields and parameters
          #   @param query [String] Search query
          #   @return [ActiveRecord::Relation]
          scope :search, ->(query) do
            return all if query.blank?

            sanitized_query = "%#{sanitize_sql_like(query)}%"
            # Use database-agnostic case-insensitive search
            # PostgreSQL: ILIKE, SQLite: LIKE with LOWER() + ESCAPE clause
            if connection.adapter_name.downcase.include?("postgresql")
              where(
                "error_class ILIKE :q OR error_message ILIKE :q OR CAST(parameters AS TEXT) ILIKE :q",
                q: sanitized_query
              )
            else
              # SQLite and other databases need ESCAPE clause for backslash to work
              sanitized_query_lower = sanitized_query.downcase
              where(
                "LOWER(error_class) LIKE :q ESCAPE '\\' OR " \
                "LOWER(error_message) LIKE :q ESCAPE '\\' OR " \
                "LOWER(CAST(parameters AS TEXT)) LIKE :q ESCAPE '\\'",
                q: sanitized_query_lower
              )
            end
          end

          # @!endgroup

          # @!group Tracing Scopes

          # @!method by_trace(trace_id)
          #   Filters to a specific distributed trace
          #   @param trace_id [String] The trace identifier
          #   @return [ActiveRecord::Relation]

          # @!method by_request(request_id)
          #   Filters to a specific request
          #   @param request_id [String] The request identifier
          #   @return [ActiveRecord::Relation]

          # @!method root_executions
          #   Returns only root (top-level) executions
          #   @return [ActiveRecord::Relation]

          # @!method child_executions
          #   Returns only child (nested) executions
          #   @return [ActiveRecord::Relation]
          scope :by_trace, ->(trace_id) { where(trace_id: trace_id) }
          scope :by_request, ->(request_id) { where(request_id: request_id) }
          scope :root_executions, -> { where(parent_execution_id: nil) }
          scope :child_executions, -> { where.not(parent_execution_id: nil) }
          scope :children_of, ->(execution_id) { where(parent_execution_id: execution_id) }

          # @!endgroup

          # @!group Routing and Retry Scopes

          # @!method with_fallback
          #   Returns executions that used a fallback model
          #   @return [ActiveRecord::Relation]

          # @!method retryable_errors
          #   Returns executions with retryable errors
          #   @return [ActiveRecord::Relation]

          # @!method rate_limited
          #   Returns executions that were rate limited
          #   @return [ActiveRecord::Relation]
          scope :with_fallback, -> { where.not(fallback_reason: nil) }
          scope :retryable_errors, -> { where(retryable: true) }
          scope :rate_limited, -> { where(rate_limited: true) }
          scope :by_fallback_reason, ->(reason) { where(fallback_reason: reason) }

          # @!endgroup

          # @!group Caching Scopes

          # @!method cached
          #   Returns executions that were cache hits
          #   @return [ActiveRecord::Relation]

          # @!method cache_miss
          #   Returns executions that were cache misses
          #   @return [ActiveRecord::Relation]
          scope :cached, -> { where(cache_hit: true) }
          scope :cache_miss, -> { where(cache_hit: [false, nil]) }

          # @!endgroup

          # @!group Streaming Scopes

          # @!method streaming
          #   Returns executions that used streaming
          #   @return [ActiveRecord::Relation]

          # @!method non_streaming
          #   Returns executions that did not use streaming
          #   @return [ActiveRecord::Relation]
          scope :streaming, -> { where(streaming: true) }
          scope :non_streaming, -> { where(streaming: [false, nil]) }

          # @!endgroup

          # @!group Finish Reason Scopes

          # @!method by_finish_reason(reason)
          #   Filters by finish reason
          #   @param reason [String] The finish reason (stop, length, content_filter, tool_calls)
          #   @return [ActiveRecord::Relation]

          # @!method truncated
          #   Returns executions that hit max_tokens limit
          #   @return [ActiveRecord::Relation]

          # @!method content_filtered
          #   Returns executions blocked by safety filter
          #   @return [ActiveRecord::Relation]
          scope :by_finish_reason, ->(reason) { where(finish_reason: reason) }
          scope :truncated, -> { where(finish_reason: "length") }
          scope :content_filtered, -> { where(finish_reason: "content_filter") }
          scope :tool_calls, -> { where(finish_reason: "tool_calls") }

          # @!endgroup
        end

        # @!group Aggregation Methods
        #
        # These methods return scalar values, not relations.
        # They can be called on scoped relations.

        class_methods do
          # Returns sum of total_cost for the current scope
          #
          # @return [Float, nil] Total cost in USD
          def total_cost_sum
            sum(:total_cost)
          end

          # Returns sum of total_tokens for the current scope
          #
          # @return [Integer, nil] Total token count
          def total_tokens_sum
            sum(:total_tokens)
          end

          # Returns average duration for the current scope
          #
          # @return [Float, nil] Average duration in milliseconds
          def avg_duration
            average(:duration_ms)
          end

          # Returns average token count for the current scope
          #
          # @return [Float, nil] Average tokens per execution
          def avg_tokens
            average(:total_tokens)
          end

          # @!endgroup
        end
      end
    end
  end
end
