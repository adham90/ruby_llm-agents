# Agent DSL Reference

The Agent DSL provides a clean, declarative way to configure your AI agents.

## Class-Level Configuration

### model

Set the LLM model for the agent:

```ruby
class MyAgent < ApplicationAgent
  model "gpt-4o"                    # OpenAI GPT-4
  # model "claude-3-5-sonnet"       # Anthropic Claude
  # model "gemini-2.0-flash"        # Google Gemini (default)
end
```

**Supported Models:**

| Provider | Models |
|----------|--------|
| OpenAI | `gpt-4o`, `gpt-4o-mini`, `gpt-4-turbo`, `gpt-3.5-turbo` |
| Anthropic | `claude-3-5-sonnet`, `claude-3-opus`, `claude-3-haiku` |
| Google | `gemini-2.0-flash`, `gemini-1.5-pro`, `gemini-1.5-flash` |

### temperature

Control response randomness (0.0 = deterministic, 2.0 = very random):

```ruby
class MyAgent < ApplicationAgent
  temperature 0.0   # Deterministic, best for classification
  # temperature 0.7 # Balanced, good for general use
  # temperature 1.0 # Creative, good for brainstorming
end
```

### version

Version string for cache invalidation:

```ruby
class MyAgent < ApplicationAgent
  version "2.0"  # Changing this invalidates cached responses
end
```

### timeout

Maximum time for a single request (in seconds):

```ruby
class MyAgent < ApplicationAgent
  timeout 60     # Default
  # timeout 120  # For slow/complex prompts
end
```

### cache

Enable response caching with TTL:

```ruby
class MyAgent < ApplicationAgent
  cache 1.hour     # Cache for 1 hour
  # cache 30.minutes
  # cache 1.day
end
```

### streaming

Enable real-time response streaming:

```ruby
class MyAgent < ApplicationAgent
  streaming true
end
```

See [Streaming](Streaming) for details.

## Parameters

### param

Define agent parameters:

```ruby
class MyAgent < ApplicationAgent
  # Required parameter - raises ArgumentError if missing
  param :query, required: true

  # Optional parameter with default
  param :limit, default: 10

  # Optional parameter without default (nil)
  param :filters
end
```

Parameters are accessible as methods:

```ruby
def user_prompt
  "Search for: #{query} (limit: #{limit})"
end
```

See [Parameters](Parameters) for details.

## Reliability Configuration

### retries

Configure automatic retry behavior:

```ruby
class MyAgent < ApplicationAgent
  retries max: 3                              # Max 3 retries
  retries max: 3, backoff: :exponential       # With exponential backoff
  retries max: 3, backoff: :constant          # Fixed delay between retries
  retries max: 3, base: 0.5, max_delay: 10.0  # Custom backoff timing
end
```

See [Automatic Retries](Automatic-Retries) for details.

### fallback_models

Specify fallback models if primary fails:

```ruby
class MyAgent < ApplicationAgent
  model "gpt-4o"
  fallback_models "gpt-4o-mini", "claude-3-5-sonnet"
end
```

See [Model Fallbacks](Model-Fallbacks) for details.

### circuit_breaker

Prevent cascading failures:

```ruby
class MyAgent < ApplicationAgent
  circuit_breaker errors: 10, within: 60, cooldown: 300
end
```

See [Circuit Breakers](Circuit-Breakers) for details.

### total_timeout

Maximum time for all attempts (including retries):

```ruby
class MyAgent < ApplicationAgent
  retries max: 5
  total_timeout 30  # Abort everything after 30 seconds
end
```

## Instance Methods to Override

### system_prompt

Define the agent's role and instructions:

```ruby
private

def system_prompt
  <<~PROMPT
    You are a helpful assistant specializing in #{domain}.
    Always respond in a professional tone.
  PROMPT
end
```

### user_prompt

Define the main request (required):

```ruby
def user_prompt
  <<~PROMPT
    Process this request: #{query}
    Constraints: #{constraints}
  PROMPT
end
```

### schema

Define structured output format:

```ruby
def schema
  @schema ||= RubyLLM::Schema.create do
    string :result, description: "The result"
    array :items, of: :string
  end
end
```

See [Prompts and Schemas](Prompts-and-Schemas) for details.

### process_response

Post-process the LLM response:

```ruby
def process_response(response)
  result = super(response)

  # Add custom processing
  result[:processed_at] = Time.current
  result[:word_count] = result[:summary].split.size

  result
end
```

### execution_metadata

Add custom metadata to execution logs:

```ruby
def execution_metadata
  {
    user_id: user_id,
    source: source,
    request_id: Current.request_id
  }
end
```

### cache_key_data

Customize cache key generation:

```ruby
def cache_key_data
  # Only include these fields in cache key
  { query: query, user_id: user_id }
  # Excludes 'limit' - different limits return same cached result
end
```

## Complete Example

```ruby
class ContentGeneratorAgent < ApplicationAgent
  model "gpt-4o"
  temperature 0.7
  version "1.2"
  timeout 90
  cache 2.hours

  retries max: 3, backoff: :exponential
  fallback_models "gpt-4o-mini"

  param :topic, required: true
  param :tone, default: "professional"
  param :word_count, default: 500
  param :user_id, required: true

  private

  def system_prompt
    <<~PROMPT
      You are a professional content writer.
      Write in a #{tone} tone with clear structure.
    PROMPT
  end

  def user_prompt
    <<~PROMPT
      Write a #{word_count}-word article about: #{topic}

      Requirements:
      - Clear introduction, body, and conclusion
      - Use examples where relevant
    PROMPT
  end

  def schema
    @schema ||= RubyLLM::Schema.create do
      string :title, description: "Article title"
      string :content, description: "Full article content"
      array :tags, of: :string, description: "Relevant tags"
    end
  end

  def process_response(response)
    result = super(response)
    result[:generated_at] = Time.current
    result
  end

  def execution_metadata
    { user_id: user_id, topic: topic }
  end
end
```

## Related Pages

- [Parameters](Parameters) - Parameter definition details
- [Prompts and Schemas](Prompts-and-Schemas) - Output structuring
- [Reliability](Reliability) - Fault tolerance configuration
- [Caching](Caching) - Cache configuration
