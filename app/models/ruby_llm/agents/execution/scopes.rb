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
