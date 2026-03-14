# frozen_string_literal: true

# CodingAgent - Demonstrates RubyLLM::Agents::Tool with context
#
# This agent showcases the new tool base class features:
# - Tools inherit from RubyLLM::Agents::Tool (instead of RubyLLM::Tool)
# - Tools access agent params via `context` (e.g., context.workspace_path)
# - Per-tool timeouts (FileReaderTool has timeout 10)
# - Automatic error handling in tools
#
# This agent can also be used as a sub-agent via the `agents` DSL.
# See OrchestratorAgent for an example of delegating to CodingAgent.
#
# @example Direct usage
#   CodingAgent.call(
#     query: "Read the Gemfile and tell me what dependencies we have",
#     workspace_path: "/path/to/project"
#   )
#
# @example As a sub-agent (workspace_path auto-forwarded)
#   class MyOrchestrator < ApplicationAgent
#     agents [CodingAgent], forward: [:workspace_path]
#   end
#
# @example Tool context flow
#   # 1. Agent is called with workspace_path: "/app"
#   # 2. LLM decides to use FileReaderTool
#   # 3. FileReaderTool reads context.workspace_path → "/app"
#   # 4. Tool reads file from /app/Gemfile
#   # 5. Result goes back to LLM
#
class CodingAgent < ApplicationAgent
  description "A coding assistant that can read files from a workspace"

  model "gpt-4o"
  temperature 0.0
  timeout 60

  tools [FileReaderTool, CalculatorTool]

  param :query, required: true
  param :workspace_path, default: "."

  def system_prompt
    <<~PROMPT
      You are a coding assistant. You have access to tools for reading files
      and performing calculations.

      When the user asks about code or files, use the file_reader tool to read them.
      When the user asks about math, use the calculator tool.

      Provide clear, concise answers based on the tool results.
    PROMPT
  end

  def user_prompt
    query
  end
end
