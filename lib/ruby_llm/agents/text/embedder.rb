# frozen_string_literal: true

require_relative "../results/embedding_result"

module RubyLLM
  module Agents
    # Base class for creating embedding generators
    #
    # Embedder inherits from BaseAgent and uses the middleware pipeline
    # for caching, reliability, instrumentation, and budget controls.
    # Only the core embedding logic is implemented here.
    #
    # @example Basic usage
    #   class DocumentEmbedder < RubyLLM::Agents::Embedder
    #     model 'text-embedding-3-small'
    #     dimensions 512
    #   end
    #
    #   result = DocumentEmbedder.call(text: "Hello world")
    #   result.vector  # => [0.123, -0.456, ...]
    #
    # @example Batch processing
    #   result = DocumentEmbedder.call(texts: ["Hello", "World"])
    #   result.vectors  # => [[...], [...]]
    #
    # @example With preprocessing
    #   class CleanEmbedder < RubyLLM::Agents::Embedder
    #     model 'text-embedding-3-small'
    #
    #     def preprocess(text)
    #       text.strip.downcase.gsub(/\s+/, ' ')
    #     end
    #   end
    #
    # @api public
    class Embedder < BaseAgent
      class << self
        # Returns the agent type for embedders
        #
        # @return [Symbol] :embedding
        def agent_type
          :embedding
        end

        # @!group Embedding-specific DSL

        # Sets or returns the embedding model
        #
        # Defaults to the embedding model from configuration, not the
        # conversation model that BaseAgent uses.
        #
        # @param value [String, nil] The model identifier to set
        # @return [String] The current model setting
        # @example
        #   model "text-embedding-3-large"
        def model(value = nil)
          @model = value if value
          return @model if defined?(@model) && @model

          # For inheritance: check if parent is also an Embedder
          if superclass.respond_to?(:agent_type) && superclass.agent_type == :embedding
            superclass.model
          else
            default_embedding_model
          end
        end

        # Sets or returns the vector dimensions
        #
        # Some models (like OpenAI text-embedding-3) support reducing
        # dimensions for more efficient storage.
        #
        # @param value [Integer, nil] The dimensions to set
        # @return [Integer, nil] The current dimensions setting
        # @example
        #   dimensions 512
        def dimensions(value = nil)
          @dimensions = value if value
          @dimensions || inherited_or_default(:dimensions, default_embedding_dimensions)
        end

        # Sets or returns the batch size
        #
        # When embedding multiple texts, they are split into batches
        # of this size for API calls.
        #
        # @param value [Integer, nil] Maximum texts per API call
        # @return [Integer] The current batch size
        # @example
        #   batch_size 50
        def batch_size(value = nil)
          @batch_size = value if value
          @batch_size || inherited_or_default(:batch_size, default_embedding_batch_size)
        end

        # @!endgroup

        # Executes the embedder with the given parameters
        #
        # @param text [String, nil] Single text to embed
        # @param texts [Array<String>, nil] Multiple texts to embed
        # @param options [Hash] Additional options
        # @yield [batch_result, index] Called after each batch completes
        # @yieldparam batch_result [EmbeddingResult] Result for the batch
        # @yieldparam index [Integer] Batch index (0-based)
        # @return [EmbeddingResult] The embedding result
        # @raise [ArgumentError] If both text: and texts: are provided
        def call(text: nil, texts: nil, **options, &block)
          new(text: text, texts: texts, **options).call(&block)
        end

        private

        def inherited_or_default(method, default)
          superclass.respond_to?(method) ? superclass.send(method) : default
        end

        def default_embedding_model
          RubyLLM::Agents.configuration.default_embedding_model
        rescue StandardError
          "text-embedding-3-small"
        end

        def default_embedding_dimensions
          RubyLLM::Agents.configuration.default_embedding_dimensions
        rescue StandardError
          nil
        end

        def default_embedding_batch_size
          RubyLLM::Agents.configuration.default_embedding_batch_size
        rescue StandardError
          100
        end
      end

      # @!attribute [r] text
      #   @return [String, nil] Single text to embed
      # @!attribute [r] texts
      #   @return [Array<String>, nil] Multiple texts to embed
      attr_reader :text, :texts

      # Creates a new Embedder instance
      #
      # @param text [String, nil] Single text to embed
      # @param texts [Array<String>, nil] Multiple texts to embed
      # @param options [Hash] Additional options
      def initialize(text: nil, texts: nil, **options)
        @text = text
        @texts = texts
        @batch_block = nil

        # Set model to embedding model if not specified
        options[:model] ||= self.class.model || self.class.class_eval { default_embedding_model }

        super(**options)
      end

      # Executes the embedding through the middleware pipeline
      #
      # @yield [batch_result, index] Called after each batch completes
      # @return [EmbeddingResult] The embedding result
      def call(&block)
        @batch_block = block
        context = build_context
        result_context = Pipeline::Executor.execute(context)
        result_context.output
      end

      # The input for this embedding operation
      #
      # Used by the pipeline to generate cache keys and for instrumentation.
      #
      # @return [String, Array<String>] The input text(s)
      def user_prompt
        input_texts.join("\n---\n")
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

      # Core embedding execution
      #
      # This is called by the Pipeline::Executor after middleware
      # has been applied. Only contains the embedding API logic.
      #
      # @param context [Pipeline::Context] The execution context
      # @return [void] Sets context.output with the EmbeddingResult
      def execute(context)
        # Track timing internally since middleware sets completed_at after execute returns
        execution_started_at = Time.current

        input_list = input_texts
        validate_input!(input_list)

        all_vectors = []
        total_input_tokens = 0
        total_cost = 0.0
        batch_count = resolved_batch_size

        batches = input_list.each_slice(batch_count).to_a

        batches.each_with_index do |batch, index|
          batch_result = execute_batch(batch, context)

          all_vectors.concat(batch_result[:vectors])
          total_input_tokens += batch_result[:input_tokens] || 0
          total_cost += batch_result[:cost] || 0.0

          # Yield batch result for progress tracking
          if @batch_block
            batch_embedding_result = build_batch_result(batch_result, batch.size)
            @batch_block.call(batch_embedding_result, index)
          end
        end

        execution_completed_at = Time.current
        duration_ms = ((execution_completed_at - execution_started_at) * 1000).to_i

        # Update context with token/cost info
        context.input_tokens = total_input_tokens
        context.output_tokens = 0
        context.input_cost = total_cost
        context.output_cost = 0.0
        context.total_cost = total_cost.round(6)

        # Build final result
        context.output = build_result(
          vectors: all_vectors,
          input_tokens: total_input_tokens,
          total_cost: total_cost,
          count: input_list.size,
          started_at: context.started_at || execution_started_at,
          completed_at: execution_completed_at,
          duration_ms: duration_ms,
          tenant_id: context.tenant_id
        )
      end

      # Generates the cache key for this embedding
      #
      # @return [String] Cache key in format "ruby_llm_agents/embedding/..."
      def agent_cache_key
        components = [
          "ruby_llm_agents",
          "embedding",
          self.class.name,
          resolved_model,
          resolved_dimensions,
          Digest::SHA256.hexdigest(input_texts.map { |t| preprocess(t) }.join("\n"))
        ].compact

        components.join("/")
      end

      protected

      # Returns the normalized input texts
      #
      # @return [Array<String>] Array of texts to embed
      def input_texts
        @input_texts ||= normalize_input
      end

      private

      # Builds context for pipeline execution
      #
      # @return [Pipeline::Context] The context object
      def build_context
        Pipeline::Context.new(
          input: user_prompt,
          agent_class: self.class,
          agent_instance: self,
          model: resolved_model,
          tenant: @options[:tenant],
          skip_cache: @options[:skip_cache]
        )
      end

      # Normalizes input to an array of texts
      #
      # @return [Array<String>] Array of texts
      # @raise [ArgumentError] If both or neither text/texts provided
      def normalize_input
        if @text && @texts
          raise ArgumentError, "Provide either text: or texts:, not both"
        end

        if @text.nil? && @texts.nil?
          raise ArgumentError, "Provide either text: or texts:"
        end

        @texts || [@text]
      end

      # Validates the input texts
      #
      # @param texts [Array<String>] Texts to validate
      # @raise [ArgumentError] If validation fails
      def validate_input!(texts)
        if texts.empty?
          raise ArgumentError, "texts cannot be empty"
        end

        texts.each_with_index do |txt, idx|
          unless txt.is_a?(String)
            raise ArgumentError, "texts[#{idx}] must be a String, got #{txt.class}"
          end

          if txt.empty?
            raise ArgumentError, "texts[#{idx}] cannot be empty"
          end
        end
      end

      # Executes a single batch of texts
      #
      # @param texts [Array<String>] Texts to embed
      # @return [Hash] Batch result with vectors, tokens, cost
      def execute_batch(texts, context = nil)
        preprocessed = texts.map { |t| preprocess(t) }

        embed_options = { model: context&.model || resolved_model }
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
      # @param started_at [Time] When execution started
      # @param completed_at [Time] When execution completed
      # @param duration_ms [Integer] Execution duration in ms
      # @param tenant_id [String, nil] Tenant identifier
      # @return [EmbeddingResult] The final result
      def build_result(vectors:, input_tokens:, total_cost:, count:, started_at:, completed_at:, duration_ms:, tenant_id:)
        EmbeddingResult.new(
          vectors: vectors,
          model_id: resolved_model,
          dimensions: vectors.first&.size,
          input_tokens: input_tokens,
          total_cost: total_cost,
          duration_ms: duration_ms,
          count: count,
          started_at: started_at,
          completed_at: completed_at,
          tenant_id: tenant_id
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
        tokens = response.input_tokens || 0
        model_name = response.model.to_s

        price_per_million = case model_name
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

      # Resolves the model to use
      #
      # @return [String] The model identifier
      def resolved_model
        @model || self.class.model
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
    end
  end
end
