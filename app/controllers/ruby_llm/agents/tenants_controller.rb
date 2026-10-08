# frozen_string_literal: true

module RubyLLM
  module Agents
    # Controller for managing tenant budgets
    #
    # Provides CRUD operations for viewing and editing tenant budget
    # configurations, including cost limits and token limits.
    #
    # @see TenantBudget For budget configuration model
    # @api private
    class TenantsController < ApplicationController
      TENANT_SORTABLE_COLUMNS = %w[name enforcement daily_limit monthly_limit].freeze
      DEFAULT_TENANT_SORT_COLUMN = "name"
      DEFAULT_TENANT_SORT_DIRECTION = "asc"

      # Lists all tenant budgets with optional search and sorting
      #
      # @return [void]
      def index
        @sort_params = parse_tenant_sort_params
        # Eager-load tenant_record so display_name's live name resolution does
        # not issue a query per row.
        scope = TenantBudget.all.includes(:tenant_record)

        if params[:q].present?
          @search_query = params[:q].to_s.strip
          escaped = TenantBudget.sanitize_sql_like(@search_query)
          scope = scope.where(
            "tenant_id LIKE :q OR name LIKE :q OR tenant_record_type LIKE :q OR tenant_record_id LIKE :q",
            q: "%#{escaped}%"
          )
        end

        @tenants = scope.order(@sort_params[:column] => @sort_params[:direction].to_sym)
        preload_tenant_index_data
      end

      # Shows a single tenant's budget details
      #
      # Usage figures cover the current month, from one grouped scan of it
      # (see Execution.breakdown). A tenant's executions are scattered across
      # the whole table, so the all-time versions of these figures were the
      # most expensive queries in the dashboard.
      #
      # @return [void]
      def show
        @tenant = TenantBudget.find(params[:id])
        @executions = tenant_executions(@tenant.tenant_id).preload(:error_detail).recent(10)

        month = Execution::Breakdown.new(cached_tenant_stats(:month) do
          @tenant.executions.where(created_at: Time.current.all_month).breakdown.rows
        end)
        @usage_stats = calculate_usage_stats(@tenant, month)
        @usage_by_agent = month.agent_stats.transform_values do |stats|
          {cost: stats[:total_cost], tokens: stats[:total_tokens], count: stats[:count]}
        end
        @usage_by_model = month.configured_model_usage.to_h do |usage|
          [usage[:model_id], {cost: usage[:cost], tokens: usage[:tokens], count: usage[:runs]}]
        end
        load_tenant_analytics(month)
      end

      # Renders the edit form for a tenant budget
      #
      # @return [void]
      def edit
        @tenant = TenantBudget.find(params[:id])
      end

      # Recalculates budget counters from the executions table
      #
      # @return [void]
      def refresh_counters
        @tenant = TenantBudget.find(params[:id])
        @tenant.refresh_counters!
        redirect_to tenant_path(@tenant), notice: "Counters refreshed"
      end

      # Updates a tenant budget
      #
      # @return [void]
      def update
        @tenant = TenantBudget.find(params[:id])
        attrs = tenant_params
        # Linked tenants derive their name live from the host record, so ignore
        # any submitted name — it would be overwritten on the next record sync.
        attrs = attrs.except(:name) if @tenant.linked?
        if @tenant.update(attrs)
          redirect_to tenant_path(@tenant), notice: "Tenant updated successfully"
        else
          render :edit, status: :unprocessable_entity
        end
      end

      private

      # Strong parameters for tenant budget
      #
      # @return [ActionController::Parameters] Permitted parameters
      def tenant_params
        params.require(:tenant_budget).permit(
          :name, :daily_limit, :monthly_limit,
          :daily_token_limit, :monthly_token_limit,
          :enforcement
        )
      end

      # Returns executions scoped to a specific tenant
      #
      # @param tenant_id [String] The tenant identifier
      # @return [ActiveRecord::Relation] Executions for the tenant
      def tenant_executions(tenant_id)
        Execution.by_tenant(tenant_id)
      end

      # Caches one of the tenant page's figures
      def cached_tenant_stats(name, expires_in: 5.minutes, &block)
        cached_stats(:tenant, @tenant.tenant_id, name, expires_in: expires_in, &block)
      end

      # Calculates usage statistics for a tenant
      #
      # @param tenant [TenantBudget] The tenant budget record
      # @param month [Execution::Breakdown] The tenant's executions this month
      # @return [Hash] Usage statistics; the total_* keys cover this month
      def calculate_usage_stats(tenant, month)
        totals = month.totals
        daily_spend, daily_tokens = tenant_executions(tenant.tenant_id)
          .where("created_at >= ?", Time.current.beginning_of_day)
          .pick(Arel.sql("COALESCE(SUM(total_cost), 0)"), Arel.sql("COALESCE(SUM(total_tokens), 0)"))

        {
          daily_spend: daily_spend,
          monthly_spend: totals[:cost],
          daily_tokens: daily_tokens,
          monthly_tokens: totals[:tokens],
          daily_spend_percentage: percentage_used(daily_spend, tenant.effective_daily_limit),
          monthly_spend_percentage: percentage_used(totals[:cost], tenant.effective_monthly_limit),
          daily_token_percentage: percentage_used(daily_tokens, tenant.effective_daily_token_limit),
          monthly_token_percentage: percentage_used(totals[:tokens], tenant.effective_monthly_token_limit),
          total_executions: totals[:total],
          total_cost: totals[:cost],
          total_tokens: totals[:tokens],
          success_count: totals[:success]
        }
      end

      # Loads trend data and period comparison for the tenant analytics section.
      #
      # @param month [Execution::Breakdown] The tenant's executions this month
      # @return [void]
      def load_tenant_analytics(month)
        # 30-day daily cost/tokens trend
        @daily_trend = cached_tenant_stats(:daily_trend) do
          @tenant.usage_by_day(period: 30.days.ago..Time.current)
        end

        # Period comparison: this month vs last month. Last month no longer
        # changes, so one aggregate of it is kept for an hour.
        totals = month.totals
        last = cached_tenant_stats(:last_month, expires_in: 1.hour) do
          @tenant.executions.where(created_at: 1.month.ago.all_month).totals
        end
        this_month = {cost: totals[:cost], tokens: totals[:tokens], executions: totals[:total]}
        last_month = {cost: last[:total_cost], tokens: last[:total_tokens], executions: last[:total_count]}
        @period_comparison = {
          this_month: this_month,
          last_month: last_month,
          cost_change: percent_change(last_month[:cost], this_month[:cost]),
          tokens_change: percent_change(last_month[:tokens], this_month[:tokens]),
          executions_change: percent_change(last_month[:executions], this_month[:executions]),
          avg_cost_this: (this_month[:executions] > 0) ? (this_month[:cost].to_f / this_month[:executions]) : 0,
          avg_cost_last: (last_month[:executions] > 0) ? (last_month[:cost].to_f / last_month[:executions]) : 0
        }
        @period_comparison[:avg_cost_change] = percent_change(
          @period_comparison[:avg_cost_last], @period_comparison[:avg_cost_this]
        )

        # Error cost: money spent on failed executions this month
        error_cost = month.error_cost
        @error_cost = error_cost[:total_cost]
        @error_count = error_cost[:total_count]
      end

      # Calculates percentage change between two values
      #
      # @return [Float]
      def percent_change(old_val, new_val)
        return 0.0 if old_val.nil? || old_val.to_f.zero?
        ((new_val.to_f - old_val.to_f) / old_val.to_f * 100).round(1)
      end

      # Builds the cost and last-execution lookups for the index view
      #
      # Read from the counter columns each tenant row already carries (they
      # are updated on every execution), rather than by grouping the whole
      # executions table by tenant. Cost is month-to-date; a counter that has
      # not been reset yet this month belongs to an earlier one.
      #
      # @return [void]
      def preload_tenant_index_data
        month_start = Date.current.beginning_of_month

        @tenant_costs = @tenants.to_h do |tenant|
          [tenant.tenant_id, (tenant.monthly_reset_date == month_start) ? tenant.monthly_cost_spent : 0]
        end
        @tenant_last_executions = @tenants.to_h { |tenant| [tenant.tenant_id, tenant.last_execution_at] }
      end

      # Parses and validates sort parameters for tenants list
      #
      # @return [Hash] Contains :column and :direction keys
      def parse_tenant_sort_params
        column = params[:sort].to_s
        direction = params[:direction].to_s.downcase

        {
          column: TENANT_SORTABLE_COLUMNS.include?(column) ? column : DEFAULT_TENANT_SORT_COLUMN,
          direction: %w[asc desc].include?(direction) ? direction : DEFAULT_TENANT_SORT_DIRECTION
        }
      end

      # Calculates percentage used
      #
      # @param current [Numeric] Current usage
      # @param limit [Numeric, nil] The limit
      # @return [Float] Percentage used (0-100+)
      def percentage_used(current, limit)
        return 0 if limit.nil? || limit.to_f <= 0
        (current.to_f / limit.to_f * 100).round(1)
      end
    end
  end
end
