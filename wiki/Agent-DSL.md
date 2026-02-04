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

### description

Document what your agent does (displayed in dashboard and introspection):

```ruby
class MyAgent < ApplicationAgent
  description "Extracts search intent and filters from user queries"
end
```

Access programmatically:

```ruby
MyAgent.description  # => "Extracts search intent and filters from user queries"
```

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

### cache_for (Preferred)

Enable response caching with TTL:

```ruby
class MyAgent < ApplicationAgent
  cache_for 1.hour     # Cache for 1 hour
  # cache_for 30.minutes
  # cache_for 1.day
end
```

### cache (Deprecated)

> **Deprecated:** Use `cache_for` instead. This method still works but may be removed in a future version.

```ruby
class MyAgent < ApplicationAgent
  cache 1.hour  # Deprecated - use cache_for instead
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

### thinking

Enable extended thinking/reasoning for supported models:

```ruby
class MyAgent < ApplicationAgent
  model "claude-opus-4-5-20250514"
  thinking effort: :high, budget: 10000
end
```

**Options:**
- `effort:` - Thinking depth (`:none`, `:low`, `:medium`, `:high`)
- `budget:` - Maximum tokens for thinking computation

**Runtime override:**
```ruby
# Override at call time
MyAgent.call(query: "Complex problem", thinking: { effort: :high, budget: 15000 })

# Disable for simple questions
MyAgent.call(query: "Quick question", thinking: false)
```

**Access thinking data:**
```ruby
result = MyAgent.call(query: "Solve this...")
result.thinking_text   # The reasoning process
result.has_thinking?   # Whether thinking was used
result.thinking_tokens # Tokens used for thinking
```

See [Thinking](Thinking) for details on supported providers and best practices.

### tools

Register tools for the agent to use:

```ruby
class MyAgent < ApplicationAgent
  tools [SearchTool, CalculatorTool, WeatherTool]
end
```

For dynamic tool selection based on runtime context, override as an instance method:

```ruby
class SmartAgent < ApplicationAgent
  param :user_role

  def tools
    base = [SearchTool, InfoTool]
    user_role == "admin" ? base + [AdminTool] : base
  end
end
```

See [Tools](Tools) for details.

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

  # Parameter with type validation (v0.4.0+)
  param :count, type: :integer, required: true
  param :tags, type: :array, default: []
  param :options, type: :hash
  param :enabled, type: :boolean, default: true
end
```

**Supported Types:**

| Type | Ruby Class | Example |
|------|------------|---------|
| `:string` | String | `"hello"` |
| `:integer` | Integer | `42` |
| `:float` | Float | `3.14` |
| `:boolean` | TrueClass/FalseClass | `true` |
| `:array` | Array | `[1, 2, 3]` |
| `:hash` | Hash | `{ key: "value" }` |

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

### reliability (Block DSL)

Group all reliability settings in a single block (v0.4.0+):

```ruby
class MyAgent < ApplicationAgent
  model "gpt-4o"

  reliability do
    retries max: 3, backoff: :exponential
    fallback_models "gpt-4o-mini", "claude-3-5-sonnet"
    circuit_breaker errors: 10, within: 60, cooldown: 300
    total_timeout 30
  end
end
```

This is equivalent to setting each option individually but provides better organization for complex configurations.

## Callbacks

### before_call

Register callbacks that run before the LLM call. Use these for input validation, preprocessing, moderation, or PII redaction.

```ruby
class MyAgent < ApplicationAgent
  # Method name
  before_call :validate_input
  before_call :sanitize_pii

  # Block
  before_call { |context| context.params[:timestamp] = Time.current }

  private

  def validate_input(context)
    raise ArgumentError, "Query required" if context.params[:query].blank?
  end

  def sanitize_pii(context)
    # Custom PII redaction logic
    context.params[:query] = RedactionService.redact(context.params[:query])
  end
end
```

**Callback behavior:**
- Receives the pipeline context as the first argument
- Can mutate the context (params, prompts, etc.)
- Raising an exception blocks execution
- Return value is ignored

### after_call

Register callbacks that run after the LLM call completes. Use these for logging, notifications, post-processing, or analytics.

```ruby
class MyAgent < ApplicationAgent
  # Method name
  after_call :log_response
  after_call :notify_completion

  # Block
  after_call { |context, response| Analytics.track(context, response) }

  private

  def log_response(context, response)
    Rails.logger.info("Agent response: #{response.content.truncate(100)}")
  end

  def notify_completion(context, response)
    WebhookService.notify(agent: self.class.name, success: response.present?)
  end
end
```

**Callback behavior:**
- Receives the pipeline context and response as arguments
- Return value is ignored
- Exceptions are logged but don't affect the result

### Example: Custom Moderation

```ruby
class ModeratedAgent < ApplicationAgent
  model "gpt-4o"

  before_call :check_content_safety

  private

  def check_content_safety(context)
    result = ContentModerationService.check(context.params[:query])
    raise ContentPolicyViolation, result.reason if result.flagged?
  end
end
```

### Example: PII Redaction

```ruby
class SecureAgent < ApplicationAgent
  model "gpt-4o"

  before_call :redact_sensitive_data

  private

  def redact_sensitive_data(context)
    context.params.each do |key, value|
      next unless value.is_a?(String)
      context.params[key] = PIIRedactor.redact(value)
    end
  end
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

### messages

Define conversation history for multi-turn conversations:

```ruby
def messages
  [
    { role: :user, content: "Previous question" },
    { role: :assistant, content: "Previous answer" }
  ]
end
```

You can also pass messages at call-time or use the chainable `with_messages` method:

```ruby
# Call-time
MyAgent.call(query: "Follow up", messages: [...])

# Chainable
agent.with_messages([...]).call
```

See [Conversation History](Conversation-History) for details.

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
  description "Generates SEO-optimized blog articles from topics"
  temperature 0.7
  version "1.2"
  timeout 90
  cache_for 2.hours  # Use cache_for instead of cache

  # Grouped reliability configuration
  reliability do
    retries max: 3, backoff: :exponential
    fallback_models "gpt-4o-mini"
    total_timeout 120
  end

  param :topic, required: true
  param :tone, default: "professional"
  param :word_count, type: :integer, default: 500
  param :user_id, type: :integer, required: true

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
- [Conversation History](Conversation-History) - Multi-turn conversations
- [Tools](Tools) - Using tools with agents
- [Thinking](Thinking) - Extended reasoning support
- [Reliability](Reliability) - Fault tolerance configuration
- [Caching](Caching) - Cache configuration
