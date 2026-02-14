# frozen_string_literal: true

# ToolsAgent - Demonstrates the tools DSL
#
# This agent showcases tool integration:
# - Multiple tools can be registered
# - LLM decides when to call tools
# - Tool results are sent back to LLM
# - Loop continues until final answer
#
# Available tools:
# - CalculatorTool: Math operations
# - WeatherTool: Weather lookups
#
# @example Math question
#   ToolsAgent.call(query: "What is 25 multiplied by 4?")
#   # => LLM calls CalculatorTool, returns "100"
#
# @example Weather question
#   ToolsAgent.call(query: "What's the weather in Tokyo?")
#   # => LLM calls WeatherTool, returns formatted weather
#
# @example Complex query
#   ToolsAgent.call(query: "What's the weather in London? And calculate 15% of 200.")
#   # => LLM may call both tools
#
# @example Inspecting tool calls
#   result = ToolsAgent.call(query: "What's 10 + 5?")
#   result.tool_calls         # => [{ "name" => "calculate", ... }]
#   result.tool_calls_count   # => 1
#   result.has_tool_calls?    # => true
#
class ToolsAgent < ApplicationAgent
  description 'Demonstrates tool usage with calculator and weather tools'

  model 'gpt-4o' # GPT-4o has good tool calling capabilities
  temperature 0.0 # Deterministic for consistent tool calls
  timeout 45

  # Register tools available to this agent
  # The LLM will receive descriptions and can call them as needed
  tools [CalculatorTool, WeatherTool]

  param :query, required: true

  def system_prompt
    <<~PROMPT
      You are a helpful assistant with access to tools for calculations and weather information.

      When the user asks about:
      - Math operations: Use the calculator tool
      - Weather information: Use the weather tool

      Always use the appropriate tool when needed, then provide a clear answer based on the results.
      If the user asks about something you can't help with, explain your limitations.
    PROMPT
  end

  def user_prompt
    query
  end

  def metadata
    {
      showcase: 'tools',
      features: %w[tools tool_calls tool_loop]
    }
  end
end
