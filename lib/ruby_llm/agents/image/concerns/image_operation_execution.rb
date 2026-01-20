# frozen_string_literal: true

require "digest"

module RubyLLM
  module Agents
    module Concerns
      # Shared execution logic for all image operation classes
      #
      # Provides common functionality like tenant resolution, budget tracking,
      # caching, and execution recording that are shared across ImageVariator,
      # ImageEditor, ImageTransformer, and ImageUpscaler.
      #
      module ImageOperationExecution
        private

        # Resolve tenant from options
        def resolve_tenant_context!
          tenant = options[:tenant]
          return unless tenant

          @tenant_id = case tenant
                       when Hash then tenant[:id]
                       when Integer, String then tenant
                       else
                         tenant.try(:llm_tenant_id) || tenant.try(:id)
                       end
        end

        # Check budget before execution
        def check_budget!
          BudgetTracker.check!(
            agent_type: self.class.name,
            tenant_id: @tenant_id,
            execution_type: execution_type
          )
        end

        # Override in subclasses to specify execution type
        def execution_type
          raise NotImplementedError, "Subclasses must implement #execution_type"
        end

        # Caching support

        def cache_enabled?
          self.class.cache_enabled? && !options[:skip_cache]
        end

        def cache_key_components
          raise NotImplementedError, "Subclasses must implement #cache_key_components"
        end

        def cache_key
          components = ["ruby_llm_agents"] + cache_key_components
          components.join(":")
        end

        def check_cache(result_class)
          return nil unless defined?(Rails) && Rails.cache

          cached_data = Rails.cache.read(cache_key)
          return nil unless cached_data

          result_class.from_cache(cached_data)
        end

        def write_cache(result)
          return unless defined?(Rails) && Rails.cache
          return unless result.success?

          Rails.cache.write(cache_key, result.to_cache, expires_in: self.class.cache_ttl)
        end

        # Execution tracking

        def execution_tracking_enabled?
          config.track_image_generation
        end

        def record_execution(result)
          return unless defined?(RubyLLM::Agents::Execution)

          execution_data = build_execution_data(result)

          if config.async_logging && defined?(ExecutionLoggerJob)
            ExecutionLoggerJob.perform_later(execution_data)
          else
            RubyLLM::Agents::Execution.create!(execution_data)
          end
        rescue StandardError => e
          Rails.logger.error("[RubyLLM::Agents] Failed to record #{execution_type} execution: #{e.message}") if defined?(Rails)
        end

        def record_failed_execution(error, started_at)
          return unless defined?(RubyLLM::Agents::Execution)

          execution_data = build_failed_execution_data(error, started_at)

          if config.async_logging && defined?(ExecutionLoggerJob)
            ExecutionLoggerJob.perform_later(execution_data)
          else
            RubyLLM::Agents::Execution.create!(execution_data)
          end
        rescue StandardError => e
          Rails.logger.error("[RubyLLM::Agents] Failed to record failed #{execution_type} execution: #{e.message}") if defined?(Rails)
        end

        def build_execution_data(result)
          {
            agent_type: self.class.name,
            tenant_id: @tenant_id,
            execution_type: execution_type,
            model_id: result.model_id,
            status: "success",
            input_tokens: 0,
            output_tokens: 0,
            total_cost: result.total_cost,
            duration_ms: result.duration_ms,
            started_at: result.started_at,
            completed_at: result.completed_at,
            metadata: build_execution_metadata(result)
          }
        end

        def build_failed_execution_data(error, started_at)
          {
            agent_type: self.class.name,
            tenant_id: @tenant_id,
            execution_type: execution_type,
            model_id: resolve_model,
            status: "error",
            input_tokens: 0,
            output_tokens: 0,
            total_cost: 0,
            duration_ms: ((Time.current - started_at) * 1000).round,
            started_at: started_at,
            completed_at: Time.current,
            error_class: error.class.name,
            error_message: error.message.truncate(1000),
            metadata: {}
          }
        end

        def build_execution_metadata(result)
          { count: result.count }
        end

        def budget_tracking_enabled?
          config.budgets_enabled? && defined?(BudgetTracker)
        end

        def config
          RubyLLM::Agents.configuration
        end

        # Model resolution with alias support
        def resolve_model
          model = options[:model] || self.class.model
          config.image_model_aliases&.dig(model.to_sym) || model
        end
      end
    end
  end
end
