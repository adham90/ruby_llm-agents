# frozen_string_literal: true

# Mock RubyLLM module for testing agents without actual API calls
module RubyLLM
  class MockResponse
    attr_reader :content

    def initialize(content)
      @content = content
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
