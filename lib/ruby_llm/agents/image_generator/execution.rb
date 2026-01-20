# frozen_string_literal: true

require "digest"

module RubyLLM
  module Agents
    class ImageGenerator
      # Execution logic for image generators
      #
      # Handles prompt validation, content policy checks, budget tracking,
      # caching, image generation via RubyLLM.paint, and result building.
      #
      module Execution
        # Execute the image generation pipeline
        #
        # @return [ImageGenerationResult] The result containing generated images
        def execute
          started_at = Time.current

          resolve_tenant_context!
          check_budget! if budget_tracking_enabled?
          validate_prompt!
          validate_content_policy!

          # Check cache for single image requests
          cached = check_cache if cache_enabled? && single_image_request?
          return cached if cached

          # Generate image(s)
          images = generate_images

          # Build result
          result = build_result(
            images: images,
            started_at: started_at,
            completed_at: Time.current
          )

          # Cache single image results
          write_cache(result) if cache_enabled? && single_image_request?

          # Track execution
          record_execution(result) if execution_tracking_enabled?

          result
        rescue StandardError => e
          record_failed_execution(e, started_at) if execution_tracking_enabled?
          build_error_result(e, started_at)
        end

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
            execution_type: "image_generation"
          )
        end

        # Validate the prompt is present and within limits
        def validate_prompt!
          raise ArgumentError, "Prompt cannot be blank" if prompt.nil? || prompt.strip.empty?

          max_length = config.max_image_prompt_length || 4000
          if prompt.length > max_length
            raise ArgumentError, "Prompt exceeds maximum length of #{max_length} characters"
          end
        end

        # Validate prompt against content policy
        def validate_content_policy!
          policy = self.class.content_policy
          return if policy == :none || policy == :standard

          ContentPolicy.validate!(prompt, policy)
        end

        # Generate images using RubyLLM.paint
        def generate_images
          count = resolve_count

          Array.new(count) do
            paint_options = build_paint_options
            RubyLLM.paint(apply_template(prompt), **paint_options)
          end
        end

        # Build options hash for RubyLLM.paint
        def build_paint_options
          opts = {
            model: resolve_model,
            size: resolve_size
          }

          # Add optional parameters if set
          opts[:quality] = resolve_quality if resolve_quality
          opts[:style] = resolve_style if resolve_style
          opts[:negative_prompt] = resolve_negative_prompt if resolve_negative_prompt
          opts[:seed] = resolve_seed if resolve_seed
          opts[:guidance_scale] = resolve_guidance_scale if resolve_guidance_scale
          opts[:steps] = resolve_steps if resolve_steps
          opts[:assume_model_exists] = true if options[:assume_model_exists]

          opts
        end

        # Apply prompt template if defined
        def apply_template(text)
          template = self.class.try(:template_string)
          return text unless template

          template.gsub("{prompt}", text)
        end

        # Build successful result
        def build_result(images:, started_at:, completed_at:)
          ImageGenerationResult.new(
            images: images,
            prompt: prompt,
            model_id: resolve_model,
            size: resolve_size,
            quality: resolve_quality,
            style: resolve_style,
            started_at: started_at,
            completed_at: completed_at,
            tenant_id: @tenant_id,
            generator_class: self.class.name
          )
        end

        # Build error result
        def build_error_result(error, started_at)
          ImageGenerationResult.new(
            images: [],
            prompt: prompt,
            model_id: resolve_model,
            size: resolve_size,
            quality: resolve_quality,
            style: resolve_style,
            started_at: started_at,
            completed_at: Time.current,
            tenant_id: @tenant_id,
            generator_class: self.class.name,
            error_class: error.class.name,
            error_message: error.message
          )
        end

        # Resolution methods (runtime options override class config)

        def resolve_model
          model = options[:model] || self.class.model
          # Handle aliases
          config.image_model_aliases&.dig(model.to_sym) || model
        end

        def resolve_size
          options[:size] || self.class.size
        end

        def resolve_quality
          options[:quality] || self.class.quality
        end

        def resolve_style
          options[:style] || self.class.style
        end

        def resolve_negative_prompt
          options[:negative_prompt] || self.class.negative_prompt
        end

        def resolve_seed
          options[:seed] || self.class.seed
        end

        def resolve_guidance_scale
          options[:guidance_scale] || self.class.guidance_scale
        end

        def resolve_steps
          options[:steps] || self.class.steps
        end

        def resolve_count
          options[:count] || 1
        end

        def single_image_request?
          resolve_count == 1
        end

        # Caching

        def cache_enabled?
          self.class.cache_enabled? && !options[:skip_cache]
        end

        def cache_key
          [
            "ruby_llm_agents",
            "image_generator",
            self.class.name,
            self.class.version,
            resolve_model,
            resolve_size,
            resolve_quality,
            resolve_style,
            Digest::SHA256.hexdigest(prompt)
          ].join(":")
        end

        def check_cache
          return nil unless defined?(Rails) && Rails.cache

          cached_data = Rails.cache.read(cache_key)
          return nil unless cached_data

          ImageGenerationResult.from_cache(cached_data)
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

          execution_data = {
            agent_type: self.class.name,
            tenant_id: @tenant_id,
            execution_type: "image_generation",
            model_id: result.model_id,
            status: "success",
            input_tokens: result.input_tokens,
            output_tokens: 0,
            total_cost: result.total_cost,
            duration_ms: result.duration_ms,
            started_at: result.started_at,
            completed_at: result.completed_at,
            metadata: {
              prompt_length: prompt.length,
              size: result.size,
              quality: result.quality,
              count: result.count
            }
          }

          if config.async_logging && defined?(ExecutionLoggerJob)
            ExecutionLoggerJob.perform_later(execution_data)
          else
            RubyLLM::Agents::Execution.create!(execution_data)
          end
        rescue StandardError => e
          Rails.logger.error("[RubyLLM::Agents] Failed to record image generation execution: #{e.message}") if defined?(Rails)
        end

        def record_failed_execution(error, started_at)
          return unless defined?(RubyLLM::Agents::Execution)

          execution_data = {
            agent_type: self.class.name,
            tenant_id: @tenant_id,
            execution_type: "image_generation",
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
            metadata: { prompt_length: prompt&.length }
          }

          if config.async_logging && defined?(ExecutionLoggerJob)
            ExecutionLoggerJob.perform_later(execution_data)
          else
            RubyLLM::Agents::Execution.create!(execution_data)
          end
        rescue StandardError => e
          Rails.logger.error("[RubyLLM::Agents] Failed to record failed image generation execution: #{e.message}") if defined?(Rails)
        end

        def budget_tracking_enabled?
          config.budgets_enabled? && defined?(BudgetTracker)
        end

        def config
          RubyLLM::Agents.configuration
        end
      end
    end
  end
end
