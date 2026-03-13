# frozen_string_literal: true

module RubyLLM
  module Agents
    # Read-only wrapper around Pipeline::Context for tool authors.
    #
    # Exposes agent params and execution metadata to tools without
    # leaking pipeline internals. Supports both method-style and
    # hash-style access to agent params.
    #
    # @example Method-style access
    #   context.container_id   # reads agent param
    #   context.tenant_id      # fixed attribute
    #
    # @example Hash-style access
    #   context[:container_id]
    #
    class ToolContext
      # Execution record ID — links tool calls to the agent execution
      #
      # @return [Integer, nil]
      def id
        @ctx.execution_id
      end

      # Tenant ID from the pipeline context
      #
      # @return [String, nil]
      def tenant_id
        @ctx.tenant_id
      end

      # Agent class name
      #
      # @return [String, nil]
      def agent_type
        @ctx.agent_class&.name
      end

      # Hash-style access to agent params
      #
      # @param key [Symbol, String] The param key
      # @return [Object, nil]
      def [](key)
        @agent_options[key.to_sym] || @agent_options[key.to_s]
      end

      def initialize(pipeline_context)
        @ctx = pipeline_context
        @agent_options = @ctx.agent_instance&.send(:options) || {}
      end

      private

      # Method-style access to agent params
      def method_missing(method_name, *args)
        key = method_name.to_sym
        if @agent_options.key?(key) || @agent_options.key?(key.to_s)
          self[key]
        else
          super
        end
      end

      def respond_to_missing?(method_name, include_private = false)
        key = method_name.to_sym
        @agent_options.key?(key) || @agent_options.key?(key.to_s) || super
      end
    end
  end
end
