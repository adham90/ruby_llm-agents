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
        scope = TenantBudget.all

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
      # @return [void]
      def show
        @tenant = TenantBudget.find(params[:id])
        @executions = tenant_executions(@tenant.tenant_id).recent.limit(10)
        @usage_stats = calculate_usage_stats(@tenant)
        @usage_by_agent = @tenant.usage_by_agent(period: nil)
        @usage_by_model = @tenant.usage_by_model(period: nil)
        load_tenant_analytics
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
        if @tenant.update(tenant_params)
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

      # Calculates usage statistics for a tenant
      #
      # @param tenant [TenantBudget] The tenant budget record
      # @return [Hash] Usage statistics
      def calculate_usage_stats(tenant)
        scope = tenant_executions(tenant.tenant_id)
        today_scope = scope.where("created_at >= ?", Time.current.beginning_of_day)
        month_scope = scope.where("created_at >= ?", Time.current.beginning_of_month)

        daily_spend = today_scope.sum(:total_cost) || 0
        monthly_spend = month_scope.sum(:total_cost) || 0
        daily_tokens = today_scope.sum(:total_tokens) || 0
        monthly_tokens = month_scope.sum(:total_tokens) || 0

        {
          daily_spend: daily_spend,
          monthly_spend: monthly_spend,
          daily_tokens: daily_tokens,
          monthly_tokens: monthly_tokens,
          daily_spend_percentage: percentage_used(daily_spend, tenant.effective_daily_limit),
          monthly_spend_percentage: percentage_used(monthly_spend, tenant.effective_monthly_limit),
          daily_token_percentage: percentage_used(daily_tokens, tenant.effective_daily_token_limit),
          monthly_token_percentage: percentage_used(monthly_tokens, tenant.effective_monthly_token_limit),
          total_executions: scope.count,
          total_cost: scope.sum(:total_cost) || 0,
          total_tokens: scope.sum(:total_tokens) || 0
        }
      end

      # Loads trend data and period comparison for the tenant analytics section.
      #
      # @return [void]
      def load_tenant_analytics
        # 30-day daily cost/tokens trend
        @daily_trend = @tenant.usage_by_day(period: 30.days.ago..Time.current)

        # Period comparison: this month vs last month
        this_month = @tenant.usage_summary(period: :this_month)
        last_month = @tenant.usage_summary(period: :last_month)
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

        # Error cost: money spent on failed executions
        error_scope = @tenant.executions.where(status: "error")
        @error_cost = error_scope.sum(:total_cost) || 0
        @error_count = error_scope.count
      end

      # Calculates percentage change between two values
      #
      # @return [Float]
      def percent_change(old_val, new_val)
        return 0.0 if old_val.nil? || old_val.to_f.zero?
        ((new_val.to_f - old_val.to_f) / old_val.to_f * 100).round(1)
      end

      # Preloads cost and last-execution data for all tenants in one query each,
      # avoiding N+1 queries in the index view.
      #
      # @return [void]
      def preload_tenant_index_data
        @tenant_costs = {}
        @tenant_last_executions = {}
        tenant_ids = @tenants.map(&:tenant_id)
        return if tenant_ids.empty?

        # Batch-load total cost per tenant
        @tenant_costs = Execution.where(tenant_id: tenant_ids)
          .group(:tenant_id)
          .sum(:total_cost)

        # Batch-load last execution time per tenant
        @tenant_last_executions = Execution.where(tenant_id: tenant_ids)
          .group(:tenant_id)
          .maximum(:created_at)
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
