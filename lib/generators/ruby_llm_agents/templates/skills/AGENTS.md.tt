# Agents

This directory contains LLM-powered agents for the application. All agents inherit from `ApplicationAgent`.

## Creating a New Agent

Use the generator:
```bash
rails generate ruby_llm_agents:agent AgentName param1:required param2:default_value
```

Or create manually by extending `ApplicationAgent`:
```ruby
class MyAgent < ApplicationAgent
  # Configuration
  model "gpt-4o"
  temperature 0.0
  version "1.0"

  # Parameters
  param :query, required: true
  param :limit, default: 10

  private

  def system_prompt
    "You are a helpful assistant."
  end

  def user_prompt
    query
  end
end
```

## Directory Structure

```
app/agents/
├── application_agent.rb      # Base class for all agents
├── concerns/                 # Shared agent mixins
├── my_agent.rb              # Task agents at root
├── images/                   # Image operation agents
│   ├── product_generator.rb
│   └── content_analyzer.rb
├── audio/                    # Audio operation agents
│   ├── meeting_transcriber.rb
│   └── voice_narrator.rb
├── embedders/               # Embedding agents
│   └── semantic_embedder.rb
└── moderators/              # Moderation agents
    └── content_moderator.rb
```

## DSL Reference

### Model Configuration

| Method | Description | Example |
|--------|-------------|---------|
| `model` | LLM model to use | `model "gpt-4o"` |
| `temperature` | Response randomness (0.0-2.0) | `temperature 0.7` |
| `version` | Cache invalidation version | `version "2.0"` |
| `timeout` | Request timeout in seconds | `timeout 30` |
| `description` | Human-readable description | `description "Searches documents"` |

### Parameters

```ruby
param :name                          # Optional parameter
param :query, required: true         # Required parameter
param :limit, default: 10            # With default value
param :count, type: Integer          # With type validation
```

Access parameters as methods: `query`, `limit`, etc.

### Caching

```ruby
cache 1.hour                         # Enable with TTL
cache_for 30.minutes                 # Alias for cache

cache_key_includes :user_id, :query  # Only these params in cache key
cache_key_excludes :timestamp        # Exclude from cache key
```

### Reliability (Retries & Fallbacks)

```ruby
# Individual settings
retries max: 3, backoff: :exponential, base: 0.4, max_delay: 3.0
fallback_models "gpt-4o-mini", "claude-3-haiku"
total_timeout 30
circuit_breaker errors: 5, within: 60, cooldown: 300

# Or grouped in a block
reliability do
  retries max: 3, backoff: :exponential
  fallback_models "gpt-4o-mini"
  total_timeout 30
  circuit_breaker errors: 5, within: 60
end
```

### Streaming

```ruby
streaming true  # Enable streaming by default
```

### Tools

```ruby
tools [SearchTool, CalculatorTool]  # Make tools available to agent
```

### Extended Thinking

```ruby
thinking effort: :high              # Enable extended thinking
thinking budget: 10000              # With token budget
```

### Moderation

```ruby
moderation :input                   # Check input before LLM call
moderation :output                  # Check output after LLM call
moderation :both                    # Check both
```

## Required Methods

### `user_prompt` (required)
The prompt sent to the LLM. Must return a String.

### `system_prompt` (optional)
Instructions for the LLM. Return nil for no system prompt.

## Optional Overrides

### `schema`
Return a `RubyLLM::Schema` for structured JSON output:
```ruby
def schema
  @schema ||= RubyLLM::Schema.create do
    string :result, description: "The result"
    integer :confidence, description: "Confidence 1-100"
    array :tags do
      string
    end
  end
end
```

### `process_response(response)`
Transform the LLM response before returning:
```ruby
def process_response(response)
  content = response.content
  # Custom processing
  content
end
```

### `messages`
Provide conversation history for multi-turn:
```ruby
def messages
  [
    { role: :user, content: "Previous question" },
    { role: :assistant, content: "Previous answer" }
  ]
end
```

### `cache_key_data`
Customize what goes into the cache key:
```ruby
def cache_key_data
  { query: query, locale: I18n.locale }
end
```

### `execution_metadata`
Add custom data to execution logs:
```ruby
def execution_metadata
  { request_id: params[:request_id] }
end
```

## Calling Agents

```ruby
# Basic call
result = MyAgent.call(query: "hello")

# Access result
result.content          # The response content
result.input_tokens     # Tokens used in prompt
result.output_tokens    # Tokens in response
result.total_cost       # Cost in USD

# Debug mode (no API call)
result = MyAgent.call(query: "hello", dry_run: true)

# Skip cache
result = MyAgent.call(query: "hello", skip_cache: true)

# With attachments
result = MyAgent.call(query: "describe this", with: "image.png")

# Streaming
MyAgent.stream(query: "hello") do |chunk|
  print chunk.content
end

# Multi-tenancy
result = MyAgent.call(query: "hello", tenant: current_user)
```

## Specialized Agents

### Image Agents
```ruby
# app/agents/images/product_generator.rb
module Images
  class ProductGenerator < RubyLLM::Agents::Image::Generator
    model "dall-e-3"
    size "1024x1024"
    quality "hd"
  end
end

# Usage
result = Images::ProductGenerator.call(prompt: "A product photo")
result.url  # Image URL
```

### Audio Agents
```ruby
# app/agents/audio/meeting_transcriber.rb
module Audio
  class MeetingTranscriber < RubyLLM::Agents::Audio::Transcriber
    model "whisper-1"
  end
end

# Usage
result = Audio::MeetingTranscriber.call(audio: "meeting.mp3")
result.text  # Transcribed text
```

### Embedding Agents
```ruby
# app/agents/embedders/semantic_embedder.rb
module Embedders
  class SemanticEmbedder < RubyLLM::Agents::Embedder
    model "text-embedding-3-large"
  end
end

# Usage
result = Embedders::SemanticEmbedder.call(text: "Hello world")
result.embedding  # Vector array
```

## Testing Agents

```ruby
RSpec.describe MyAgent do
  describe ".call" do
    it "returns expected result" do
      # Use dry_run for unit tests
      result = described_class.call(query: "test", dry_run: true)
      expect(result.content[:user_prompt]).to eq("test")
    end
  end
end
```

## Best Practices

1. **Keep prompts focused** - One agent, one task
2. **Use structured output** - Define schemas for predictable responses
3. **Enable caching** - For deterministic queries
4. **Set appropriate temperatures** - 0.0 for deterministic, higher for creative
5. **Configure retries** - For production reliability
6. **Version your agents** - Bump version when changing prompts
