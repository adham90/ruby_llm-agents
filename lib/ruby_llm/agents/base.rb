# frozen_string_literal: true

require_relative "base/dsl"
require_relative "base/caching"
require_relative "base/cost_calculation"
require_relative "base/tool_tracking"
require_relative "base/response_building"
require_relative "base/execution"
require_relative "base/reliability_execution"

module RubyLLM
  module Agents
    # Base class for LLM-powered agents
    #
    # Provides a DSL for configuring and executing agents that interact with
    # large language models. Includes built-in support for caching, timeouts,
    # structured output, and execution tracking.
    #
    # @example Creating an agent
    #   class SearchAgent < ApplicationAgent
    #     model "gpt-4o"
    #     temperature 0.0
    #     version "1.0"
    #     timeout 30
    #     cache 1.hour
    #
    #     param :query, required: true
    #     param :limit, default: 10
    #
    #     def system_prompt
    #       "You are a search assistant..."
    #     end
    #
    #     def user_prompt
    #       "Search for: #{query}"
    #     end
    #   end
    #
    # @example Calling an agent
    #   SearchAgent.call(query: "red dress")
    #   SearchAgent.call(query: "red dress", dry_run: true)    # Debug mode
    #   SearchAgent.call(query: "red dress", skip_cache: true) # Bypass cache
    #
    # @see RubyLLM::Agents::Instrumentation
    # @api public
    class Base
      include Instrumentation
      include Caching
      include CostCalculation
      include ToolTracking
      include ResponseBuilding
      include Execution
      include ReliabilityExecution

      extend DSL

      class << self
        # Factory method to instantiate and execute an agent
        #
        # @param args [Array] Positional arguments (reserved for future use)
        # @param kwargs [Hash] Named parameters for the agent
        # @option kwargs [Boolean] :dry_run Return prompt info without API call
        # @option kwargs [Boolean] :skip_cache Bypass caching even if enabled
        # @option kwargs [String, Array<String>] :with Attachments (files, URLs) to send with the prompt
        # @yield [chunk] Yields chunks when streaming is enabled
        # @yieldparam chunk [RubyLLM::Chunk] A streaming chunk with content
        # @return [Object] The processed response from the agent
        #
        # @example Basic usage
        #   SearchAgent.call(query: "red dress")
        #
        # @example Debug mode
        #   SearchAgent.call(query: "red dress", dry_run: true)
        #
        # @example Streaming mode
        #   ChatAgent.call(message: "Hello") do |chunk|
        #     print chunk.content
        #   end
        #
        # @example With attachments
        #   VisionAgent.call(query: "Describe this image", with: "photo.jpg")
        #   VisionAgent.call(query: "Compare these", with: ["a.png", "b.png"])
        def call(*args, **kwargs, &block)
          new(*args, **kwargs).call(&block)
        end
      end

      # @!attribute [r] model
      #   @return [String] The LLM model being used
      # @!attribute [r] temperature
      #   @return [Float] The temperature setting
      # @!attribute [r] client
      #   @return [RubyLLM::Chat] The configured RubyLLM client
      # @!attribute [r] time_to_first_token_ms
      #   @return [Integer, nil] Time to first token in milliseconds (streaming only)
      # @!attribute [r] accumulated_tool_calls
      #   @return [Array<Hash>] Tool calls accumulated during execution
      attr_reader :model, :temperature, :client, :time_to_first_token_ms, :accumulated_tool_calls

      # Creates a new agent instance
      #
      # @param model [String] Override the class-level model setting
      # @param temperature [Float] Override the class-level temperature
      # @param options [Hash] Agent parameters defined via the param DSL
      # @raise [ArgumentError] If required parameters are missing
      def initialize(model: self.class.model, temperature: self.class.temperature, **options)
        @model = model
        @temperature = temperature
        @options = options
        @accumulated_tool_calls = []
        validate_required_params!
        @client = build_client
      end

      # @!group Template Methods (override in subclasses)

      # User prompt to send to the LLM
      #
      # @abstract Subclasses must implement this method
      # @return [String] The user prompt
      # @raise [NotImplementedError] If not overridden in subclass
      def user_prompt
        raise NotImplementedError, "#{self.class} must implement #user_prompt"
      end

      # System prompt for LLM instructions
      #
      # @return [String, nil] System instructions, or nil for none
      def system_prompt
        nil
      end

      # Response schema for structured output
      #
      # @return [RubyLLM::Schema, nil] Schema definition, or nil for free-form
      def schema
        nil
      end

      # Conversation history for multi-turn conversations
      #
      # Override in subclass to provide conversation history.
      # Messages will be added to the chat before the user_prompt.
      #
      # @return [Array<Hash>] Array of messages with :role and :content keys
      # @example
      #   def messages
      #     [{ role: :user, content: "Hello" }, { role: :assistant, content: "Hi!" }]
      #   end
      def messages
        []
      end

      # Post-processes the LLM response
      #
      # Override to transform the response before returning to the caller.
      # Default implementation symbolizes hash keys.
      #
      # @param response [RubyLLM::Message] The raw response from the LLM
      # @return [Object] The processed result
      def process_response(response)
        content = response.content
        return content unless content.is_a?(Hash)
        content.transform_keys(&:to_sym)
      end

      # @!endgroup

      # Sets conversation history and rebuilds the client
      #
      # @param msgs [Array<Hash>] Messages with :role and :content keys
      # @return [self] Returns self for chaining
      # @example
      #   agent.with_messages([{ role: :user, content: "Hi" }]).call
      def with_messages(msgs)
        @override_messages = msgs
        @client = build_client
        self
      end
    end
  end
end
