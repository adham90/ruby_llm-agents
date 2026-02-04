# Extended Thinking Support

Extended thinking (also known as reasoning or chain-of-thought) allows LLM models to show their reasoning process before providing a final answer. This is particularly useful for complex problem-solving, math, logic puzzles, and multi-step analysis tasks.

## Supported Providers

| Provider | Thinking Visible | Configuration |
|----------|-----------------|---------------|
| Claude (Anthropic/Bedrock) | Yes | `effort` + `budget` |
| Gemini 2.5+ | Yes | `budget` (token count) |
| Gemini 3 | Yes | `effort` levels |
| OpenAI (o1/o3) | No (hidden) | `effort` only |
| Perplexity | Yes | Streams `<think>` blocks |
| Mistral Magistral | Yes | Always on |
| Ollama Qwen3 | Yes | Default on, `:none` to disable |

## Basic Usage

### DSL Configuration

Configure thinking at the agent class level:

```ruby
class ReasoningAgent < ApplicationAgent
  model "claude-opus-4-5-20250514"
  thinking effort: :high, budget: 10000

  param :query, required: true

  def system_prompt
    "You are a reasoning assistant. Show your work step by step."
  end

  def user_prompt
    query
  end
end
```

### Calling the Agent

```ruby
result = ReasoningAgent.call(query: "What is 127 * 43?")

# Access the reasoning/thinking content
puts "Thinking:"
puts result.thinking_text

puts "\nAnswer:"
puts result.content

# Check if thinking was used
if result.has_thinking?
  puts "Thinking tokens used: #{result.thinking_tokens}"
end
```

## Configuration Options

### Effort Levels

The `effort` option controls how much "thinking" the model does:

| Level | Description |
|-------|-------------|
| `:none` | Disable thinking |
| `:low` | Light reasoning, faster responses |
| `:medium` | Balanced reasoning |
| `:high` | Deep reasoning, best for complex problems |

```ruby
class QuickAgent < ApplicationAgent
  thinking effort: :low  # Fast, light reasoning
end

class DeepAgent < ApplicationAgent
  thinking effort: :high  # Thorough, detailed reasoning
end
```

### Token Budget

The `budget` option caps the maximum tokens used for thinking:

```ruby
class BudgetedAgent < ApplicationAgent
  thinking effort: :high, budget: 5000  # Max 5000 tokens for thinking
end
```

**Note:** Thinking tokens are billed by providers. Higher budgets increase costs.

## Runtime Override

Override thinking configuration at call time:

```ruby
# Override effort and budget
result = MyAgent.call(
  query: "Complex problem...",
  thinking: { effort: :high, budget: 15000 }
)

# Disable thinking for this call
result = MyAgent.call(
  query: "Simple question",
  thinking: false
)

# Use lower effort for speed
result = MyAgent.call(
  query: "Quick question",
  thinking: { effort: :low }
)
```

## Result Object

The Result object includes thinking-related accessors:

```ruby
result = ThinkingAgent.call(query: "Solve this problem")

# Thinking content
result.thinking_text       # String - the reasoning content
result.thinking_signature  # String - for multi-turn continuity (Claude)
result.thinking_tokens     # Integer - tokens used for thinking
result.has_thinking?       # Boolean - whether thinking was used
```

## Streaming with Thinking

When streaming, thinking chunks typically arrive before content chunks:

```ruby
ThinkingAgent.stream(query: "Analyze this data...") do |chunk|
  if chunk.thinking&.text
    # Display thinking in a collapsible UI element
    print "[Thinking] #{chunk.thinking.text}"
  elsif chunk.content
    # Stream the actual response
    print chunk.content
  end
end
```

## Global Default

Set a default thinking configuration for all agents:

```ruby
# config/initializers/ruby_llm_agents.rb
RubyLLM::Agents.configure do |config|
  config.default_thinking = { effort: :medium }
  # or
  config.default_thinking = nil  # disabled by default (recommended)
end
```

**Recommendation:** Keep thinking disabled by default to avoid unexpected costs. Enable it per-agent as needed.

## Multi-turn Conversations

For Claude, the thinking signature enables continuity across conversation turns:

```ruby
class ConversationAgent < ApplicationAgent
  model "claude-opus-4-5-20250514"
  thinking effort: :high

  def messages
    # Include thinking signature from previous turns
    # for context continuity
    conversation_history_with_signatures
  end
end
```

## Cost Considerations

Thinking tokens are billed by providers:

- **Claude:** Thinking tokens count toward output tokens
- **Gemini:** Budget affects cost
- **OpenAI:** Reasoning tokens are billed but hidden

Monitor costs via the dashboard or budget controls:

```ruby
RubyLLM::Agents.configure do |config|
  config.budgets = {
    global_daily: 50.0,
    per_agent_daily: { "ReasoningAgent" => 10.0 },
    enforcement: :hard
  }
end
```

## Best Practices

1. **Use appropriate effort levels** - Use `:high` for complex problems, `:low` for simple queries
2. **Set token budgets** - Prevent runaway costs with reasonable budget limits
3. **Disable for simple tasks** - Override with `thinking: false` for trivial queries
4. **Monitor usage** - Track thinking token usage in the dashboard
5. **Cache when possible** - Enable caching for deterministic thinking results
6. **Test with dry_run** - Verify configuration without API calls

```ruby
# Verify thinking configuration
result = MyAgent.call(query: "test", dry_run: true)
# Check the configuration in result.content
```

## Example Agent

See the complete example in your Rails app:

```ruby
# app/agents/thinking_agent.rb
class ThinkingAgent < ApplicationAgent
  description "Demonstrates extended thinking/reasoning support"

  model "claude-opus-4-5-20250514"
  temperature 0.0
  thinking effort: :high, budget: 10000

  param :query, required: true

  def system_prompt
    <<~PROMPT
      You are a reasoning assistant that excels at step-by-step problem solving.

      When given a problem:
      1. Break it down into smaller steps
      2. Work through each step carefully
      3. Verify your work
      4. Provide a clear final answer
    PROMPT
  end

  def user_prompt
    query
  end
end
```

## Providers Without Thinking Support

If you use the thinking DSL with a provider that doesn't support thinking, the configuration is silently ignored. This allows you to write agents that work across providers without conditional logic.

```ruby
class FlexibleAgent < ApplicationAgent
  model "gpt-4o"  # Doesn't support visible thinking
  thinking effort: :medium  # Silently ignored

  # Agent works normally without thinking
end
```
