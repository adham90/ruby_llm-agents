# frozen_string_literal: true

module RubyLLM
  module Agents
    class Execution
      # Scopes concern for common query patterns
      #
      # Provides chainable scopes for:
      # - Time-based filtering (today, this_week, last_n_days)
      # - Agent-based filtering (by_agent, by_version, by_model)
      # - Status filtering (successful, failed, errors, timeouts)
      # - Performance filtering (expensive, slow, high_token)
      # - JSONB parameter queries
      # - Aggregations (total_cost_sum, avg_duration)
      #
      module Scopes
        extend ActiveSupport::Concern

        included do
          # Time-based scopes
          scope :recent, ->(limit = 100) { order(created_at: :desc).limit(limit) }
          scope :oldest, ->(limit = 100) { order(created_at: :asc).limit(limit) }
          scope :today, -> { where("created_at >= ?", Time.current.beginning_of_day) }
          scope :yesterday, -> { where(created_at: 1.day.ago.beginning_of_day..1.day.ago.end_of_day) }
          scope :this_week, -> { where("created_at >= ?", Time.current.beginning_of_week) }
          scope :this_month, -> { where("created_at >= ?", Time.current.beginning_of_month) }
          scope :last_n_days, ->(n) { where("created_at >= ?", n.days.ago) }

          # Agent-based scopes
          scope :by_agent, ->(agent_type) { where(agent_type: agent_type.to_s) }
          scope :by_version, ->(version) { where(agent_version: version.to_s) }
          scope :by_model, ->(model_id) { where(model_id: model_id.to_s) }

          # Status scopes
          scope :running, -> { where(status: "running") }
          scope :in_progress, -> { running }  # alias
          scope :completed, -> { where.not(status: "running") }
          scope :successful, -> { where(status: "success") }
          scope :failed, -> { where(status: %w[error timeout]) }
          scope :errors, -> { where(status: "error") }
          scope :timeouts, -> { where(status: "timeout") }

          # Performance scopes
          scope :expensive, ->(threshold_dollars = 1.00) { where("total_cost >= ?", threshold_dollars) }
          scope :slow, ->(threshold_ms = 5000) { where("duration_ms >= ?", threshold_ms) }
          scope :high_token, ->(threshold = 10_000) { where("total_tokens >= ?", threshold) }

          # Parameter-based scopes (JSONB queries)
          scope :with_parameter, ->(key, value = nil) do
            if value
              where("parameters @> ?", { key => value }.to_json)
            else
              where("parameters ? :key", key: key.to_s)
            end
          end

        end

        # Aggregation methods (not scopes - these return values, not relations)
        class_methods do
          def total_cost_sum
            sum(:total_cost)
          end

          def total_tokens_sum
            sum(:total_tokens)
          end

          def avg_duration
            average(:duration_ms)
          end

          def avg_tokens
            average(:total_tokens)
          end
        end
      end
    end
  end
end
