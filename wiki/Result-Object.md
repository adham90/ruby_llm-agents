# Result Object

Every agent call returns a `Result` object containing the response and rich metadata.

## Basic Usage

```ruby
result = MyAgent.call(query: "test")

# The LLM's response
result.content  # => { key: "value", ... }
```

## Accessing Content

### Direct Access

```ruby
result.content
# => { refined_query: "red dress", filters: ["color:red"] }
```

### Hash-Style Access (Deprecated)

> **Deprecated (v0.4.0):** Direct hash-style access on the result object is deprecated. Use `result.content[:key]` instead of `result[:key]`.

The Result object delegates to content for backward compatibility, but this will be removed in a future version:

```ruby
# Deprecated - avoid this pattern
result[:refined_query]        # => "red dress"

# Preferred - use content explicitly
result.content[:refined_query]        # => "red dress"
result.content.dig(:nested, :key)     # => "value"
result.content.fetch(:key, "default") # => "default"
```

### Enumeration

```ruby
result.each { |k, v| puts "#{k}: #{v}" }
result.keys   # => [:refined_query, :filters]
result.values # => ["red dress", ["color:red"]]
```

## Token Usage

```ruby
result.input_tokens   # => 150  - Tokens in the prompt
result.output_tokens  # => 50   - Tokens in the response
result.total_tokens   # => 200  - Total tokens used
result.cached_tokens  # => 0    - Tokens from cache (some providers)
```

## Cost Information

```ruby
result.input_cost   # => 0.000150  - Cost of input tokens
result.output_cost  # => 0.000100  - Cost of output tokens
result.total_cost   # => 0.000250  - Total cost in USD
```

## Model Information

```ruby
result.model_id         # => "gpt-4o"  - Model used
result.chosen_model_id  # => "gpt-4o"  - Final model (may differ if fallback used)
result.temperature      # => 0.0       - Temperature setting
```

## Timing Information

```ruby
result.duration_ms            # => 1234  - Total execution time
result.started_at             # => 2024-01-15 10:30:00 UTC
result.completed_at           # => 2024-01-15 10:30:01 UTC
result.time_to_first_token_ms # => 245   - Streaming only
```

## Status Information

```ruby
result.success?       # => true  - Did the call succeed?
result.finish_reason  # => "stop", "length", "tool_calls", etc.
result.streaming?     # => false - Was streaming enabled?
result.truncated?     # => false - Was output truncated (hit max_tokens)?
```

### Finish Reasons

| Reason | Meaning |
|--------|---------|
| `"stop"` | Normal completion |
| `"length"` | Hit max_tokens limit |
| `"tool_calls"` | Model wants to call tools |
| `"content_filter"` | Content was filtered |

## Tool Calls

For agents using tools:

```ruby
result.tool_calls        # => [{ "id" => "call_abc", "name" => "search", ... }]
result.tool_calls_count  # => 1
result.has_tool_calls?   # => true
```

## Thinking Information

For agents with extended thinking enabled:

```ruby
result.thinking_text       # => "Let me work through this step by step..."
result.thinking_signature  # => "sig_abc123" (for multi-turn, Claude)
result.thinking_tokens     # => 500 - Tokens used for thinking
result.has_thinking?       # => true - Whether thinking was used
```

### Checking for Thinking

```ruby
result = ReasoningAgent.call(query: "Complex problem")

if result.has_thinking?
  puts "Reasoning:"
  puts result.thinking_text
  puts "\nThinking tokens used: #{result.thinking_tokens}"
end

puts "\nAnswer:"
puts result.content
```

See [Thinking](Thinking) for configuration details.

## Reliability Information

When using retries or fallbacks:

```ruby
result.attempts_count  # => 3     - Number of attempts made
result.used_fallback?  # => true  - Was a fallback model used?
result.chosen_model_id # => "gpt-4o-mini"  - The model that succeeded
```

### Accessing Attempt Details (v0.4.0+)

Get detailed information about each attempt:

```ruby
result.attempts
# => [
#   { model: "gpt-4o", status: "error", error: "Rate limit", duration_ms: 150 },
#   { model: "gpt-4o", status: "error", error: "Rate limit", duration_ms: 320 },
#   { model: "gpt-4o-mini", status: "success", duration_ms: 850 }
# ]

# Check specific conditions
result.attempts.any? { |a| a[:status] == "error" }  # => true
result.attempts.last[:model]                         # => "gpt-4o-mini"
```

### Fallback Information

```ruby
result.fallback_chain   # => ["gpt-4o", "gpt-4o-mini"] - Models tried in order
result.fallback_reason  # => "rate_limited" - Why fallback was triggered
result.cache_hit?       # => false - Whether response came from cache
```

## Full Metadata Hash

Get everything as a hash:

```ruby
result.to_h
# => {
#   content: { refined_query: "red dress", ... },
#   input_tokens: 150,
#   output_tokens: 50,
#   total_tokens: 200,
#   cached_tokens: 0,
#   input_cost: 0.000150,
#   output_cost: 0.000100,
#   total_cost: 0.000250,
#   model_id: "gpt-4o",
#   chosen_model_id: "gpt-4o",
#   temperature: 0.0,
#   duration_ms: 1234,
#   started_at: 2024-01-15 10:30:00 UTC,
#   completed_at: 2024-01-15 10:30:01 UTC,
#   finish_reason: "stop",
#   streaming: false,
#   tool_calls: [],
#   tool_calls_count: 0,
#   attempts_count: 1,
#   used_fallback: false
# }
```

## Dry Run Results

When using `dry_run: true`:

```ruby
result = MyAgent.call(query: "test", dry_run: true)

result[:dry_run]       # => true
result[:agent]         # => "MyAgent"
result[:model]         # => "gpt-4o"
result[:temperature]   # => 0.0
result[:system_prompt] # => "You are..."
result[:user_prompt]   # => "Process: test"
result[:schema]        # => "RubyLLM::Schema"
```

## Error Results

When an execution fails:

```ruby
result = MyAgent.call(query: "test")

if result.success?
  process(result.content)
else
  handle_error(result.error)
end

# Error information
result.error         # => "Rate limit exceeded"
result.error_class   # => "RateLimitError"
```

## Working with Results in Controllers

```ruby
class SearchController < ApplicationController
  def search
    result = SearchAgent.call(query: params[:q])

    if result.success?
      render json: {
        results: result.content,
        meta: {
          tokens: result.total_tokens,
          cost: result.total_cost,
          duration_ms: result.duration_ms
        }
      }
    else
      render json: { error: result.error }, status: :service_unavailable
    end
  end
end
```

## Logging Results

```ruby
result = MyAgent.call(query: query)

Rails.logger.info({
  agent: "MyAgent",
  success: result.success?,
  tokens: result.total_tokens,
  cost: result.total_cost,
  duration_ms: result.duration_ms,
  model: result.chosen_model_id
}.to_json)
```

## Comparing Results

```ruby
# Track metrics over time
results = queries.map { |q| MyAgent.call(query: q) }

avg_cost = results.sum(&:total_cost) / results.size
avg_tokens = results.sum(&:total_tokens) / results.size
avg_duration = results.sum(&:duration_ms) / results.size

puts "Average cost: $#{avg_cost.round(6)}"
puts "Average tokens: #{avg_tokens}"
puts "Average duration: #{avg_duration}ms"
```

## Related Pages

- [Agent DSL](Agent-DSL) - Configuring agents
- [Prompts and Schemas](Prompts-and-Schemas) - Structuring outputs
- [Execution Tracking](Execution-Tracking) - Persisted execution data
- [Reliability](Reliability) - Retries and fallbacks
