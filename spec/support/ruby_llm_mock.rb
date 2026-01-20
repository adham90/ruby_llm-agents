# frozen_string_literal: true

# Mock RubyLLM module for testing agents without actual API calls
module RubyLLM
  class MockResponse
    attr_reader :content, :input_tokens, :output_tokens, :model_id

    def initialize(content, input_tokens: 10, output_tokens: 5, model_id: "gpt-4o")
      @content = content
      @input_tokens = input_tokens
      @output_tokens = output_tokens
      @model_id = model_id
    end

    # Returns usage data in the format expected by BaseAgent
    def usage
      {
        input_tokens: @input_tokens,
        output_tokens: @output_tokens,
        cache_creation_input_tokens: 0,
        cache_read_input_tokens: 0
      }
    end

    # Alias for backward compatibility with tests
    def total_tokens
      @input_tokens + @output_tokens
    end

    # Thinking support (returns nil by default)
    def thinking
      nil
    end

    def thinking_content
      nil
    end

    def tool_call?
      false
    end

    def tool_calls
      []
    end

    # Finish reason (stop, length, tool_calls, etc.)
    def finish_reason
      "stop"
    end
  end

  class MockClient
    attr_reader :model, :temperature, :instructions, :schema, :tools, :messages

    def initialize
      @model = nil
      @temperature = nil
      @instructions = nil
      @schema = nil
      @messages = []
      @tools = []
    end

    def with_model(model)
      @model = model
      self
    end

    def with_temperature(temperature)
      @temperature = temperature
      self
    end

    def with_instructions(instructions)
      @instructions = instructions
      self
    end

    def with_schema(schema)
      @schema = schema
      self
    end

    def with_tools(*tools)
      @tools = tools
      self
    end

    def add_message(role:, content:)
      @messages << { role: role, content: content }
      self
    end

    def ask(_prompt)
      MockResponse.new("Mock response")
    end
  end

  class << self
    def chat
      MockClient.new
    end
  end
end
