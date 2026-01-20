# Async/Fiber Integration

RubyLLM::Agents supports concurrent execution using Ruby's Fiber scheduler. When used inside an `Async` block, LLM operations automatically become non-blocking, allowing you to handle many concurrent requests with minimal resources.

## Why Async for LLM Operations?

Traditional thread-based approaches have limitations:
- LLM operations take 5-60 seconds, spending 99% of time waiting
- Each thread consumes ~1MB of memory
- Thread pool exhaustion under load

Async/Fiber approach:
- Lightweight fibers (~10KB each) instead of threads
- Single database connection shared across fibers
- 100x more concurrent operations with same resources

## Installation

Add the async gem to your Gemfile:

```ruby
gem 'async', '~> 2.0'
```

Then bundle install:

```bash
bundle install
```

## Basic Usage

### Concurrent Agent Execution

```ruby
require 'async'

Async do
  # These run concurrently, not sequentially
  results = [
    Async { SentimentAgent.call(input: "I love this!") },
    Async { SummaryAgent.call(input: "Long text...") },
    Async { CategoryAgent.call(input: "Product review") }
  ].map(&:wait)
end
```

### Using the Batch Helper

The `RubyLLM::Agents::Async.batch` method provides rate-limited concurrent execution:

```ruby
require 'async'

Async do
  results = RubyLLM::Agents::Async.batch([
    [SentimentAgent, { input: "Text 1" }],
    [SentimentAgent, { input: "Text 2" }],
    [SentimentAgent, { input: "Text 3" }]
  ], max_concurrent: 5)
end
```

### Processing Collections

```ruby
Async do
  reviews = ["Great!", "Terrible!", "Okay"]

  results = RubyLLM::Agents::Async.each(reviews, max_concurrent: 10) do |review|
    SentimentAgent.call(input: review)
  end
end
```

### Stream Results as They Complete

```ruby
Async do
  RubyLLM::Agents::Async.stream(agents_with_params) do |result, agent_class, index|
    puts "#{agent_class.name} finished: #{result.content}"
  end
end
```

## Configuration

```ruby
RubyLLM::Agents.configure do |config|
  # Maximum concurrent operations for batch processing
  config.async_max_concurrency = 20
end
```

## How It Works

RubyLLM uses `Net::HTTP` which automatically cooperates with Ruby's fiber scheduler. When you wrap agent calls in an `Async` block:

1. **Automatic Detection**: The gem detects it's running in an async context
2. **Non-blocking I/O**: HTTP requests yield to other fibers while waiting
3. **Shared Resources**: Database connections and HTTP pools are shared efficiently
4. **Transparent Fallback**: Outside async context, everything works synchronously

```
BEFORE (Threads):              AFTER (Fibers):
┌─────────────┐                ┌─────────────┐
│  Thread 1   │ (1MB RAM)      │ Event Loop  │
│  blocking   │                │  (1 thread) │
└─────────────┘                └──────┬──────┘
┌─────────────┐                  ┌────┴────┐
│  Thread 2   │ (1MB RAM)        ▼         ▼
│  blocking   │                ┌─────┐   ┌─────┐
└─────────────┘                │Fiber│   │Fiber│  (~10KB each)
                               └─────┘   └─────┘
```

## Parallel Workflows

Parallel workflows automatically use fibers when in async context:

```ruby
class ReviewAnalyzer < RubyLLM::Agents::Workflow::Parallel
  branch :sentiment,  agent: SentimentAgent
  branch :summary,    agent: SummaryAgent
  branch :categories, agent: CategoryAgent
end

# In async context, uses fibers instead of threads
Async do
  result = ReviewAnalyzer.call(text: "Great product!")
end
```

## Retry Backoff

Retry delays are automatically non-blocking in async context:

```ruby
class ReliableAgent < ApplicationAgent
  retries max: 3, backoff: :exponential

  # In async context, sleep doesn't block other fibers
end
```

## Server Setup

### With Falcon (Recommended)

Falcon is an async-native web server:

```ruby
# Gemfile
gem 'falcon'
```

```bash
falcon serve
```

### With Puma

Puma works but requires wrapping requests in Async blocks:

```ruby
# app/controllers/api/agents_controller.rb
def analyze
  Async do
    result = RubyLLM::Agents::Async.batch(analysis_agents)
    render json: result
  end.wait
end
```

## Best Practices

### 1. Always Set Concurrency Limits

```ruby
# Prevent overwhelming API rate limits
RubyLLM::Agents::Async.batch(agents, max_concurrent: 10)
```

### 2. Use Batch for Large Collections

```ruby
# Good: Rate-limited batch processing
Async do
  RubyLLM::Agents::Async.batch(
    items.map { |item| [ProcessorAgent, { input: item }] },
    max_concurrent: 20
  )
end

# Avoid: Spawning unlimited concurrent tasks
Async do
  items.map { |item| Async { ProcessorAgent.call(input: item) } }.map(&:wait)
end
```

### 3. Handle Errors Per-Agent

```ruby
Async do
  results = RubyLLM::Agents::Async.batch(agents) do |result, index|
    if result.error?
      Rails.logger.error "Agent #{index} failed: #{result.error}"
    end
  end
end
```

## Checking Async Availability

```ruby
# Check if async gem is loaded
RubyLLM::Agents::Async.available?
# => true

# Check if currently in async context
RubyLLM::Agents::Async.async_context?
# => true (inside Async block)
```

## Comparison with Threads

| Feature | Threads (ThreadPool) | Fibers (Async) |
|---------|---------------------|----------------|
| Memory per worker | ~1MB | ~10KB |
| Context switching | Kernel (expensive) | Userspace (cheap) |
| Max concurrent | ~100 practical | ~10,000+ |
| DB connections | 1 per thread | Shared |
| Code changes | None | Wrap in `Async do` |

## Backwards Compatibility

Existing code works unchanged:

```ruby
# Still works exactly the same (synchronous)
result = MyAgent.call(input: "Hello")

# Opt-in to async
Async do
  result = MyAgent.call(input: "Hello")  # Now non-blocking
end
```

## Related

- [Parallel Workflows](Parallel-Workflows.md)
- [Reliability & Retries](Reliability.md)
- [Background Jobs](Background-Jobs.md)
