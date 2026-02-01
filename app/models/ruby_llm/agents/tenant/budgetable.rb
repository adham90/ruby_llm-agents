# frozen_string_literal: true

module RubyLLM
  module Agents
    class Tenant
      # Handles budget limits and enforcement for tenants.
      #
      # Supports three types of limits:
      # - Cost limits (USD): daily_limit, monthly_limit
      # - Token limits: daily_token_limit, monthly_token_limit
      # - Execution limits: daily_execution_limit, monthly_execution_limit
      #
      # Enforcement modes:
      # - :none - No enforcement, tracking only
      # - :soft - Log warnings when limits exceeded
      # - :hard - Block execution when limits exceeded
      #
      # @example Setting limits
      #   tenant.daily_limit = 100.0
      #   tenant.monthly_limit = 1000.0
      #   tenant.enforcement = "hard"
      #
      # @example Checking budget
      #   tenant.within_budget?                    # => true
      #   tenant.within_budget?(type: :monthly_cost)
      #   tenant.remaining_budget(type: :daily_tokens)
      #
      # @see BudgetTracker
      # @api public
      module Budgetable
        extend ActiveSupport::Concern

        # Valid enforcement modes
        ENFORCEMENT_MODES = %w[none soft hard].freeze

        included do
          # Validations
          validates :enforcement, inclusion: { in: ENFORCEMENT_MODES }, allow_nil: true
          validates :daily_limit, :monthly_limit,
                    numericality: { greater_than_or_equal_to: 0 }, allow_nil: true
          validates :daily_token_limit, :monthly_token_limit,
                    numericality: { greater_than_or_equal_to: 0, only_integer: true }, allow_nil: true
          validates :daily_execution_limit, :monthly_execution_limit,
                    numericality: { greater_than_or_equal_to: 0, only_integer: true }, allow_nil: true

          # Scopes
          scope :with_budgets, -> { where.not(daily_limit: nil).or(where.not(monthly_limit: nil)) }
          scope :with_enforcement, ->(mode) { where(enforcement: mode) }
          scope :hard_enforcement, -> { where(enforcement: "hard") }
          scope :soft_enforcement, -> { where(enforcement: "soft") }
          scope :no_enforcement, -> { where(enforcement: "none") }
        end

        # Effective limits (considering inheritance from global config)

        # Returns the effective daily cost limit
        #
        # @return [Float, nil] The daily limit or nil if not set
        def effective_daily_limit
          return daily_limit if daily_limit.present?
          return nil unless inherit_global_defaults

          global_config&.dig(:global_daily)
        end

        # Returns the effective monthly cost limit
        #
        # @return [Float, nil] The monthly limit or nil if not set
        def effective_monthly_limit
          return monthly_limit if monthly_limit.present?
          return nil unless inherit_global_defaults

          global_config&.dig(:global_monthly)
        end

        # Returns the effective daily token limit
        #
        # @return [Integer, nil] The daily token limit or nil if not set
        def effective_daily_token_limit
          return daily_token_limit if daily_token_limit.present?
          return nil unless inherit_global_defaults

          global_config&.dig(:global_daily_tokens)
        end

        # Returns the effective monthly token limit
        #
        # @return [Integer, nil] The monthly token limit or nil if not set
        def effective_monthly_token_limit
          return monthly_token_limit if monthly_token_limit.present?
          return nil unless inherit_global_defaults

          global_config&.dig(:global_monthly_tokens)
        end

        # Returns the effective daily execution limit
        #
        # @return [Integer, nil] The daily execution limit or nil if not set
        def effective_daily_execution_limit
          return daily_execution_limit if daily_execution_limit.present?
          return nil unless inherit_global_defaults

          global_config&.dig(:global_daily_executions)
        end

        # Returns the effective monthly execution limit
        #
        # @return [Integer, nil] The monthly execution limit or nil if not set
        def effective_monthly_execution_limit
          return monthly_execution_limit if monthly_execution_limit.present?
          return nil unless inherit_global_defaults

          global_config&.dig(:global_monthly_executions)
        end

        # Returns the effective enforcement mode
        #
        # @return [Symbol] :none, :soft, or :hard
        def effective_enforcement
          return enforcement.to_sym if enforcement.present?
          return :soft unless inherit_global_defaults

          RubyLLM::Agents.configuration.budget_enforcement
        end

        # Returns the effective per-agent daily limit
        #
        # @param agent_type [String] The agent class name
        # @return [Float, nil] The limit or nil if not set
        def effective_per_agent_daily(agent_type)
          limit = per_agent_daily&.dig(agent_type)
          return limit if limit.present?
          return nil unless inherit_global_defaults

          global_config&.dig(:per_agent_daily, agent_type)
        end

        # Returns the effective per-agent monthly limit
        #
        # @param agent_type [String] The agent class name
        # @return [Float, nil] The limit or nil if not set
        def effective_per_agent_monthly(agent_type)
          limit = per_agent_monthly&.dig(agent_type)
          return limit if limit.present?
          return nil unless inherit_global_defaults

          global_config&.dig(:per_agent_monthly, agent_type)
        end

        # Budget status checks

        # Checks if budget enforcement is enabled
        #
        # @return [Boolean] true if enforcement is :soft or :hard
        def budgets_enabled?
          effective_enforcement != :none
        end

        # Checks if hard enforcement is enabled
        #
        # @return [Boolean]
        def hard_enforcement?
          effective_enforcement == :hard
        end

        # Checks if soft enforcement is enabled
        #
        # @return [Boolean]
        def soft_enforcement?
          effective_enforcement == :soft
        end

        # Check if within budget for a specific type using counter columns
        #
        # @param type [Symbol] :daily_cost, :monthly_cost, :daily_tokens,
        #   :monthly_tokens, :daily_executions, :monthly_executions
        # @return [Boolean]
        def within_budget?(type: :daily_cost)
          return true unless budgets_enabled?

          case type
          when :daily_cost
            within_daily_cost_budget?
          when :monthly_cost
            within_monthly_cost_budget?
          when :daily_tokens
            within_daily_token_budget?
          when :monthly_tokens
            within_monthly_token_budget?
          when :daily_executions
            within_daily_execution_budget?
          when :monthly_executions
            within_monthly_execution_budget?
          else
            true
          end
        end

        # Get remaining budget for a specific type
        #
        # @param type [Symbol] Budget type (see #within_budget?)
        # @return [Numeric, nil]
        def remaining_budget(type: :daily_cost)
          case type
          when :daily_cost
            effective_daily_limit && (ensure_daily_reset!; effective_daily_limit - daily_cost_spent)
          when :monthly_cost
            effective_monthly_limit && (ensure_monthly_reset!; effective_monthly_limit - monthly_cost_spent)
          when :daily_tokens
            effective_daily_token_limit && (ensure_daily_reset!; effective_daily_token_limit - daily_tokens_used)
          when :monthly_tokens
            effective_monthly_token_limit && (ensure_monthly_reset!; effective_monthly_token_limit - monthly_tokens_used)
          when :daily_executions
            effective_daily_execution_limit && (ensure_daily_reset!; effective_daily_execution_limit - daily_executions_count)
          when :monthly_executions
            effective_monthly_execution_limit && (ensure_monthly_reset!; effective_monthly_execution_limit - monthly_executions_count)
          end
        end

        # Check budget and raise if exceeded (for hard enforcement)
        #
        # @param agent_type [String] The agent class name
        # @raise [BudgetExceededError] If hard enforcement and over budget
        def check_budget!(agent_type = nil)
          return unless budgets_enabled?
          return unless hard_enforcement?

          ensure_daily_reset!
          ensure_monthly_reset!

          if effective_daily_limit && daily_cost_spent >= effective_daily_limit
            raise Reliability::BudgetExceededError.new(
              :global_daily, effective_daily_limit, daily_cost_spent, tenant_id: tenant_id
            )
          end

          if effective_monthly_limit && monthly_cost_spent >= effective_monthly_limit
            raise Reliability::BudgetExceededError.new(
              :global_monthly, effective_monthly_limit, monthly_cost_spent, tenant_id: tenant_id
            )
          end

          if effective_daily_token_limit && daily_tokens_used >= effective_daily_token_limit
            raise Reliability::BudgetExceededError.new(
              :global_daily_tokens, effective_daily_token_limit, daily_tokens_used, tenant_id: tenant_id
            )
          end

          if effective_monthly_token_limit && monthly_tokens_used >= effective_monthly_token_limit
            raise Reliability::BudgetExceededError.new(
              :global_monthly_tokens, effective_monthly_token_limit, monthly_tokens_used, tenant_id: tenant_id
            )
          end

          if effective_daily_execution_limit && daily_executions_count >= effective_daily_execution_limit
            raise Reliability::BudgetExceededError.new(
              :global_daily_executions, effective_daily_execution_limit, daily_executions_count, tenant_id: tenant_id
            )
          end

          if effective_monthly_execution_limit && monthly_executions_count >= effective_monthly_execution_limit
            raise Reliability::BudgetExceededError.new(
              :global_monthly_executions, effective_monthly_execution_limit, monthly_executions_count, tenant_id: tenant_id
            )
          end
        end

        # Get full budget status using counter columns
        #
        # @return [Hash] Budget status with usage information
        def budget_status
          ensure_daily_reset!
          ensure_monthly_reset!

          {
            enabled: budgets_enabled?,
            enforcement: effective_enforcement,
            global_daily: budget_status_for(effective_daily_limit, daily_cost_spent),
            global_monthly: budget_status_for(effective_monthly_limit, monthly_cost_spent),
            global_daily_tokens: budget_status_for(effective_daily_token_limit, daily_tokens_used),
            global_monthly_tokens: budget_status_for(effective_monthly_token_limit, monthly_tokens_used),
            global_daily_executions: budget_status_for(effective_daily_execution_limit, daily_executions_count),
            global_monthly_executions: budget_status_for(effective_monthly_execution_limit, monthly_executions_count)
          }
        end

        # Individual budget check methods

        def within_daily_cost_budget?
          ensure_daily_reset!
          effective_daily_limit.nil? || daily_cost_spent < effective_daily_limit
        end

        def within_monthly_cost_budget?
          ensure_monthly_reset!
          effective_monthly_limit.nil? || monthly_cost_spent < effective_monthly_limit
        end

        def within_daily_token_budget?
          ensure_daily_reset!
          effective_daily_token_limit.nil? || daily_tokens_used < effective_daily_token_limit
        end

        def within_monthly_token_budget?
          ensure_monthly_reset!
          effective_monthly_token_limit.nil? || monthly_tokens_used < effective_monthly_token_limit
        end

        def within_daily_execution_budget?
          ensure_daily_reset!
          effective_daily_execution_limit.nil? || daily_executions_count < effective_daily_execution_limit
        end

        def within_monthly_execution_budget?
          ensure_monthly_reset!
          effective_monthly_execution_limit.nil? || monthly_executions_count < effective_monthly_execution_limit
        end

        # Convert to config hash for BudgetTracker
        #
        # @return [Hash] Budget configuration hash
        def to_budget_config
          {
            enabled: budgets_enabled?,
            enforcement: effective_enforcement,
            # Cost limits
            global_daily: effective_daily_limit,
            global_monthly: effective_monthly_limit,
            per_agent_daily: merged_per_agent_daily,
            per_agent_monthly: merged_per_agent_monthly,
            # Token limits
            global_daily_tokens: effective_daily_token_limit,
            global_monthly_tokens: effective_monthly_token_limit,
            # Execution limits
            global_daily_executions: effective_daily_execution_limit,
            global_monthly_executions: effective_monthly_execution_limit
          }
        end

        private

        # Returns the global budgets configuration
        #
        # @return [Hash, nil]
        def global_config
          RubyLLM::Agents.configuration.budgets
        end

        # Merges per-agent daily limits with global defaults
        #
        # @return [Hash]
        def merged_per_agent_daily
          return per_agent_daily || {} unless inherit_global_defaults

          (global_config&.dig(:per_agent_daily) || {}).merge(per_agent_daily || {})
        end

        # Merges per-agent monthly limits with global defaults
        #
        # @return [Hash]
        def merged_per_agent_monthly
          return per_agent_monthly || {} unless inherit_global_defaults

          (global_config&.dig(:per_agent_monthly) || {}).merge(per_agent_monthly || {})
        end

        # Builds a status hash for a single budget dimension
        #
        # @param limit [Numeric, nil] The configured limit
        # @param current [Numeric] The current usage
        # @return [Hash, nil]
        def budget_status_for(limit, current)
          return nil unless limit

          {
            limit: limit,
            current_spend: current,
            remaining: [limit - current, 0].max,
            percentage_used: (current.to_f / limit * 100).round(1)
          }
        end
      end
    end
  end
end
