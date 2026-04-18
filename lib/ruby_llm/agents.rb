# frozen_string_literal: true

require "csv"
require "ruby_llm"
require "ruby_llm/schema"

# Core
require_relative "agents/core/version"
require_relative "agents/core/configuration"
require_relative "agents/core/deprecations"
require_relative "agents/core/errors"
require_relative "agents/core/llm_tenant"

# Infrastructure - Reliability
require_relative "agents/infrastructure/reliability"

# Pipeline infrastructure (middleware-based execution)
require_relative "agents/pipeline"

# DSL modules for agent configuration
require_relative "agents/dsl"

# BaseAgent - new middleware-based agent architecture
require_relative "agents/base_agent"

# Streaming events
require_relative "agents/stream_event"

# Tool base class and context for coding agents
require_relative "agents/tool_context"
require_relative "agents/tool"

# Infrastructure - Budget & Utilities
require_relative "agents/infrastructure/circuit_breaker"
require_relative "agents/infrastructure/budget_tracker"
require_relative "agents/infrastructure/alert_manager"
require_relative "agents/infrastructure/attempt_tracker"
require_relative "agents/infrastructure/cache_helper"
require_relative "agents/infrastructure/budget/budget_query"
require_relative "agents/infrastructure/budget/config_resolver"
require_relative "agents/infrastructure/budget/forecaster"
require_relative "agents/infrastructure/budget/spend_recorder"

# Tracking
require_relative "agents/tracker"
require_relative "agents/track_report"

# Results
require_relative "agents/results/trackable"
require_relative "agents/results/base"
require_relative "agents/results/embedding_result"
require_relative "agents/results/transcription_result"
require_relative "agents/results/speech_result"
require_relative "agents/results/image_generation_result"
require_relative "agents/results/image_variation_result"
require_relative "agents/results/image_edit_result"
require_relative "agents/results/image_transform_result"
require_relative "agents/results/image_upscale_result"
require_relative "agents/results/image_analysis_result"
require_relative "agents/results/background_removal_result"
require_relative "agents/results/image_pipeline_result"

# Image concerns (shared DSL/execution for image operations)
require_relative "agents/image/concerns/image_operation_dsl"
require_relative "agents/image/concerns/image_operation_execution"

# Routing concern (classification & routing)
require_relative "agents/routing"

# Text agents
require_relative "agents/text/embedder"

# Audio agents
require_relative "agents/audio/transcriber"
require_relative "agents/audio/speaker"

# Image agents
require_relative "agents/image/generator"
require_relative "agents/image/variator"
require_relative "agents/image/editor"
require_relative "agents/image/transformer"
require_relative "agents/image/upscaler"
require_relative "agents/image/analyzer"
require_relative "agents/image/background_remover"
require_relative "agents/image/pipeline"

# Evaluation framework
require_relative "agents/eval"

# Providers (extends RubyLLM with additional providers)
require_relative "agents/providers/inception"
RubyLLM::Provider.register :inception, RubyLLM::Agents::Providers::Inception

# Rails integration
if defined?(Rails)
  require_relative "agents/core/inflections"
  require_relative "agents/core/instrumentation"
  require_relative "agents/infrastructure/execution_logger_job"
  require_relative "agents/infrastructure/retention_job"
end
require_relative "agents/rails/engine" if defined?(Rails::Engine)

module RubyLLM
  # Agent framework for building LLM-powered agents with observability
  #
  # RubyLLM::Agents provides a DSL for creating agents that interact with
  # large language models, with built-in execution tracking, cost monitoring,
  # and a dashboard for observability.
  #
  # @example Basic configuration
  #   RubyLLM::Agents.configure do |config|
  #     config.default_model = "gpt-4o"
  #     config.async_logging = true
  #   end
  #
  # @example Creating an agent
  #   class SearchAgent < ApplicationAgent
  #     model "gpt-4o"
  #     param :query, required: true
  #
  #     def user_prompt
  #       "Search for: #{query}"
  #     end
  #   end
  #
  #   SearchAgent.call(query: "ruby gems")
  #
  # @see RubyLLM::Agents::Base
  # @see RubyLLM::Agents::Configuration
  module Agents
    class << self
      # Wraps a block of agent calls, collecting all Results and
      # returning an aggregated TrackReport.
      #
      # Shared options (tenant, tags, request_id) are injected into
      # every agent instantiated inside the block unless overridden.
      #
      # @param tenant [Hash, Object, nil] Shared tenant for all calls
      # @param request_id [String, nil] Shared request ID (auto-generated if nil)
      # @param tags [Hash] Tags merged into each execution's metadata
      # @param defaults [Hash] Additional shared options for agents
      # @yield Block containing agent calls to track
      # @return [TrackReport] Aggregated report of all calls
      #
      # @example Basic usage
      #   report = RubyLLM::Agents.track do
      #     ChatAgent.call(query: "hello")
      #     SummaryAgent.call(text: "...")
      #   end
      #   report.total_cost  # => 0.015
      #
      # @example With shared tenant
      #   report = RubyLLM::Agents.track(tenant: current_user) do
      #     AgentA.call(query: "test")
      #   end
      def track(tenant: nil, request_id: nil, tags: {}, **defaults)
        defaults[:tenant] = tenant if tenant
        tracker = Tracker.new(defaults: defaults, request_id: request_id, tags: tags)

        # Stack trackers for nesting support
        previous_tracker = Thread.current[:ruby_llm_agents_tracker]
        Thread.current[:ruby_llm_agents_tracker] = tracker

        started_at = Time.current
        value = nil
        error = nil

        begin
          value = yield
        rescue => e
          error = e
        end

        completed_at = Time.current

        report = TrackReport.new(
          value: value,
          error: error,
          results: tracker.results,
          request_id: tracker.request_id,
          started_at: started_at,
          completed_at: completed_at
        )

        # Bubble results up to parent tracker if nested
        if previous_tracker
          tracker.results.each { |r| previous_tracker << r }
        end

        report
      ensure
        Thread.current[:ruby_llm_agents_tracker] = previous_tracker
      end

      # Returns the global configuration instance
      #
      # @return [Configuration] The configuration object
      def configuration
        @configuration ||= Configuration.new
      end

      # Yields the configuration for modification
      #
      # @yield [Configuration] The configuration object
      # @return [void]
      # @example
      #   RubyLLM::Agents.configure do |config|
      #     config.default_model = "claude-3-sonnet"
      #   end
      def configure
        yield(configuration)
      end

      # Resets configuration to defaults
      #
      # Primarily used for testing to ensure clean state.
      #
      # @return [Configuration] A new configuration instance
      # @api private
      def reset_configuration!
        @configuration = Configuration.new
      end

      # ============================================================
      # Convenience Query API
      # ============================================================
      # These methods provide quick access to execution data without
      # needing to reference model classes directly.

      # Returns a chainable scope of all executions.
      #
      # @return [ActiveRecord::Relation] All executions
      #
      # @example Recent successful executions
      #   RubyLLM::Agents.executions.successful.recent(10)
      #
      # @example Filter by agent
      #   RubyLLM::Agents.executions.by_agent("ChatAgent").today
      def executions
        Execution.all
      end

      # Returns a usage summary for a given period.
      #
      # @param period [Symbol, Range] :today, :yesterday, :this_week, :this_month,
      #   :last_7_days, :last_30_days, or a custom Time range
      # @param agent [String, Class, nil] Optional agent class or name to filter by
      # @param tenant [String, Object, nil] Optional tenant ID or object to filter by
      # @return [Hash] Usage summary with keys:
      #   :executions, :successful, :failed, :success_rate,
      #   :total_cost, :total_tokens, :avg_duration_ms, :avg_cost
      #
      # @example Global usage today
      #   RubyLLM::Agents.usage(period: :today)
      #
      # @example Per-agent usage
      #   RubyLLM::Agents.usage(period: :this_month, agent: "ChatAgent")
      #
      # @example Per-tenant usage
      #   RubyLLM::Agents.usage(period: :this_week, tenant: current_user)
      def usage(period: :today, agent: nil, tenant: nil)
        scope = scope_for_period(Execution, period)
        scope = scope.by_agent(agent_name_for(agent)) if agent
        scope = scope_for_tenant(scope, tenant) if tenant

        total = scope.count
        successful = scope.successful.count

        {
          executions: total,
          successful: successful,
          failed: scope.failed.count,
          success_rate: total.zero? ? 0.0 : (successful.to_f / total * 100).round(1),
          total_cost: scope.sum(:total_cost),
          total_tokens: scope.sum(:total_tokens),
          avg_duration_ms: scope.average(:duration_ms)&.round,
          avg_cost: total.zero? ? 0 : (scope.sum(:total_cost).to_f / total).round(6)
        }
      end

      # Returns cost breakdown by agent for a period.
      #
      # @param period [Symbol, Range] Time period (see #usage)
      # @param tenant [String, Object, nil] Optional tenant filter
      # @return [Hash{String => Hash}] Agent name => { cost:, count:, avg_cost: }
      #
      # @example
      #   RubyLLM::Agents.costs(period: :this_month)
      #   # => { "ChatAgent" => { cost: 12.50, count: 1000, avg_cost: 0.0125 } }
      def costs(period: :today, tenant: nil)
        scope = scope_for_period(Execution, period)
        scope = scope_for_tenant(scope, tenant) if tenant

        scope.group(:agent_type).pluck(
          :agent_type,
          Arel.sql("COUNT(*)"),
          Arel.sql("SUM(total_cost)"),
          Arel.sql("AVG(total_cost)")
        ).each_with_object({}) do |(agent, count, total, avg), hash|
          hash[agent] = {
            cost: total&.to_f&.round(6) || 0,
            count: count,
            avg_cost: avg&.to_f&.round(6) || 0
          }
        end
      end

      # Returns all registered agents with their stats.
      #
      # @return [Array<Hash>] Agent info with name, model, stats, etc.
      #
      # @example
      #   RubyLLM::Agents.agents
      #   # => [{ name: "ChatAgent", active: true, model: "gpt-4o", ... }]
      def agents
        AgentRegistry.all_with_details
      end

      # Returns a tenant's usage data.
      #
      # @param tenant [String, Object] Tenant ID or object with llm_tenant_id
      # @return [RubyLLM::Agents::Tenant, nil] The tenant record
      #
      # @example
      #   tenant = RubyLLM::Agents.tenant_for(current_user)
      #   tenant.cost_today       # => 0.42
      #   tenant.budget_status    # => { enabled: true, enforcement: :soft, ... }
      def tenant_for(tenant)
        Tenant.for(tenant)
      rescue
        nil
      end

      private

      def scope_for_period(model, period)
        case period
        when :today then model.today
        when :yesterday then model.yesterday
        when :this_week then model.this_week
        when :this_month then model.this_month
        when :last_7_days then model.last_n_days(7)
        when :last_30_days then model.last_n_days(30)
        when Range then model.where(created_at: period)
        else model.all
        end
      end

      def scope_for_tenant(scope, tenant)
        tenant_id = case tenant
        when String then tenant
        else
          tenant.try(:llm_tenant_id) || tenant.try(:tenant_id) || tenant.try(:id)&.to_s
        end
        scope.by_tenant(tenant_id)
      end

      def agent_name_for(agent)
        agent.is_a?(String) ? agent : agent.name
      end

      public

      # Renames an agent in the database, updating execution records and
      # tenant budget configuration keys
      #
      # @param old_name [String] The previous agent class name
      # @param to [String] The new agent class name
      # @param dry_run [Boolean] If true, returns counts without modifying data
      # @return [Hash] Summary of affected records
      #
      # @example Rename an agent
      #   RubyLLM::Agents.rename_agent("CustomerSupportAgent", to: "SupportBot")
      #   # => { executions_updated: 1432, tenants_updated: 3 }
      #
      # @example Dry run first
      #   RubyLLM::Agents.rename_agent("CustomerSupportAgent", to: "SupportBot", dry_run: true)
      #   # => { executions_affected: 1432, tenants_affected: 3 }
      def rename_agent(old_name, to:, dry_run: false)
        old_name = old_name.to_s
        new_name = to.to_s

        raise ArgumentError, "old_name and new name must be different" if old_name == new_name
        raise ArgumentError, "old_name cannot be blank" if old_name.blank?
        raise ArgumentError, "new name cannot be blank" if new_name.blank?

        execution_scope = Execution.where(agent_type: old_name)
        execution_count = execution_scope.count

        tenant_count = 0
        if defined?(Tenant) && Tenant.table_exists?
          Tenant.find_each do |tenant|
            changed = false
            %w[per_agent_daily per_agent_monthly].each do |field|
              hash = tenant.send(field)
              next unless hash.is_a?(Hash) && hash.key?(old_name)
              changed = true
              break
            end
            tenant_count += 1 if changed
          end
        end

        if dry_run
          {executions_affected: execution_count, tenants_affected: tenant_count}
        else
          executions_updated = execution_scope.update_all(agent_type: new_name)

          tenants_updated = 0
          if defined?(Tenant) && Tenant.table_exists?
            Tenant.find_each do |tenant|
              changed = false
              %w[per_agent_daily per_agent_monthly].each do |field|
                hash = tenant.send(field)
                next unless hash.is_a?(Hash) && hash.key?(old_name)
                hash[new_name] = hash.delete(old_name)
                tenant.send(:"#{field}=", hash)
                changed = true
              end
              if changed
                tenant.save!
                tenants_updated += 1
              end
            end
          end

          {executions_updated: executions_updated, tenants_updated: tenants_updated}
        end
      end
    end
  end
end
