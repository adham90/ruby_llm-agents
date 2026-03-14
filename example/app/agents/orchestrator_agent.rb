# frozen_string_literal: true

# OrchestratorAgent - Demonstrates the agents DSL
#
# This agent showcases the `agents` DSL for delegating substantial tasks
# to specialized sub-agents. The LLM decides which agents to invoke based
# on the user's request.
#
# Key concepts:
# - `agents` DSL separates agent delegates from regular `tools`
# - `forward` auto-injects parent params into sub-agent calls
# - System prompt auto-generates "Direct Tools" and "Agents" sections
# - Stream events distinguish :agent_start/:agent_end from :tool_start/:tool_end
# - Sub-agents run through their own full pipeline (middleware, tracking, etc.)
#
# @example Basic usage
#   OrchestratorAgent.call(
#     query: "Read the Gemfile and generate tests for the User model",
#     workspace_path: "/path/to/project"
#   )
#
# @example With stream events (see agent lifecycle)
#   OrchestratorAgent.call(
#     query: "Review the code and fix any issues",
#     workspace_path: "/path/to/project",
#     stream_events: true
#   ) do |event|
#     case event.type
#     when :chunk       then print event.data[:content]
#     when :tool_start  then puts "Tool: #{event.data[:tool_name]}..."
#     when :tool_end    then puts "Done (#{event.data[:duration_ms]}ms)"
#     when :agent_start then puts "Delegating to #{event.data[:agent_name]}..."
#     when :agent_end   then puts "Agent done (#{event.data[:duration_ms]}ms)"
#     end
#   end
#
# @example Simple form (list + options)
#   # agents [CodingAgent, SchemaAgent], forward: [:workspace_path]
#
# @example Block form (per-agent configuration)
#   # agents do
#   #   use CodingAgent, timeout: 120, description: "Read and write code"
#   #   use SchemaAgent, description: "Analyze data structures"
#   #   forward :workspace_path
#   #   instructions "Use agents for complex, multi-file tasks."
#   # end
#
class OrchestratorAgent < ApplicationAgent
  description "Orchestrates specialized agents for complex development tasks"

  model "gpt-4o"
  temperature 0.3
  timeout 120
  streaming true

  # Direct tools — fast, local operations
  tools [CalculatorTool]

  # Agents — specialized AI agents the LLM can delegate to.
  # Each agent is autonomous with its own tools, context, and pipeline.
  # The `forward` option auto-injects workspace_path into every agent call
  # without the LLM needing to pass it explicitly.
  agents do
    use CodingAgent, description: "Read files, analyze code, and perform calculations"

    forward :workspace_path
    instructions <<~TEXT
      Use agents for substantial tasks that require reading multiple files
      or performing complex analysis. For simple calculations or quick
      questions, use your direct tools instead.
    TEXT
  end

  param :query, required: true
  param :workspace_path, default: "."

  def system_prompt
    <<~PROMPT
      You are a senior developer orchestrating a team of specialized agents.
      Analyze the user's request and decide whether to handle it directly
      or delegate to one of your available agents.
    PROMPT
  end

  def user_prompt
    query
  end
end
