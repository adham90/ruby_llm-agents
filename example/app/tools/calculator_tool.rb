# frozen_string_literal: true

# Sample calculator tool for demonstrating tools DSL
#
# This tool shows how to:
# - Define a tool with description
# - Accept required and optional parameters
# - Return formatted results for the LLM
# - Handle errors gracefully
#
# @example Usage via ToolsAgent
#   ToolsAgent.call(query: "What is 25 * 4?")
#
class CalculatorTool < RubyLLM::Tool
  description 'Perform basic mathematical calculations. Supports addition, subtraction, multiplication, division, and exponentiation.'

  param :operation, desc: 'Math operation: add, subtract, multiply, divide, power', required: true
  param :a, desc: 'First number', required: true
  param :b, desc: 'Second number', required: true
  param :precision, desc: 'Decimal places for result', type: :integer, required: false

  def execute(operation:, a:, b:, precision: nil)
    precision ||= 2
    a = a.to_f
    b = b.to_f

    result = case operation.to_s.downcase
             when 'add', '+'
               a + b
             when 'subtract', '-'
               a - b
             when 'multiply', '*', 'x'
               a * b
             when 'divide', '/'
               return 'Error: Division by zero' if b.zero?

               a / b
             when 'power', '^', '**'
               a**b
             else
               return "Error: Unknown operation '#{operation}'. Supported: add, subtract, multiply, divide, power"
             end

    "Result: #{result.round(precision)}"
  rescue StandardError => e
    "Error: #{e.message}"
  end
end
