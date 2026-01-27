# frozen_string_literal: true

require "digest"

module RubyLLM
  module Agents
    class ImagePipeline
      # Execution logic for image pipelines
      #
      # Handles step execution, context passing between steps,
      # error handling, caching, and execution tracking.
      #
      module Execution
        private

        def execute
          @started_at = Time.current

          resolve_tenant_context!
          check_budget! if budget_tracking_enabled?

          # Check cache for deterministic pipelines
          if cache_enabled?
            cached = check_cache
            return cached if cached
          end

          # Run before callbacks
          run_callbacks(:before)

          # Execute pipeline steps
          current_image = options[:image]
          @step_results = []

          self.class.steps.each do |step_def|
            # Check if step should run
            next unless should_run_step?(step_def)

            result = execute_step(step_def, current_image)
            @step_results << { name: step_def[:name], type: step_def[:type], result: result }

            # Update context with result
            @context[step_def[:name]] = result

            if result.error?
              break if self.class.stop_on_error?
            else
              # Pass image to next step (except for analyze steps which don't produce images)
              current_image = extract_image_from_result(result) unless step_def[:type] == :analyzer
            end
          end

          # Build result
          result = build_result

          # Run after callbacks
          run_callbacks(:after, result)

          # Cache successful results
          write_cache(result) if cache_enabled? && result.success?

          # Track execution
          record_execution(result) if execution_tracking_enabled?

          result
        rescue StandardError => e
          record_failed_execution(e) if execution_tracking_enabled?
          build_error_result(e)
        end

        def should_run_step?(step_def)
          config = step_def[:config]

          # Check :if condition
          if config[:if]
            return false unless evaluate_condition(config[:if])
          end

          # Check :unless condition
          if config[:unless]
            return false if evaluate_condition(config[:unless])
          end

          true
        end

        def evaluate_condition(condition)
          case condition
          when Proc
            condition.call(@context)
          when Symbol
            respond_to?(condition, true) ? send(condition) : @context[condition]
          else
            condition
          end
        end

        def execute_step(step_def, current_image)
          step_type = step_def[:type]
          step_config = step_def[:config]
          step_class = step_config[step_type]

          # Build options for the step (exclude meta options)
          step_options = step_config.except(:if, :unless, step_type)
          step_options[:tenant] = options[:tenant] if options[:tenant]

          case step_type
          when :generator
            execute_generator(step_class, step_options)
          when :variator
            execute_variator(step_class, current_image, step_options)
          when :editor
            execute_editor(step_class, current_image, step_options)
          when :transformer
            execute_transformer(step_class, current_image, step_options)
          when :upscaler
            execute_upscaler(step_class, current_image, step_options)
          when :analyzer
            execute_analyzer(step_class, current_image, step_options)
          when :remover
            execute_remover(step_class, current_image, step_options)
          else
            raise ArgumentError, "Unknown step type: #{step_type}"
          end
        end

        def execute_generator(step_class, step_options)
          prompt = step_options.delete(:prompt) || options[:prompt]
          raise ArgumentError, "Generator step requires a prompt" unless prompt

          step_class.call(prompt: prompt, **step_options)
        end

        def execute_variator(step_class, image, step_options)
          raise ArgumentError, "Variator step requires an input image" unless image

          step_class.call(image: image, **step_options)
        end

        def execute_editor(step_class, image, step_options)
          raise ArgumentError, "Editor step requires an input image" unless image

          mask = step_options.delete(:mask) || options[:mask]
          prompt = step_options.delete(:prompt) || options[:edit_prompt]
          raise ArgumentError, "Editor step requires a mask and prompt" unless mask && prompt

          step_class.call(image: image, mask: mask, prompt: prompt, **step_options)
        end

        def execute_transformer(step_class, image, step_options)
          raise ArgumentError, "Transformer step requires an input image" unless image

          prompt = step_options.delete(:prompt) || options[:transform_prompt]
          raise ArgumentError, "Transformer step requires a prompt" unless prompt

          step_class.call(image: image, prompt: prompt, **step_options)
        end

        def execute_upscaler(step_class, image, step_options)
          raise ArgumentError, "Upscaler step requires an input image" unless image

          step_class.call(image: image, **step_options)
        end

        def execute_analyzer(step_class, image, step_options)
          raise ArgumentError, "Analyzer step requires an input image" unless image

          step_class.call(image: image, **step_options)
        end

        def execute_remover(step_class, image, step_options)
          raise ArgumentError, "Remover step requires an input image" unless image

          step_class.call(image: image, **step_options)
        end

        def extract_image_from_result(result)
          # Try common methods for getting image data
          if result.respond_to?(:url) && result.url
            result.url
          elsif result.respond_to?(:data) && result.data
            result.data
          elsif result.respond_to?(:to_blob)
            result.to_blob
          else
            result
          end
        end

        def build_result
          ImagePipelineResult.new(
            step_results: @step_results,
            started_at: @started_at,
            completed_at: Time.current,
            tenant_id: @tenant_id,
            pipeline_class: self.class.name,
            context: @context
          )
        end

        def build_error_result(error)
          ImagePipelineResult.new(
            step_results: @step_results || [],
            started_at: @started_at || Time.current,
            completed_at: Time.current,
            tenant_id: @tenant_id,
            pipeline_class: self.class.name,
            context: @context || {},
            error_class: error.class.name,
            error_message: error.message
          )
        end

        # Tenant resolution

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

        # Budget tracking

        def budget_tracking_enabled?
          config.budgets_enabled? && defined?(BudgetTracker)
        end

        def check_budget!
          BudgetTracker.check_budget!(
            self.class.name,
            tenant_id: @tenant_id
          )
        end

        # Caching

        def cache_enabled?
          self.class.cache_enabled? && !options[:skip_cache]
        end

        def cache_key
          components = [
            "ruby_llm_agents",
            "image_pipeline",
            self.class.name,
            self.class.version,
            Digest::SHA256.hexdigest(cache_key_input)
          ]
          components.join(":")
        end

        def cache_key_input
          # Include relevant options and step configuration
          {
            prompt: options[:prompt],
            image: options[:image].to_s,
            steps: self.class.steps.map { |s| [s[:name], s[:type]] }
          }.to_json
        end

        def check_cache
          return nil unless defined?(Rails) && Rails.cache

          cached_data = Rails.cache.read(cache_key)
          return nil unless cached_data

          ImagePipelineResult.from_cache(cached_data)
        end

        def write_cache(result)
          return unless defined?(Rails) && Rails.cache
          return unless result.success?

          Rails.cache.write(cache_key, result.to_cache, expires_in: self.class.cache_ttl)
        end

        # Callbacks

        def run_callbacks(type, *args)
          callbacks = self.class.callbacks[type] || []

          callbacks.each do |callback|
            case callback
            when Symbol
              send(callback, *args)
            when Proc
              instance_exec(*args, &callback)
            end
          end
        end

        # Execution tracking

        def execution_tracking_enabled?
          config.track_image_generation
        end

        def record_execution(result)
          return unless defined?(RubyLLM::Agents::Execution)

          execution_data = {
            agent_type: self.class.name,
            tenant_id: @tenant_id,
            execution_type: "image_pipeline",
            model_id: result.primary_model_id,
            status: result.success? ? "success" : "error",
            input_tokens: 0,
            output_tokens: 0,
            total_cost: result.total_cost,
            duration_ms: result.duration_ms,
            started_at: result.started_at,
            completed_at: result.completed_at,
            metadata: {
              step_count: result.step_count,
              successful_steps: result.successful_step_count,
              failed_steps: result.failed_step_count
            }
          }

          if config.async_logging && defined?(ExecutionLoggerJob)
            ExecutionLoggerJob.perform_later(execution_data)
          else
            RubyLLM::Agents::Execution.create!(execution_data)
          end
        rescue StandardError => e
          Rails.logger.error("[RubyLLM::Agents] Failed to record pipeline execution: #{e.message}") if defined?(Rails)
        end

        def record_failed_execution(error)
          return unless defined?(RubyLLM::Agents::Execution)

          execution_data = {
            agent_type: self.class.name,
            tenant_id: @tenant_id,
            execution_type: "image_pipeline",
            model_id: nil,
            status: "error",
            input_tokens: 0,
            output_tokens: 0,
            total_cost: calculate_partial_cost,
            duration_ms: ((@started_at ? (Time.current - @started_at) : 0) * 1000).round,
            started_at: @started_at || Time.current,
            completed_at: Time.current,
            error_class: error.class.name,
            error_message: error.message.truncate(1000),
            metadata: {
              step_count: self.class.steps.size,
              completed_steps: @step_results&.size || 0
            }
          }

          if config.async_logging && defined?(ExecutionLoggerJob)
            ExecutionLoggerJob.perform_later(execution_data)
          else
            RubyLLM::Agents::Execution.create!(execution_data)
          end
        rescue StandardError => e
          Rails.logger.error("[RubyLLM::Agents] Failed to record failed pipeline execution: #{e.message}") if defined?(Rails)
        end

        def calculate_partial_cost
          return 0 unless @step_results

          @step_results.sum do |step|
            step[:result]&.total_cost || 0
          end
        end

        def config
          RubyLLM::Agents.configuration
        end
      end
    end
  end
end
