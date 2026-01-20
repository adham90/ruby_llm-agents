# frozen_string_literal: true

module RubyLLM
  module Agents
    class Embedder
      # Execution logic for embedders
      #
      # Handles input normalization, batch processing, API calls,
      # execution tracking, and result building.
      module Execution
        # Executes the embedding operation
        #
        # @param text [String, nil] Single text to embed
        # @param texts [Array<String>, nil] Multiple texts to embed
        # @yield [batch_result, index] Called after each batch completes
        # @yieldparam batch_result [EmbeddingResult] Result for the batch
        # @yieldparam index [Integer] Batch index (0-based)
        # @return [EmbeddingResult] The combined embedding result
        def call(text: nil, texts: nil, &block)
          @execution_started_at = Time.current

          # Resolve tenant context
          resolve_tenant_context!

          # Check budget before execution
          check_budget! if track_embeddings?

          # Normalize and validate input
          input_texts = normalize_input(text, texts)
          validate_input!(input_texts)

          # Check cache for single texts
          if self.class.cache_enabled? && input_texts.size == 1
            cache_key = embedding_cache_key(input_texts.first)
            cached = cache_store.read(cache_key)
            return cached if cached
          end

          # Execute in batches
          all_vectors = []
          total_input_tokens = 0
          total_cost = 0.0
          batch_size = resolved_batch_size

          batches = input_texts.each_slice(batch_size).to_a

          batches.each_with_index do |batch, index|
            batch_result = execute_batch(batch)

            all_vectors.concat(batch_result[:vectors])
            total_input_tokens += batch_result[:input_tokens] || 0
            total_cost += batch_result[:cost] || 0.0

            # Yield batch result for progress tracking
            if block_given?
              batch_embedding_result = build_batch_result(batch_result, batch.size)
              yield(batch_embedding_result, index)
            end
          end

          @execution_completed_at = Time.current

          # Build final result
          result = build_result(
            vectors: all_vectors,
            input_tokens: total_input_tokens,
            total_cost: total_cost,
            count: input_texts.size
          )

          # Cache single text results
          if self.class.cache_enabled? && input_texts.size == 1
            cache_key = embedding_cache_key(input_texts.first)
            cache_store.write(cache_key, result, expires_in: self.class.cache_ttl)
          end

          # Record execution
          record_execution(result) if track_embeddings?

          result
        rescue StandardError => e
          @execution_completed_at = Time.current
          record_failed_execution(e) if track_embeddings?
          raise
        end

        # Preprocesses text before embedding
        #
        # Override this method in subclasses to apply custom preprocessing
        # like normalization, cleaning, or truncation.
        #
        # @param text [String] The text to preprocess
        # @return [String] The preprocessed text
        # @example Custom preprocessing
        #   def preprocess(text)
        #     text.strip.downcase.gsub(/\s+/, ' ').truncate(8000)
        #   end
        def preprocess(text)
          text
        end

        private

        # Normalizes input to an array of texts
        #
        # @param text [String, nil] Single text
        # @param texts [Array<String>, nil] Multiple texts
        # @return [Array<String>] Array of texts
        # @raise [ArgumentError] If both or neither are provided
        def normalize_input(text, texts)
          if text && texts
            raise ArgumentError, "Provide either text: or texts:, not both"
          end

          if text.nil? && texts.nil?
            raise ArgumentError, "Provide either text: or texts:"
          end

          texts || [text]
        end

        # Validates the input texts
        #
        # @param texts [Array<String>] Texts to validate
        # @raise [ArgumentError] If validation fails
        def validate_input!(texts)
          if texts.empty?
            raise ArgumentError, "texts cannot be empty"
          end

          texts.each_with_index do |text, idx|
            unless text.is_a?(String)
              raise ArgumentError, "texts[#{idx}] must be a String, got #{text.class}"
            end

            if text.empty?
              raise ArgumentError, "texts[#{idx}] cannot be empty"
            end
          end
        end

        # Executes a single batch of texts
        #
        # @param texts [Array<String>] Texts to embed
        # @return [Hash] Batch result with vectors, tokens, cost
        def execute_batch(texts)
          preprocessed = texts.map { |t| preprocess(t) }

          embed_options = { model: resolved_model }
          embed_options[:dimensions] = resolved_dimensions if resolved_dimensions

          response = RubyLLM.embed(preprocessed, **embed_options)

          # ruby_llm returns vectors as an array (even for single text)
          vectors = response.vectors
          vectors = [vectors] unless vectors.first.is_a?(Array)

          {
            vectors: vectors,
            input_tokens: response.input_tokens,
            model: response.model,
            cost: calculate_cost(response)
          }
        end

        # Builds a batch result for progress callback
        #
        # @param batch_data [Hash] Raw batch data
        # @param count [Integer] Number of texts in batch
        # @return [EmbeddingResult] Result for the batch
        def build_batch_result(batch_data, count)
          EmbeddingResult.new(
            vectors: batch_data[:vectors],
            model_id: batch_data[:model],
            dimensions: batch_data[:vectors].first&.size,
            input_tokens: batch_data[:input_tokens],
            total_cost: batch_data[:cost],
            count: count
          )
        end

        # Builds the final result object
        #
        # @param vectors [Array<Array<Float>>] All vectors
        # @param input_tokens [Integer] Total tokens
        # @param total_cost [Float] Total cost
        # @param count [Integer] Total texts
        # @return [EmbeddingResult] The final result
        def build_result(vectors:, input_tokens:, total_cost:, count:)
          EmbeddingResult.new(
            vectors: vectors,
            model_id: resolved_model,
            dimensions: vectors.first&.size,
            input_tokens: input_tokens,
            total_cost: total_cost,
            duration_ms: duration_ms,
            count: count,
            started_at: @execution_started_at,
            completed_at: @execution_completed_at,
            tenant_id: @tenant_id
          )
        end

        # Calculates cost for an embedding response
        #
        # @param response [Object] The ruby_llm embedding response
        # @return [Float] Cost in USD
        def calculate_cost(response)
          # ruby_llm may provide cost directly, otherwise estimate
          return response.input_cost if response.respond_to?(:input_cost) && response.input_cost

          # Fallback: estimate based on tokens and model
          # These are approximate OpenAI prices
          tokens = response.input_tokens || 0
          model = response.model.to_s

          price_per_million = case model
                              when /text-embedding-3-small/
                                0.02
                              when /text-embedding-3-large/
                                0.13
                              when /text-embedding-ada/
                                0.10
                              else
                                0.02 # Default to small pricing
                              end

          (tokens / 1_000_000.0) * price_per_million
        end

        # Returns the execution duration in milliseconds
        #
        # @return [Integer, nil] Duration in ms
        def duration_ms
          return nil unless @execution_started_at && @execution_completed_at

          ((@execution_completed_at - @execution_started_at) * 1000).to_i
        end

        # Resolves the model to use
        #
        # @return [String] The model identifier
        def resolved_model
          @options[:model] || self.class.model
        end

        # Resolves the dimensions to use
        #
        # @return [Integer, nil] The dimensions or nil for model default
        def resolved_dimensions
          @options[:dimensions] || self.class.dimensions
        end

        # Resolves the batch size to use
        #
        # @return [Integer] The batch size
        def resolved_batch_size
          @options[:batch_size] || self.class.batch_size
        end

        # Resolves tenant context from options
        #
        # @return [void]
        def resolve_tenant_context!
          return if defined?(@tenant_context_resolved) && @tenant_context_resolved

          tenant_value = @options[:tenant]

          if tenant_value.nil?
            @tenant_id = nil
            @tenant_object = nil
            @tenant_config = nil
            @tenant_context_resolved = true
            return
          end

          if tenant_value.is_a?(Hash)
            @tenant_id = tenant_value[:id]&.to_s
            @tenant_object = nil
            @tenant_config = tenant_value.except(:id)
          elsif tenant_value.respond_to?(:llm_tenant_id)
            @tenant_id = tenant_value.llm_tenant_id
            @tenant_object = tenant_value
            @tenant_config = nil
          else
            raise ArgumentError,
                  "tenant must respond to :llm_tenant_id (use llm_tenant DSL), got #{tenant_value.class}"
          end

          @tenant_context_resolved = true
        end

        # Returns the cache store
        #
        # @return [ActiveSupport::Cache::Store] The cache store
        def cache_store
          RubyLLM::Agents.configuration.cache_store
        end

        # Generates a cache key for embedding
        #
        # @param text [String] The text to cache
        # @return [String] The cache key
        def embedding_cache_key(text)
          components = [
            "ruby_llm_agents",
            "embedding",
            self.class.name,
            self.class.version,
            resolved_model,
            resolved_dimensions,
            Digest::SHA256.hexdigest(preprocess(text))
          ].compact

          components.join("/")
        end

        # Returns whether to track embeddings
        #
        # @return [Boolean] true if tracking is enabled
        def track_embeddings?
          RubyLLM::Agents.configuration.track_embeddings
        end

        # Checks budget before execution
        #
        # @raise [BudgetExceededError] If budget exceeded with hard enforcement
        def check_budget!
          return unless RubyLLM::Agents.configuration.budgets_enabled?

          BudgetTracker.check!(
            agent_type: self.class.name,
            tenant_id: @tenant_id,
            execution_type: "embedding"
          )
        end

        # Records a successful execution
        #
        # @param result [EmbeddingResult] The result to record
        def record_execution(result)
          return unless defined?(RubyLLM::Agents::Execution)

          execution_data = {
            agent_type: self.class.name,
            execution_type: "embedding",
            model_id: result.model_id,
            status: "success",
            input_tokens: result.input_tokens,
            output_tokens: 0,
            total_cost: result.total_cost,
            duration_ms: result.duration_ms,
            started_at: result.started_at,
            completed_at: result.completed_at,
            tenant_id: result.tenant_id,
            metadata: {
              text_count: result.count,
              dimensions: result.dimensions,
              batch_size: resolved_batch_size
            }
          }

          if RubyLLM::Agents.configuration.async_logging
            RubyLLM::Agents::ExecutionLoggerJob.perform_later(execution_data)
          else
            RubyLLM::Agents::Execution.create!(execution_data)
          end
        rescue StandardError => e
          Rails.logger.error("[RubyLLM::Agents] Failed to record embedding execution: #{e.message}") if defined?(Rails)
        end

        # Records a failed execution
        #
        # @param error [StandardError] The error that occurred
        def record_failed_execution(error)
          return unless defined?(RubyLLM::Agents::Execution)

          execution_data = {
            agent_type: self.class.name,
            execution_type: "embedding",
            model_id: resolved_model,
            status: "error",
            input_tokens: 0,
            output_tokens: 0,
            total_cost: 0,
            duration_ms: duration_ms,
            started_at: @execution_started_at,
            completed_at: @execution_completed_at,
            tenant_id: @tenant_id,
            error_class: error.class.name,
            error_message: error.message.truncate(1000),
            metadata: {
              batch_size: resolved_batch_size
            }
          }

          if RubyLLM::Agents.configuration.async_logging
            RubyLLM::Agents::ExecutionLoggerJob.perform_later(execution_data)
          else
            RubyLLM::Agents::Execution.create!(execution_data)
          end
        rescue StandardError => e
          Rails.logger.error("[RubyLLM::Agents] Failed to record failed embedding execution: #{e.message}") if defined?(Rails)
        end
      end
    end
  end
end
