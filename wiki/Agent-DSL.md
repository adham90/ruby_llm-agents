# Agent DSL Reference

The Agent DSL provides a clean, declarative way to configure your AI agents.

## Simplified DSL (Recommended)

The simplified DSL uses three roles -- `system`, `user`, and `assistant` -- that map directly to the LLM message format:

```ruby
class SearchAgent < ApplicationAgent
  model "gpt-4o"

  system "You are a helpful search assistant. Be concise."
  user "Search for: {query} (limit: {limit})"

  param :limit, default: 10  # Override auto-detected param with default

  returns do
    array :results do
      string :title
      string :url
      string :snippet
    end
  end

  on_failure do
    retries times: 3, backoff: :exponential
    fallback to: "gpt-4o-mini"
    circuit_breaker after: 5, cooldown: 5.minutes
  end

  cache for: 1.hour

  before { |ctx| validate_query!(ctx.params[:query]) }
  after { |ctx, result| log_search(result) }
end
```

### Key Features

- **`system`** - System instructions (sets agent behavior and persona)
- **`user`** - Define user prompt with `{placeholder}` syntax (auto-registers required params)
- **`assistant`** - Prefill the assistant response (useful for forcing JSON or specific formats)
- **`returns`** - Structured output schema (alias for `schema`)
- **`on_failure`** - Error handling configuration (alias for `reliability`)
- **`cache for:, key:`** - Caching with cleaner syntax
- **`before`/`after`** - Simplified callbacks (block-only)

> **Deprecation note:** `prompt` still works as an alias for `user` but is deprecated. New code should use `user`.

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

### user (Simplified DSL)

Define the user prompt with automatic parameter detection:

```ruby
class SearchAgent < ApplicationAgent
  # Parameters {query} and {category} are auto-registered as required
  user "Search for {query} in {category}"
end
```

Override auto-detected parameters with defaults:

```ruby
class SearchAgent < ApplicationAgent
  user "Search for {query} in {category} (limit: {limit})"

  param :limit, default: 10  # Now optional with default
end
```

For dynamic prompts, use a block:

```ruby
class SummarizerAgent < ApplicationAgent
  param :text
  param :language, default: "english"

  user do
    base = "Summarize the following"
    base += " in #{language}" if language != "english"
    "#{base}: #{text}"
  end
end
```

> **Deprecated:** `prompt` is still accepted as an alias for `user` but should not be used in new code.

### assistant (Simplified DSL)

Prefill the beginning of the assistant's response. This is particularly useful with Anthropic models to force JSON output or guide the model's format:

```ruby
class JsonExtractorAgent < ApplicationAgent
  model "claude-3-5-sonnet"
  temperature 0.0

  system "You extract structured data from text. Always respond in valid JSON."

  user "Extract the key entities from:\n\n{text}"

  assistant "{"   # Forces the model to begin its response with "{"
end
```

You can also use `assistant` with a block for dynamic prefills:

```ruby
class TranslatorAgent < ApplicationAgent
  param :target_language, default: "Spanish"

  system "You are a translator. Return only the translated text."

  user "Translate the following to {target_language}:\n\n{text}"

  assistant do
    # Guide the model toward the target language's script
    case target_language
    when "Japanese" then "\u300C"   # Opening Japanese quote bracket
    when "French"   then "\u00AB "  # Opening guillemet
    else ""
    end
  end
end
```

**When to use `assistant`:**
- Force JSON output by prefilling `{` or `[`
- Ensure a specific output prefix or format
- Steer the model away from preamble text like "Sure, here is..."

### system (Simplified DSL)

Define system instructions:

```ruby
class MyAgent < ApplicationAgent
  system "You are a helpful assistant. Be concise and accurate."
end
```

For dynamic system prompts:

```ruby
class MyAgent < ApplicationAgent
  param :user_role, default: "user"

  system do
    "You are helping a #{user_role}. Adjust your response accordingly."
  end
end
```

### returns (Simplified DSL)

Define structured output (alias for `schema`):

```ruby
class AnalysisAgent < ApplicationAgent
  user "Analyze: {data}"

  returns do
    string :summary, description: "A brief summary"
    array :insights, of: :string, description: "Key insights"
    number :confidence, description: "Confidence score 0-1"
    boolean :needs_review, description: "Whether human review is needed"
  end
end
```

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

### timeout

Maximum time for a single request (in seconds):

```ruby
class MyAgent < ApplicationAgent
  timeout 60     # Default
  # timeout 120  # For slow/complex prompts
end
```

### cache (Simplified DSL)

Enable response caching with cleaner syntax:

```ruby
class MyAgent < ApplicationAgent
  cache for: 1.hour                          # Cache for 1 hour
  cache for: 30.minutes, key: [:query]       # With explicit cache key params
end
```

### cache_for (Alternative)

```ruby
class MyAgent < ApplicationAgent
  cache_for 1.hour     # Cache for 1 hour
  # cache_for 30.minutes
  # cache_for 1.day
end
```

### streaming

Enable real-time response streaming:

```ruby
class MyAgent < ApplicationAgent
  streaming true
end
```

Or use `.stream()` at call time (preferred):

```ruby
MyAgent.stream(query: "Hello") do |chunk|
  print chunk.content
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

**Auto-detected parameters:** When using the `user` DSL (or its deprecated alias `prompt`) with `{placeholder}` syntax, parameters are automatically registered as required unless you explicitly define them with `param`.

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

### on_failure (Simplified DSL)

Group all error handling in one block with intuitive syntax:

```ruby
class MyAgent < ApplicationAgent
  model "gpt-4o"

  on_failure do
    retries times: 3, backoff: :exponential  # Retry up to 3 times
    fallback to: ["gpt-4o-mini", "gpt-3.5-turbo"]  # Try these models next
    timeout 30  # Total timeout for all attempts
    circuit_breaker after: 5, cooldown: 5.minutes  # Open after 5 failures
  end
end
```

**Available options in `on_failure`:**

| Method | Description |
|--------|-------------|
| `retries times:, backoff:, base:, max_delay:` | Configure retry behavior |
| `fallback to:` | Fallback models (string or array) |
| `timeout` | Total timeout for all attempts |
| `circuit_breaker after:, within:, cooldown:` | Circuit breaker configuration |
| `non_fallback_errors` | Errors that should fail immediately |

### reliability (Alternative)

The block DSL for reliability configuration:

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

### Individual Methods

You can also configure reliability options individually:

```ruby
class MyAgent < ApplicationAgent
  retries max: 3, backoff: :exponential
  fallback_models "gpt-4o-mini", "gpt-3.5-turbo"
  circuit_breaker errors: 10, within: 60, cooldown: 300
  total_timeout 30
end
```

See [Automatic Retries](Automatic-Retries), [Model Fallbacks](Model-Fallbacks), and [Circuit Breakers](Circuit-Breakers) for details.

## Callbacks

### before / after (Simplified DSL)

Simplified block-only callbacks:

```ruby
class MyAgent < ApplicationAgent
  before { |ctx| ctx.params[:timestamp] = Time.current }
  after { |ctx, result| Analytics.track(result) }
end
```

### before_call / after_call (Full API)

Register callbacks with method names or blocks:

```ruby
class MyAgent < ApplicationAgent
  # Method name
  before_call :validate_input
  before_call :sanitize_pii

  # Block
  before_call { |context| context.params[:timestamp] = Time.current }

  # After callbacks
  after_call :log_response
  after_call { |context, response| Analytics.track(context, response) }

  private

  def validate_input(context)
    raise ArgumentError, "Query required" if context.params[:query].blank?
  end

  def log_response(context, response)
    Rails.logger.info("Agent response: #{response.content.truncate(100)}")
  end
end
```

**Callback behavior:**
- `before_call`: Receives pipeline context, can mutate it, raising blocks execution
- `after_call`: Receives context and response, return value ignored

## Instance Methods to Override

### system_prompt

Define the agent's role and instructions (alternative to `system` DSL):

```ruby
private

def system_prompt
  <<~S
    You are a helpful assistant specializing in #{domain}.
    Always respond in a professional tone.
  S
end
```

### user_prompt

Define the main request (alternative to `user` DSL):

```ruby
def user_prompt
  <<~S
    Process this request: #{query}
    Constraints: #{constraints}
  S
end
```

### schema

Define structured output format (alternative to `returns` DSL):

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

## Conversational Usage with `.ask`

While `.call` is stateless (fire-and-forget), `.ask` accumulates conversation history so each turn builds on the last. Use `.ask` when you need a multi-turn, chat-style interaction.

```ruby
agent = SearchAgent.new(limit: 10)

# First turn
result = agent.ask("red summer dress under $50")
result.content  # => { results: [...] }

# The agent remembers the first turn
result = agent.ask("now only show results with free shipping")
result.content  # => { results: [...filtered...] }
```

`.ask` accepts the same parameters as `.call`. You can also pass an ad-hoc user message as the first argument:

```ruby
agent = ContentGeneratorAgent.new(tone: "casual", word_count: 300, user_id: 1)

result = agent.ask("Write about remote work trends")
puts result.content[:title]

# Iterate on the output
result = agent.ask("Make it more upbeat and add a call to action")
puts result.content[:content]
```

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

### metadata

Add custom metadata to execution logs:

```ruby
def metadata
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

## Complete Example (Simplified DSL)

```ruby
class ContentGeneratorAgent < ApplicationAgent
  model "gpt-4o"
  description "Generates SEO-optimized blog articles from topics"
  temperature 0.7

  system do
    <<~S
      You are a professional content writer.
      Write in a {tone} tone with clear structure.
      Always return valid JSON with keys: title, content, tags.
    S
  end

  user "Write a {word_count}-word article about: {topic}"

  assistant "{"   # Force JSON output

  param :tone, default: "professional"
  param :word_count, default: 500
  param :user_id, required: true

  returns do
    string :title, description: "Article title"
    string :content, description: "Full article content"
    array :tags, of: :string, description: "Relevant tags"
  end

  on_failure do
    retries times: 3, backoff: :exponential
    fallback to: "gpt-4o-mini"
    timeout 120
  end

  cache for: 2.hours

  after { |ctx, result| result[:generated_at] = Time.current }
end
```

## Complete Example (Traditional DSL)

```ruby
class ContentGeneratorAgent < ApplicationAgent
  model "gpt-4o"
  description "Generates SEO-optimized blog articles from topics"
  temperature 0.7
  timeout 90
  cache_for 2.hours

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
    <<~S
      You are a professional content writer.
      Write in a #{tone} tone with clear structure.
    S
  end

  def user_prompt
    <<~S
      Write a #{word_count}-word article about: #{topic}

      Requirements:
      - Clear introduction, body, and conclusion
      - Use examples where relevant
    S
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

  def metadata
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
