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

  # Mock speech response for text-to-speech
  class MockSpeechResponse
    attr_reader :audio, :model_id, :voice, :format

    def initialize(audio: "mock_audio_data", model_id: "tts-1", voice: "nova", format: "mp3")
      @audio = audio
      @model_id = model_id
      @voice = voice
      @format = format
    end

    def data
      @audio
    end

    def cost
      0.015
    end
  end

  # Mock embedding response
  class MockEmbeddingResponse
    attr_reader :vectors, :model_id, :input_tokens

    def initialize(vectors: nil, model_id: "text-embedding-3-small", input_tokens: 10, dimensions: 1536)
      @vectors = vectors || [Array.new(dimensions) { rand(-1.0..1.0) }]
      @model_id = model_id
      @input_tokens = input_tokens
    end

    def embedding
      @vectors.first
    end

    def embeddings
      @vectors
    end

    def usage
      { input_tokens: @input_tokens }
    end

    def cost
      0.0001
    end
  end

  # Mock moderation response
  class MockModerationResponse
    attr_reader :model_id, :results

    def initialize(flagged: false, model_id: "omni-moderation-latest", categories: {})
      @model_id = model_id
      @flagged = flagged
      @categories = categories
      @results = [{ flagged: flagged, categories: categories, category_scores: {} }]
    end

    def flagged?
      @flagged
    end

    def categories
      @categories
    end

    def category_scores
      {}
    end
  end

  # Mock transcription response
  class MockTranscriptionResponse
    attr_reader :text, :model_id, :language, :duration, :segments

    def initialize(text: "Mock transcription", model_id: "whisper-1", language: "en", duration: 10.0)
      @text = text
      @model_id = model_id
      @language = language
      @duration = duration
      @segments = []
    end

    def cost
      0.006
    end
  end

  # Mock image generation response
  class MockImageResponse
    attr_reader :url, :data, :model_id, :revised_prompt

    def initialize(url: "https://example.com/image.png", data: nil, model_id: "dall-e-3", revised_prompt: nil)
      @url = url
      @data = data
      @model_id = model_id
      @revised_prompt = revised_prompt
    end

    def images
      [self]
    end

    def cost
      0.04
    end
  end

  class << self
    def chat
      MockClient.new
    end

    # Text-to-speech
    def speak(text, model: nil, voice: nil, **options)
      MockSpeechResponse.new(model_id: model || "tts-1", voice: voice || "nova")
    end

    # Embeddings
    def embed(input, model: nil, dimensions: nil, **options)
      MockEmbeddingResponse.new(model_id: model || "text-embedding-3-small", dimensions: dimensions || 1536)
    end

    # Moderation
    def moderate(input, model: nil, **options)
      MockModerationResponse.new(model_id: model || "omni-moderation-latest")
    end

    # Transcription
    def transcribe(audio, model: nil, **options)
      MockTranscriptionResponse.new(model_id: model || "whisper-1")
    end

    # Image generation
    def paint(prompt, model: nil, **options)
      MockImageResponse.new(model_id: model || "dall-e-3")
    end
  end
end
