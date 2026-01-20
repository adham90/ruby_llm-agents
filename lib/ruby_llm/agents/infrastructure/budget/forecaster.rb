# frozen_string_literal: true

module RubyLLM
  module Agents
    module Budget
      # Budget forecasting based on current spending trends
      #
      # @api private
      module Forecaster
        class << self
          # Calculates budget forecasts based on current spending trends
          #
          # @param tenant_id [String, nil] The tenant identifier
          # @param budget_config [Hash] Budget configuration
          # @return [Hash, nil] Forecast information
          def calculate_forecast(tenant_id: nil, budget_config:)
            return nil unless budget_config[:enabled]
            return nil unless budget_config[:global_daily] || budget_config[:global_monthly]

            daily_current = BudgetQuery.current_spend(:global, :daily, tenant_id: tenant_id)
            monthly_current = BudgetQuery.current_spend(:global, :monthly, tenant_id: tenant_id)

            # Calculate hours elapsed today and days elapsed this month
            hours_elapsed = Time.current.hour + (Time.current.min / 60.0)
            hours_elapsed = [hours_elapsed, 1].max # Avoid division by zero
            days_in_month = Time.current.end_of_month.day
            day_of_month = Time.current.day
            days_elapsed = day_of_month - 1 + (hours_elapsed / 24.0)
            days_elapsed = [days_elapsed, 1].max

            forecast = {}

            # Daily forecast
            if budget_config[:global_daily]
              daily_rate = daily_current / hours_elapsed
              projected_daily = daily_rate * 24
              forecast[:daily] = {
                current: daily_current.round(4),
                projected: projected_daily.round(4),
                limit: budget_config[:global_daily],
                on_track: projected_daily <= budget_config[:global_daily],
                hours_remaining: (24 - hours_elapsed).round(1),
                rate_per_hour: daily_rate.round(6)
              }
            end

            # Monthly forecast
            if budget_config[:global_monthly]
              monthly_rate = monthly_current / days_elapsed
              projected_monthly = monthly_rate * days_in_month
              days_remaining = days_in_month - day_of_month
              forecast[:monthly] = {
                current: monthly_current.round(4),
                projected: projected_monthly.round(4),
                limit: budget_config[:global_monthly],
                on_track: projected_monthly <= budget_config[:global_monthly],
                days_remaining: days_remaining,
                rate_per_day: monthly_rate.round(4)
              }
            end

            forecast.presence
          end
        end
      end
    end
  end
end
