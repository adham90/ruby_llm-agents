# frozen_string_literal: true

module RubyLLM
  module Agents
    # Wrapper for agent execution results with full metadata
    #
    # Provides access to the response content along with execution details
    # like token usage, cost, timing, and model information.
    #
    # @example Basic usage
    #   result = MyAgent.call(query: "test")
    #   result.content        # => processed response
    #   result.input_tokens   # => 150
    #   result.total_cost     # => 0.00025
    #
    # @example Backward compatible hash access
    #   result[:key]          # delegates to result.content[:key]
    #   result.dig(:nested, :key)
    #
    # @api public
    class Result
      extend ActiveSupport::Delegation

      # @!attribute [r] content
      #   @return [Hash, String] The processed response content
      attr_reader :content

      # @!group Token Usage
      # @!attribute [r] input_tokens
      #   @return [Integer, nil] Number of input tokens consumed
      # @!attribute [r] output_tokens
      #   @return [Integer, nil] Number of output tokens generated
      # @!attribute [r] cached_tokens
      #   @return [Integer] Number of tokens served from cache
      # @!attribute [r] cache_creation_tokens
      #   @return [Integer] Number of tokens used to create cache
      attr_reader :input_tokens, :output_tokens, :cached_tokens, :cache_creation_tokens

      # @!group Cost
      # @!attribute [r] input_cost
      #   @return [Float, nil] Cost of input tokens in USD
      # @!attribute [r] output_cost
      #   @return [Float, nil] Cost of output tokens in USD
      # @!attribute [r] total_cost
      #   @return [Float, nil] Total cost in USD
      attr_reader :input_cost, :output_cost, :total_cost

      # @!group Model Info
      # @!attribute [r] model_id
      #   @return [String, nil] The model that was requested
      # @!attribute [r] chosen_model_id
      #   @return [String, nil] The model that actually responded (may differ if fallback used)
      # @!attribute [r] temperature
      #   @return [Float, nil] Temperature setting used
      attr_reader :model_id, :chosen_model_id, :temperature

      # @!group Timing
      # @!attribute [r] started_at
      #   @return [Time, nil] When execution started
      # @!attribute [r] completed_at
      #   @return [Time, nil] When execution completed
      # @!attribute [r] duration_ms
      #   @return [Integer, nil] Execution duration in milliseconds
      # @!attribute [r] time_to_first_token_ms
      #   @return [Integer, nil] Time to first token (streaming only)
      attr_reader :started_at, :completed_at, :duration_ms, :time_to_first_token_ms

      # @!group Status
      # @!attribute [r] finish_reason
      #   @return [String, nil] Why generation stopped (stop, length, tool_calls, etc.)
      # @!attribute [r] streaming
      #   @return [Boolean] Whether streaming was enabled
      attr_reader :finish_reason, :streaming

      # @!group Error Info
      # @!attribute [r] error_class
      #   @return [String, nil] Exception class name if failed
      # @!attribute [r] error_message
      #   @return [String, nil] Exception message if failed
      attr_reader :error_class, :error_message

      # @!group Reliability
      # @!attribute [r] attempts
      #   @return [Array<Hash>] Details of each attempt (for retries/fallbacks)
      # @!attribute [r] attempts_count
      #   @return [Integer] Number of attempts made
      attr_reader :attempts, :attempts_count

      # Creates a new Result instance
      #
      # @param content [Hash, String] The processed response content
      # @param options [Hash] Execution metadata
      def initialize(content:, **options)
        @content = content

        # Token usage
        @input_tokens = options[:input_tokens]
        @output_tokens = options[:output_tokens]
        @cached_tokens = options[:cached_tokens] || 0
        @cache_creation_tokens = options[:cache_creation_tokens] || 0

        # Cost
        @input_cost = options[:input_cost]
        @output_cost = options[:output_cost]
        @total_cost = options[:total_cost]

        # Model info
        @model_id = options[:model_id]
        @chosen_model_id = options[:chosen_model_id] || options[:model_id]
        @temperature = options[:temperature]

        # Timing
        @started_at = options[:started_at]
        @completed_at = options[:completed_at]
        @duration_ms = options[:duration_ms]
        @time_to_first_token_ms = options[:time_to_first_token_ms]

        # Status
        @finish_reason = options[:finish_reason]
        @streaming = options[:streaming] || false

        # Error
        @error_class = options[:error_class]
        @error_message = options[:error_message]

        # Reliability
        @attempts = options[:attempts] || []
        @attempts_count = options[:attempts_count] || 1
      end

      # Returns total tokens (input + output)
      #
      # @return [Integer] Total token count
      def total_tokens
        (input_tokens || 0) + (output_tokens || 0)
      end

      # Returns whether streaming was enabled
      #
      # @return [Boolean] true if streaming was used
      def streaming?
        streaming == true
      end

      # Returns whether the execution succeeded
      #
      # @return [Boolean] true if no error occurred
      def success?
        error_class.nil?
      end

      # Returns whether the execution failed
      #
      # @return [Boolean] true if an error occurred
      def error?
        !success?
      end

      # Returns whether a fallback model was used
      #
      # @return [Boolean] true if chosen_model_id differs from model_id
      def used_fallback?
        chosen_model_id.present? && chosen_model_id != model_id
      end

      # Returns whether the response was truncated due to max tokens
      #
      # @return [Boolean] true if finish_reason is "length"
      def truncated?
        finish_reason == "length"
      end

      # Converts the result to a hash
      #
      # @return [Hash] All result data as a hash
      def to_h
        {
          content: content,
          input_tokens: input_tokens,
          output_tokens: output_tokens,
          total_tokens: total_tokens,
          cached_tokens: cached_tokens,
          cache_creation_tokens: cache_creation_tokens,
          input_cost: input_cost,
          output_cost: output_cost,
          total_cost: total_cost,
          model_id: model_id,
          chosen_model_id: chosen_model_id,
          temperature: temperature,
          started_at: started_at,
          completed_at: completed_at,
          duration_ms: duration_ms,
          time_to_first_token_ms: time_to_first_token_ms,
          finish_reason: finish_reason,
          streaming: streaming,
          error_class: error_class,
          error_message: error_message,
          attempts_count: attempts_count,
          attempts: attempts
        }
      end

      # Delegate hash methods to content for backward compatibility
      delegate :[], :dig, :keys, :values, :each, :map, to: :content, allow_nil: true

      # Custom to_json that returns content as JSON for backward compatibility
      #
      # @param args [Array] Arguments passed to to_json
      # @return [String] JSON representation
      def to_json(*args)
        content.to_json(*args)
      end
    end
  end
end
