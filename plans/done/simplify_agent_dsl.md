# Plan: Simplify Agent DSL

## Goal

Redesign the agent DSL to be more intuitive, reduce boilerplate, and make prompts first-class citizens. The new DSL should feel natural to Ruby developers while maintaining full flexibility for complex use cases.

## Current Pain Points

### 1. Too Many Ways to Configure the Same Thing

```ruby
# Block style
reliability do
  retries max: 3, backoff: :exponential
end

# Method style
retries max: 3, backoff: :exponential

# Which is "right"?
```

### 2. Deep Inheritance Chain

```
BaseAgent → Base → ApplicationAgent → YourAgent
```

- Hard to know where configuration comes from
- Debugging inheritance issues is frustrating
- Mental model overhead

### 3. Prompts Buried in Template Methods

```ruby
class SearchAgent < ApplicationAgent
  model "gpt-4o"
  param :query, required: true

  # The actual prompt is hidden down here
  def user_prompt
    "Search for: #{query}"
  end

  def system_prompt
    "You are a helpful assistant."
  end
end
```

Prompts are the *heart* of an agent — they should be front and center.

### 4. Verbose for Simple Cases

A simple agent that just sends a prompt requires:
- Class definition
- Model declaration
- Parameter declaration
- Method override for `user_prompt`
- Optional method override for `system_prompt`

### 5. Scattered DSL Modules

- `DSL::Base` — model, timeout, schema
- `DSL::Reliability` — retries, fallbacks, circuit breaker
- `DSL::Caching` — cache_for, cache_key_includes/excludes
- `BaseAgent` — params, streaming, tools, thinking
- `Base` — callbacks (before_call, after_call)

These feel like separate systems bolted together rather than a cohesive DSL.

### 6. Inconsistent Naming

| Current | What It Does |
|---------|--------------|
| `user_prompt` | The main prompt sent to the LLM |
| `system_prompt` | System instructions |
| `cache_for` | Enable caching with TTL |
| `cache_key_includes` | Add params to cache key |
| `reliability { }` | Configure error handling |

Some are verbs, some are nouns, some are imperative, some are declarative.

### 7. Required vs Optional Not Obvious

```ruby
param :query, required: true   # Required
param :limit                   # Optional? Has no default...
param :format, default: "json" # Optional with default
```

---

## Design Principles

1. **One obvious way** to do each thing
2. **Prompts are first-class** — they're the core of an agent, should be visible at the top
3. **Flat hierarchy** — composition over deep inheritance
4. **Progressive disclosure** — simple things simple, complex things possible
5. **Declarative over imperative** — describe what, not how
6. **Convention over configuration** — sensible defaults, minimal boilerplate
7. **Consistency** — all DSL methods follow the same patterns

---

## New DSL Design

### Core Philosophy

The agent class should read like a specification:
1. What model to use
2. What the system instructions are
3. What prompt to send
4. What parameters it accepts
5. What output structure to return
6. How to handle failures

### Minimal Agent (One Line of Config)

```ruby
class SearchAgent < Agent
  prompt "Search for: {query}"
end

SearchAgent.call(query: "ruby gems")
```

- Parameters are **auto-detected** from `{placeholder}` syntax
- Model defaults to `RubyLLM::Agents.configuration.default_model`
- No boilerplate

### Simple Agent with System Prompt

```ruby
class SearchAgent < Agent
  system "You are a helpful search assistant. Be concise."
  prompt "Search for: {query} (limit: {limit})"

  param :limit, default: 10  # Override auto-detected param with default
end
```

### Dynamic Prompts (Block Syntax)

When you need logic in your prompt, use a block:

```ruby
class SummarizerAgent < Agent
  system "You are a summarization expert."

  prompt do
    base = "Summarize the following text"
    base += " in #{language}" if language != "english"
    base += " (max #{max_words} words)" if max_words
    base + ":\n\n#{text}"
  end

  param :text
  param :language, default: "english"
  param :max_words, default: nil
end
```

### With Structured Output

```ruby
class AnalysisAgent < Agent
  model "gpt-4o"

  system "You are a data analyst."
  prompt "Analyze this data: {data}"

  param :data

  returns do
    string :summary, "A brief summary of the analysis"
    array :insights, of: :string, description: "Key insights discovered"
    number :confidence, "Confidence score from 0 to 1"
    boolean :needs_review, "Whether human review is recommended"
  end
end

result = AnalysisAgent.call(data: sales_data)
result.summary      # => "Sales increased 15%..."
result.insights     # => ["Q4 was strongest", "Mobile up 30%"]
result.confidence   # => 0.87
result.needs_review # => false
```

### Error Handling (on_failure block)

```ruby
class RobustAgent < Agent
  model "gpt-4o"

  system "You are a helpful assistant."
  prompt "Answer: {question}"

  param :question

  on_failure do
    retry times: 3, backoff: :exponential, base: 0.5
    fallback to: ["gpt-4o-mini", "gpt-3.5-turbo"]
    circuit_breaker after: 5, cooldown: 5.minutes
    timeout 30.seconds
  end
end
```

The name `on_failure` is more intuitive than `reliability` — it describes *when* this config applies.

### Caching

```ruby
class CachedAgent < Agent
  prompt "Translate to {language}: {text}"

  cache for: 1.hour
  cache key: [:text, :language]  # Explicit cache key params (optional)
end
```

Single `cache` method with clear options instead of three separate methods.

### Tools

```ruby
class ToolAgent < Agent
  system "You have access to tools. Use them when needed."
  prompt "{question}"

  param :question

  tools Calculator, WebSearch, WeatherLookup
end
```

### Conversation History

```ruby
class ChatAgent < Agent
  system "You are a friendly assistant."
  prompt "{message}"

  param :message
  param :history, default: []

  conversation from: :history
end

# Usage
ChatAgent.call(
  message: "What did I just ask?",
  history: [
    { role: :user, content: "Hello" },
    { role: :assistant, content: "Hi there!" }
  ]
)
```

### Callbacks (Hooks)

```ruby
class AuditedAgent < Agent
  prompt "Process: {input}"

  param :input

  before do |context|
    context[:started_at] = Time.current
    Rails.logger.info("Starting #{self.class.name}")
  end

  after do |context, result|
    duration = Time.current - context[:started_at]
    Analytics.track("agent_call", agent: self.class.name, duration: duration)
  end
end
```

### Streaming

Streaming is a **call-site decision**, not class configuration:

```ruby
class StreamingAgent < Agent
  prompt "Write a story about: {topic}"
  param :topic
end

# Non-streaming (default)
result = StreamingAgent.call(topic: "dragons")

# Streaming
StreamingAgent.stream(topic: "dragons") do |chunk|
  print chunk.content
end
```

### Extended Thinking

```ruby
class ReasoningAgent < Agent
  model "claude-sonnet-4-20250514"

  system "Think through problems carefully."
  prompt "Solve: {problem}"

  param :problem

  thinking effort: :high, budget: 10_000
end
```

### Full-Featured Example

```ruby
class FullFeaturedAgent < Agent
  # Model configuration
  model "gpt-4o"
  temperature 0.7

  # Prompts (the core of the agent)
  system "You are an expert analyst with access to tools."
  prompt do
    "Analyze the following #{data_type} data:\n\n#{data}"
  end

  # Parameters
  param :data
  param :data_type, default: "general"
  param :history, default: []

  # Conversation history
  conversation from: :history

  # Structured output
  returns do
    string :summary
    array :findings, of: :string
    object :metadata do
      number :confidence
      string :method_used
    end
  end

  # Tools
  tools Calculator, DataVisualizer

  # Error handling
  on_failure do
    retry times: 2, backoff: :exponential
    fallback to: "gpt-4o-mini"
    circuit_breaker after: 5, cooldown: 5.minutes
  end

  # Caching
  cache for: 30.minutes

  # Hooks
  before { |ctx| validate_data!(ctx.params[:data]) }
  after { |ctx, result| notify_if_low_confidence(result) }

  private

  def validate_data!(data)
    raise ArgumentError, "Data cannot be empty" if data.blank?
  end

  def notify_if_low_confidence(result)
    Slack.notify("#alerts", "Low confidence analysis") if result.metadata.confidence < 0.5
  end
end
```

---

## Specialized Agent Types

### Embedder

```ruby
class DocumentEmbedder < Embedder
  model "text-embedding-3-small"
  dimensions 512
  batch_size 100

  preprocess do |text|
    text.strip.downcase.gsub(/\s+/, " ")
  end
end

# Usage
embedding = DocumentEmbedder.embed("Hello world")
embeddings = DocumentEmbedder.embed_batch(["Hello", "World"])
```

### Speaker (Text-to-Speech)

```ruby
class Narrator < Speaker
  provider :openai
  model "tts-1-hd"
  voice "nova"
  speed 1.0
  format :mp3
end

# Usage
audio = Narrator.speak("Welcome to the show")
audio.data   # Binary audio data
audio.format # :mp3
```

### Transcriber (Speech-to-Text)

```ruby
class AudioTranscriber < Transcriber
  model "whisper-1"
  language "en"

  format :verbose_json  # Include timestamps
end

# Usage
result = AudioTranscriber.transcribe("recording.mp3")
result.text      # "Hello, world..."
result.segments  # [{start: 0.0, end: 1.2, text: "Hello"}, ...]
```

### ImageGenerator

```ruby
class LogoGenerator < ImageGenerator
  model "dall-e-3"
  size "1024x1024"
  quality :hd
  style :vivid

  prompt "A minimalist logo for {company}, {style_description} style"
  negative "text, watermark, blurry, low quality"

  param :company
  param :style_description, default: "modern tech"
end

# Usage
image = LogoGenerator.generate(company: "Acme Corp")
image.url  # URL to generated image
image.data # Binary image data (if requested)
```

### ImageAnalyzer

```ruby
class ProductAnalyzer < ImageAnalyzer
  model "gpt-4o"

  prompt "Analyze this product image and identify: {aspects}"

  param :aspects, default: "quality, brand, condition"

  returns do
    string :product_name
    array :identified_aspects, of: :string
    number :quality_score
  end
end

# Usage
result = ProductAnalyzer.analyze("product.jpg", aspects: "defects, authenticity")
```

---

## API Comparison

### Creating and Calling Agents

| Current | Proposed |
|---------|----------|
| `MyAgent.call(query: "x")` | `MyAgent.call(query: "x")` (same) |
| `MyAgent.call(query: "x") { \|c\| }` | `MyAgent.stream(query: "x") { \|c\| }` |
| `MyAgent.call(query: "x", dry_run: true)` | `MyAgent.dry_run(query: "x")` |
| `MyAgent.call(query: "x", skip_cache: true)` | `MyAgent.call(query: "x", cache: false)` |

### DSL Methods

| Current | Proposed | Rationale |
|---------|----------|-----------|
| `def user_prompt` | `prompt "..."` | Declarative, visible |
| `def system_prompt` | `system "..."` | Shorter, clearer |
| `param :x, required: true` | `param :x` | Required by default (most are) |
| `param :x` | `param :x, default: nil` | Explicit optionality |
| `reliability { }` | `on_failure { }` | Intent-revealing name |
| `cache_for 1.hour` | `cache for: 1.hour` | Grouped config |
| `cache_key_includes :x` | `cache key: [:x]` | Simpler API |
| `streaming true` | `.stream()` | Call-site decision |
| `schema { }` | `returns { }` | Describes output |
| `before_call :method` | `before { }` | Block-only, simpler |
| `after_call :method` | `after { }` | Block-only, simpler |
| `fallback_models "x"` | `fallback to: "x"` | Inside on_failure block |

---

## Parameter Auto-Detection

The `prompt` string syntax `{param_name}` automatically registers parameters:

```ruby
class MyAgent < Agent
  prompt "Search for {query} in {category}"
end

# Equivalent to:
class MyAgent < Agent
  prompt "Search for {query} in {category}"
  param :query      # auto-registered, required
  param :category   # auto-registered, required
end
```

You can override auto-detected params to add defaults:

```ruby
class MyAgent < Agent
  prompt "Search for {query} in {category}"
  param :category, default: "all"  # Now optional
end
```

---

## Inheritance & Composition

### Flat Hierarchy

```
Agent (conversation agents)
Embedder (embeddings)
Speaker (text-to-speech)
Transcriber (speech-to-text)
ImageGenerator (image generation)
ImageAnalyzer (image analysis)
ImageEditor (image editing)
```

No deep inheritance. Each is a standalone base class.

### ApplicationAgent Pattern

```ruby
# app/agents/application_agent.rb
class ApplicationAgent < Agent
  # Shared config for all agents in your app
  model "gpt-4o"
  temperature 0

  on_failure do
    retry times: 2
    fallback to: "gpt-4o-mini"
  end

  before { |ctx| ctx[:tenant] = Current.tenant }
  after { |ctx, result| track_usage(ctx, result) }
end

# app/agents/search_agent.rb
class SearchAgent < ApplicationAgent
  system "You are a search assistant."
  prompt "Search: {query}"
end
```

### Mixins for Shared Behavior

```ruby
module Auditable
  extend ActiveSupport::Concern

  included do
    after { |ctx, result| AuditLog.create!(agent: self.class.name, result: result) }
  end
end

class SensitiveAgent < ApplicationAgent
  include Auditable

  prompt "Process sensitive data: {data}"
end
```

---

## Implementation Plan

### Phase 1: Core DSL Rewrite

1. **Create new `Agent` base class** with simplified DSL
   - `prompt` (string or block)
   - `system` (string or block)
   - `param` with auto-detection from prompt placeholders
   - `returns` for schema definition

2. **Implement `on_failure` block**
   - `retry`, `fallback`, `circuit_breaker`, `timeout`
   - Remove separate `DSL::Reliability` module

3. **Simplify caching to single `cache` method**
   - `cache for: TTL`
   - `cache key: [params]`
   - Remove `DSL::Caching` module

4. **Implement `before`/`after` hooks**
   - Block-only syntax
   - Remove method-reference style

### Phase 2: Specialized Agents

5. **Create `Embedder` base class**
   - `embed`, `embed_batch` class methods
   - `preprocess` block

6. **Create `Speaker` base class**
   - `speak` class method
   - Provider/voice/format config

7. **Create `Transcriber` base class**
   - `transcribe` class method
   - Language/format config

8. **Create `ImageGenerator` base class**
   - `generate` class method
   - Size/quality/style config
   - `prompt` and `negative` DSL

9. **Create `ImageAnalyzer` base class**
   - `analyze` class method
   - Integration with `returns` schema

### Phase 3: Migration & Compatibility

10. **Deprecation layer** for old DSL
    - `user_prompt` → `prompt`
    - `system_prompt` → `system`
    - `reliability { }` → `on_failure { }`
    - Emit deprecation warnings

11. **Update generators**
    - New agent templates use simplified DSL
    - Migration guide in generator output

12. **Update documentation & examples**
    - New README with simplified examples
    - Migration guide for existing users

---

## Files to Create/Modify

| File | Action | Description |
|------|--------|-------------|
| `lib/ruby_llm/agents/agent.rb` | Create | New base class with simplified DSL |
| `lib/ruby_llm/agents/embedder.rb` | Modify | Simplify to match new patterns |
| `lib/ruby_llm/agents/speaker.rb` | Modify | Simplify to match new patterns |
| `lib/ruby_llm/agents/transcriber.rb` | Modify | Simplify to match new patterns |
| `lib/ruby_llm/agents/image_generator.rb` | Modify | Simplify to match new patterns |
| `lib/ruby_llm/agents/image_analyzer.rb` | Modify | Simplify to match new patterns |
| `lib/ruby_llm/agents/dsl/prompt.rb` | Create | Prompt parsing & interpolation |
| `lib/ruby_llm/agents/dsl/failure.rb` | Create | on_failure block handling |
| `lib/ruby_llm/agents/dsl/schema.rb` | Create | returns block handling |
| `lib/ruby_llm/agents/dsl/params.rb` | Create | Parameter DSL with auto-detection |
| `lib/ruby_llm/agents/deprecation.rb` | Create | Deprecation warnings for old DSL |
| `lib/generators/ruby_llm_agents/agent/templates/` | Modify | Update templates |
| `README.md` | Modify | Update documentation |
| `MIGRATION.md` | Create | Migration guide from old DSL |

---

## Backward Compatibility Strategy

### Deprecation Warnings

```ruby
class LegacyAgent < ApplicationAgent
  model "gpt-4o"
  param :query, required: true

  def user_prompt
    # DEPRECATION WARNING: `user_prompt` method is deprecated.
    # Use `prompt "..."` class method instead.
    "Search: #{query}"
  end
end
```

### Compatibility Shim

```ruby
module RubyLLM::Agents::LegacyDSL
  def user_prompt
    # Called if no `prompt` DSL defined
    nil
  end

  def system_prompt
    # Called if no `system` DSL defined
    nil
  end
end
```

### Migration Timeline

1. **v1.x** — New DSL available, old DSL still works with deprecation warnings
2. **v2.0** — Old DSL removed, migration required

---

## Open Questions

1. **Auto-detection syntax**: `{param}` vs `%{param}` vs `{{param}}`?
   - `{param}` is cleanest but conflicts with Ruby block syntax in strings
   - `%{param}` is Ruby's format string syntax
   - `{{param}}` is Mustache-style, unambiguous

2. **Required by default**: Is this too opinionated?
   - Pro: Most params *are* required, reduces boilerplate
   - Con: Breaks convention that no modifier = optional

3. **Streaming as call-site decision**: Remove class-level `streaming` entirely?
   - Pro: Cleaner, streaming is truly a runtime choice
   - Con: Some agents are *always* streamed (chat UIs)

4. **Callbacks block-only**: Remove method reference style?
   - Pro: Simpler API, one way to do things
   - Con: Method references allow reuse across agents

---

## Success Metrics

- [ ] Simple agent requires ≤3 lines of DSL
- [ ] All DSL methods are discoverable via class methods
- [ ] No deep inheritance (max 2 levels: Base → ApplicationAgent → YourAgent)
- [ ] Prompts visible at top of class definition
- [ ] One obvious way to configure each feature
- [ ] Existing agents can migrate with deprecation warnings
- [ ] All current functionality preserved

---

## Example Migration

### Before (Current DSL)

```ruby
class SearchAgent < ApplicationAgent
  model "gpt-4o"
  temperature 0.5

  cache_for 1.hour
  cache_key_includes :query, :limit

  reliability do
    retries max: 3, backoff: :exponential
    fallback_models "gpt-4o-mini"
    circuit_breaker errors: 5, within: 60, cooldown: 300
  end

  param :query, required: true
  param :limit, default: 10
  param :category, default: "all"

  before_call :validate_query
  after_call :log_result

  def system_prompt
    "You are a helpful search assistant."
  end

  def user_prompt
    "Search for '#{query}' in category '#{category}' (limit: #{limit})"
  end

  def schema
    RubyLLM::Schema.create do
      array :results do
        string :title
        string :url
        string :snippet
      end
    end
  end

  private

  def validate_query(context)
    raise ArgumentError, "Query too short" if context.params[:query].length < 3
  end

  def log_result(context, response)
    Rails.logger.info("Search returned #{response.results.length} results")
  end
end
```

### After (New DSL)

```ruby
class SearchAgent < ApplicationAgent
  model "gpt-4o"
  temperature 0.5

  system "You are a helpful search assistant."
  prompt "Search for '{query}' in category '{category}' (limit: {limit})"

  param :limit, default: 10
  param :category, default: "all"

  returns do
    array :results do
      string :title
      string :url
      string :snippet
    end
  end

  on_failure do
    retry times: 3, backoff: :exponential
    fallback to: "gpt-4o-mini"
    circuit_breaker after: 5, cooldown: 5.minutes
  end

  cache for: 1.hour, key: [:query, :limit]

  before { |ctx| raise ArgumentError, "Query too short" if ctx.params[:query].length < 3 }
  after { |ctx, result| Rails.logger.info("Search returned #{result.results.length} results") }
end
```

**Line count: 45 → 24 (47% reduction)**

---

## Notes

- This is a significant breaking change — needs major version bump
- Consider providing a codemod/migration script
- The simplified DSL should make the library more approachable for new users
- Power users can still access underlying primitives if needed
