# frozen_string_literal: true

module RubyLLM
  module Agents
    module Pipeline
      # Carries request/response data through the middleware pipeline.
      #
      # All data flows explicitly through this object - no hidden
      # instance variables or implicit state. This makes the data flow
      # visible and testable.
      #
      # @example Creating a context
      #   context = Context.new(
      #     input: "Hello world",
      #     agent_class: MyEmbedder,
      #     model: "text-embedding-3-small"
      #   )
      #
      # @example Accessing data set by middleware
      #   context.tenant_id          # Set by Tenant middleware
      #   context.cached?            # Set by Cache middleware
      #   context.duration_ms        # Computed from timestamps
      #
      class Context
        # Request data
        attr_accessor :input, :model, :options

        # Tenant data (set by Tenant middleware)
        attr_accessor :tenant_id, :tenant_object, :tenant_config

        # Execution tracking (set by Instrumentation middleware)
        attr_accessor :started_at, :completed_at, :attempt, :attempts_made

        # Result data (set by core execute method)
        attr_accessor :output, :error, :cached

        # Cost tracking
        attr_accessor :input_tokens, :output_tokens, :total_cost

        # Agent metadata
        attr_reader :agent_class, :agent_type

        # Creates a new pipeline context
        #
        # @param input [Object] The input data for the agent
        # @param agent_class [Class] The agent class being executed
        # @param model [String, nil] Override model (defaults to agent_class.model)
        # @param options [Hash] Additional options passed to the agent
        def initialize(input:, agent_class:, model: nil, **options)
          @input = input
          @agent_class = agent_class
          @agent_type = extract_agent_type(agent_class)
          @model = model || extract_model(agent_class)
          @options = options

          # Initialize tracking fields
          @attempt = 0
          @attempts_made = 0
          @cached = false
          @metadata = {}

          # Initialize cost fields
          @input_tokens = 0
          @output_tokens = 0
          @total_cost = 0.0
        end

        # Duration in milliseconds
        #
        # @return [Integer, nil] Duration in ms, or nil if not yet completed
        def duration_ms
          return nil unless @started_at && @completed_at

          ((@completed_at - @started_at) * 1000).to_i
        end

        # Was the result served from cache?
        #
        # @return [Boolean]
        def cached?
          @cached == true
        end

        # Did execution succeed?
        #
        # @return [Boolean]
        def success?
          @error.nil? && !@output.nil?
        end

        # Did execution fail?
        #
        # @return [Boolean]
        def failed?
          !@error.nil?
        end

        # Total tokens used (input + output)
        #
        # @return [Integer]
        def total_tokens
          (@input_tokens || 0) + (@output_tokens || 0)
        end

        # Custom metadata storage - read
        #
        # @param key [Symbol, String] The metadata key
        # @return [Object] The stored value
        def [](key)
          @metadata[key]
        end

        # Custom metadata storage - write
        #
        # @param key [Symbol, String] The metadata key
        # @param value [Object] The value to store
        def []=(key, value)
          @metadata[key] = value
        end

        # Returns all custom metadata
        #
        # @return [Hash] The metadata hash
        def metadata
          @metadata.dup
        end

        # Convert to hash for logging/recording
        #
        # @return [Hash] Hash representation of the context
        def to_h
          {
            agent_class: @agent_class&.name,
            agent_type: @agent_type,
            model: @model,
            tenant_id: @tenant_id,
            duration_ms: duration_ms,
            cached: cached?,
            success: success?,
            input_tokens: @input_tokens,
            output_tokens: @output_tokens,
            total_tokens: total_tokens,
            total_cost: @total_cost,
            attempts_made: @attempts_made,
            error_class: @error&.class&.name,
            error_message: @error&.message
          }.compact
        end

        # Creates a duplicate context for retry attempts
        #
        # @return [Context] A new context with the same input but reset state
        def dup_for_retry
          new_ctx = self.class.new(
            input: @input,
            agent_class: @agent_class,
            model: @model,
            **@options
          )
          new_ctx.tenant_id = @tenant_id
          new_ctx.tenant_object = @tenant_object
          new_ctx.tenant_config = @tenant_config
          new_ctx.started_at = @started_at
          new_ctx.attempts_made = @attempts_made
          new_ctx
        end

        private

        # Extracts agent_type from the agent class
        #
        # @param agent_class [Class] The agent class
        # @return [Symbol, nil] The agent type
        def extract_agent_type(agent_class)
          return nil unless agent_class

          if agent_class.respond_to?(:agent_type)
            agent_class.agent_type
          else
            # Infer from class name as fallback
            infer_agent_type(agent_class)
          end
        end

        # Infers agent type from class name
        #
        # @param agent_class [Class] The agent class
        # @return [Symbol] The inferred agent type
        def infer_agent_type(agent_class)
          name = agent_class.name.to_s.split("::").last.to_s.downcase

          case name
          when /embed/ then :embedding
          when /image/, /generator/, /analyzer/, /editor/, /transform/, /upscale/, /variat/, /background/
            :image
          when /transcrib/, /speak/ then :audio
          when /moderat/ then :moderation
          else :conversation
          end
        end

        # Extracts model from agent class
        #
        # @param agent_class [Class] The agent class
        # @return [String, nil] The model identifier
        def extract_model(agent_class)
          return nil unless agent_class
          return agent_class.model if agent_class.respond_to?(:model)

          nil
        end
      end
    end
  end
end
