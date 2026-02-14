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
          scope = scope.where(
            "tenant_id LIKE :q OR name LIKE :q",
            q: "%#{TenantBudget.sanitize_sql_like(@search_query)}%"
          )
        end

        @tenants = scope.order(@sort_params[:column] => @sort_params[:direction].to_sym)
      end

      # Shows a single tenant's budget details
      #
      # @return [void]
      def show
        @tenant = TenantBudget.find(params[:id])
        @executions = tenant_executions(@tenant.tenant_id).recent.limit(10)
        @usage_stats = calculate_usage_stats(@tenant)
      end

      # Renders the edit form for a tenant budget
      #
      # @return [void]
      def edit
        @tenant = TenantBudget.find(params[:id])
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
