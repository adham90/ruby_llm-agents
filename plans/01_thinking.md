# Thinking Support Implementation Plan

## Overview

Add extended thinking/reasoning support to ruby_llm-agents, allowing agents to show their reasoning process before providing a final answer. This leverages the existing `with_thinking` support in ruby_llm (v1.10+).

## Supported Providers

| Provider | Thinking Visible | Configuration |
|----------|-----------------|---------------|
| Claude (Anthropic/Bedrock) | Yes | `effort` + `budget` |
| Gemini 2.5 | Yes | `budget` (token count) |
| Gemini 3 | Yes | `effort` levels |
| OpenAI (o1/o3) | No (hidden) | `effort` only |
| Perplexity | Yes | Streams `<think>` blocks |
| Mistral Magistral | Yes | Always on |
| Ollama Qwen3 | Yes | Default on, `:none` to disable |

## Implementation Tasks

### 1. DSL Extension (`lib/ruby_llm/agents/base/dsl.rb`)

Add new `thinking` class method to configure thinking behavior:

```ruby
class MyAgent < ApplicationAgent
  model 'claude-opus-4.5'
  thinking effort: :high, budget: 8000
end
```

**Options:**
- `effort:` - Qualitative depth (`:none`, `:low`, `:medium`, `:high`)
- `budget:` - Token cap for thinking computation (integer)

**Implementation:**
- Add `thinking` class method that stores configuration
- Add `resolved_thinking` instance method for runtime resolution
- Support runtime override via `call(thinking: { effort: :low })`

### 2. Result Object Enhancement (`lib/ruby_llm/agents/result.rb`)

Add thinking-related accessors to the Result class:

```ruby
result = MyAgent.call(query: "Complex problem")
result.thinking           # ThinkingData object or nil
result.thinking_text      # String - the reasoning content
result.thinking_signature # String - for multi-turn (Claude)
result.thinking_tokens    # Integer - tokens used for thinking
result.has_thinking?      # Boolean
```

**New ThinkingData class or simple hash:**
```ruby
# Option A: Dedicated class
class ThinkingData
  attr_reader :text, :signature, :tokens
end

# Option B: Simple hash access (recommended for simplicity)
# result.thinking returns { text: "...", signature: "...", tokens: 123 }
```

### 3. Execution Logic (`lib/ruby_llm/agents/base/execution.rb`)

Modify `build_client` to apply thinking configuration:

```ruby
def build_client
  client = RubyLLM.chat
    .with_model(model)
    .with_temperature(temperature)
    # ... existing configuration ...

  # Add thinking support
  if (thinking_config = resolved_thinking)
    client = client.with_thinking(**thinking_config)
  end

  client
end
```

**Changes needed:**
- Add `resolved_thinking` method to merge class-level and runtime config
- Apply `with_thinking` to the client when configured
- Extract thinking data from response in `safe_extract_response_data`

### 4. Response Extraction (`lib/ruby_llm/agents/instrumentation.rb`)

Update `safe_extract_response_data` to capture thinking:

```ruby
def safe_extract_response_data(response)
  {
    # ... existing fields ...
    thinking_text: response.thinking&.text,
    thinking_signature: response.thinking&.signature,
    thinking_tokens: response.thinking&.tokens
  }
end
```

### 5. Streaming Support (`lib/ruby_llm/agents/base/execution.rb`)

Ensure thinking works with streaming:

```ruby
MyAgent.stream(query: "Problem") do |chunk|
  # Thinking chunks come first
  if chunk.thinking&.text
    print "[Thinking] #{chunk.thinking.text}"
  end

  # Then content chunks
  print chunk.content if chunk.content
end
```

**Considerations:**
- Thinking chunks typically arrive before content chunks
- May need separate callbacks or chunk type detection
- Document streaming behavior for users

### 6. Database Schema (Optional - Execution Tracking)

Add columns to `ruby_llm_agents_executions` table for thinking data:

```ruby
# Migration
add_column :ruby_llm_agents_executions, :thinking_text, :text
add_column :ruby_llm_agents_executions, :thinking_signature, :text
add_column :ruby_llm_agents_executions, :thinking_tokens, :integer
```

**Note:** This is optional but recommended for analytics and debugging.

### 7. Configuration Defaults (`lib/ruby_llm/agents/configuration.rb`)

Add global default thinking configuration:

```ruby
RubyLLM::Agents.configure do |config|
  config.default_thinking = { effort: :medium }
  # or
  config.default_thinking = nil  # disabled by default
end
```

### 8. Documentation (`wiki/Thinking.md`)

Create comprehensive documentation covering:
- Overview of thinking/reasoning support
- Provider compatibility matrix
- DSL configuration examples
- Streaming with thinking
- Accessing thinking data from results
- Multi-turn conversations with thinking signatures
- Cost considerations (thinking tokens are billed)

## File Changes Summary

| File | Change Type | Description |
|------|-------------|-------------|
| `lib/ruby_llm/agents/base/dsl.rb` | Modify | Add `thinking` DSL method |
| `lib/ruby_llm/agents/base/execution.rb` | Modify | Apply thinking to client, extract from response |
| `lib/ruby_llm/agents/result.rb` | Modify | Add thinking accessors |
| `lib/ruby_llm/agents/instrumentation.rb` | Modify | Extract thinking data from response |
| `lib/ruby_llm/agents/configuration.rb` | Modify | Add default_thinking option |
| `db/migrate/xxx_add_thinking_to_executions.rb` | New | Optional migration for tracking |
| `wiki/Thinking.md` | New | Documentation |
| `spec/thinking_spec.rb` | New | Test coverage |

## API Design

### Basic Usage

```ruby
class ReasoningAgent < ApplicationAgent
  model 'claude-opus-4.5'
  thinking effort: :high, budget: 10000

  prompt do
    "Solve this step by step: {{query}}"
  end
end

result = ReasoningAgent.call(query: "What is 127 * 43?")

puts "Thinking:"
puts result.thinking_text

puts "\nAnswer:"
puts result.content
```

### Runtime Override

```ruby
# Override at call time
result = ReasoningAgent.call(
  query: "Simple question",
  thinking: { effort: :low }
)

# Disable thinking for this call
result = ReasoningAgent.call(
  query: "Quick question",
  thinking: false
)
```

### Streaming with Thinking

```ruby
ReasoningAgent.stream(query: "Complex problem") do |chunk|
  if chunk.thinking&.text
    # Show thinking in a collapsible UI element
    update_thinking_display(chunk.thinking.text)
  elsif chunk.content
    # Stream the actual response
    append_to_response(chunk.content)
  end
end
```

### Multi-turn with Thinking Signature (Claude)

```ruby
class ConversationAgent < ApplicationAgent
  model 'claude-opus-4.5'
  thinking effort: :high

  def messages
    # Include thinking signature for context continuity
    conversation_history_with_signatures
  end
end
```

## Testing Strategy

1. **Unit Tests**
   - DSL configuration parsing
   - Result object thinking accessors
   - Thinking config resolution (class vs runtime)

2. **Integration Tests**
   - Mock ruby_llm responses with thinking data
   - Verify thinking passed to client correctly
   - Test streaming with thinking chunks

3. **Provider-specific Tests** (if feasible)
   - Test with actual Claude API (optional, slow)
   - Test with Gemini API (optional, slow)

## Cost Considerations

Document that thinking tokens are billed:
- Claude: Thinking tokens count toward output tokens
- Gemini: Budget affects cost
- OpenAI: Reasoning tokens are billed but hidden

Users should be aware that enabling thinking increases API costs.

## Migration Path

1. **Phase 1**: Core implementation (DSL, execution, result)
2. **Phase 2**: Streaming support
3. **Phase 3**: Database tracking (optional)
4. **Phase 4**: Documentation and examples

## Open Questions

1. Should thinking be enabled by default for supported models?
   - **Recommendation**: No, keep it opt-in to avoid unexpected costs

2. Should we add a `thinking_only` mode that returns just the reasoning?
   - **Recommendation**: Not initially, can add later if requested

3. How to handle providers that don't support thinking?
   - **Recommendation**: Silently ignore or log warning, don't error

4. Should thinking data be included in cached responses?
   - **Recommendation**: Yes, cache the full response including thinking
