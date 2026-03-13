# frozen_string_literal: true

require "timeout"

module RubyLLM
  module Agents
    # Base class for tools that need access to the agent's execution context.
    #
    # Inherits from RubyLLM::Tool and adds:
    # - `context` accessor: read agent params, tenant, execution ID
    # - `timeout` DSL: per-tool timeout in seconds
    # - Error handling: exceptions become error strings for the LLM
    #
    # Users implement `execute()` — the standard RubyLLM convention.
    # This class overrides `call()` to wrap execution with its features.
    #
    # @example Defining a tool
    #   class BashTool < RubyLLM::Agents::Tool
    #     description "Run a shell command"
    #     timeout 30
    #
    #     param :command, desc: "The command to run", required: true
    #
    #     def execute(command:)
    #       context.container_id  # reads agent param
    #       # ... run command ...
    #     end
    #   end
    #
    # @example Using with an agent
    #   class CodingAgent < ApplicationAgent
    #     param :container_id, required: true
    #     tools [BashTool]
    #   end
    #
    #   CodingAgent.call(query: "list files", container_id: "abc123")
    #
    class Tool < RubyLLM::Tool
      # The execution context, set before each call.
      # Provides access to agent params, tenant, execution ID.
      #
      # @return [ToolContext, nil]
      attr_reader :context

      class << self
        # Sets or gets the per-tool timeout in seconds.
        #
        # @param value [Integer, nil] Timeout in seconds (setter)
        # @return [Integer, nil] The configured timeout (getter)
        def timeout(value = nil)
          if value
            @timeout = value
          else
            @timeout
          end
        end
      end

      # Wraps RubyLLM's call() with context, timeout, and error handling.
      #
      # RubyLLM's Chat calls tool.call(args) during the tool loop.
      # We set up context, apply timeout, then delegate to super
      # (which validates args and calls execute).
      #
      # @param args [Hash] Tool arguments from the LLM
      # @return [String, Tool::Halt] The tool result or a Halt signal
      def call(args)
        pipeline_context = Thread.current[:ruby_llm_agents_caller_context]
        @context = pipeline_context ? ToolContext.new(pipeline_context) : nil

        timeout_seconds = self.class.timeout
        timeout_seconds ||= RubyLLM::Agents.configuration.default_tool_timeout

        if timeout_seconds
          Timeout.timeout(timeout_seconds) { super }
        else
          super
        end
      rescue Timeout::Error
        "TIMEOUT: Tool did not complete within #{timeout_seconds}s."
      rescue RubyLLM::Agents::CancelledError
        raise # Let cancellation propagate to BaseAgent
      rescue => e
        "ERROR (#{e.class}): #{e.message}"
      end
    end
  end
end
