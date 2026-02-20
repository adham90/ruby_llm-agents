# Querying Executions

Every agent class provides built-in methods for querying its execution history directly. Instead of manually scoping `RubyLLM::Agents::Execution.where(agent_type: "SearchAgent")`, you can use the agent class as your entry point.

## Agent-Centric Queries

### `.executions`

Returns an `ActiveRecord::Relation` scoped to this agent's executions. Chains with all existing Execution scopes.

```ruby
SearchAgent.executions                          # All executions
SearchAgent.executions.successful               # Successful only
SearchAgent.executions.today.expensive(1.00)    # Expensive today
SearchAgent.executions.by_tenant("acme")        # Tenant-scoped
SearchAgent.executions.streaming.slow(5000)     # Slow streaming
SearchAgent.executions.with_tool_calls          # Used tools
```

This is equivalent to:

```ruby
RubyLLM::Agents::Execution.by_agent("SearchAgent")
```

But more readable and less error-prone (no magic strings).

### `.last_run`

Returns the most recent execution for this agent.

```ruby
SearchAgent.last_run
# => #<RubyLLM::Agents::Execution id: 42, status: "success", ...>

SearchAgent.last_run&.total_cost
# => 0.025
```

### `.failures(since:)`

Returns failed executions within a time window (default: 24 hours).

```ruby
SearchAgent.failures                    # Last 24 hours
SearchAgent.failures(since: 7.days)    # Last 7 days
SearchAgent.failures(since: 1.hour)    # Last hour
```

### `.total_spent(since:)`

Returns total cost for this agent, optionally filtered by time window.

```ruby
SearchAgent.total_spent                 # All time total
SearchAgent.total_spent(since: 1.month) # Last month
SearchAgent.total_spent(since: 24.hours) # Last 24 hours
```

### `.stats(since:)`

Returns a comprehensive stats hash with counts, rates, costs, and token usage.

```ruby
SearchAgent.stats
# => {
#   total: 150,
#   successful: 145,
#   failed: 5,
#   success_rate: 96.7,
#   avg_duration_ms: 850,
#   avg_cost: 0.012,
#   total_cost: 1.80,
#   total_tokens: 75000,
#   avg_tokens: 500
# }

# Filter by time window
SearchAgent.stats(since: 24.hours)
SearchAgent.stats(since: 7.days)
```

### `.cost_by_model(since:)`

Returns cost breakdown grouped by model.

```ruby
SearchAgent.cost_by_model
# => {
#   "gpt-4o" => { count: 100, total_cost: 5.00, avg_cost: 0.05 },
#   "gpt-4o-mini" => { count: 50, total_cost: 0.25, avg_cost: 0.005 }
# }

SearchAgent.cost_by_model(since: 7.days)
```

### `.with_params(**params)`

Filters executions by parameter values stored in execution details.

```ruby
SearchAgent.with_params(user_id: "u123")
SearchAgent.with_params(user_id: "u123", category: "billing")
```

Works with SQLite and PostgreSQL (uses `json_extract` or `@>` operator respectively).

## Replay

Re-execute a previous run with the same or overridden inputs. Useful for:

- **A/B testing models** — compare GPT-4o vs Claude on the same input
- **Debugging** — reproduce a failed execution in development
- **Regression testing** — verify a prompt change doesn't break existing behavior
- **Cost optimization** — test cheaper models on real inputs

### Basic Replay

```ruby
run = SearchAgent.last_run
new_result = run.replay
```

### Replay with Model Override

```ruby
# Compare models on the same input
original = SearchAgent.last_run
gpt_result = original.replay(model: "gpt-4o")
claude_result = original.replay(model: "claude-3-5-sonnet")

puts "GPT-4o cost: $#{gpt_result.total_cost}"
puts "Claude cost: $#{claude_result.total_cost}"
```

### Replay with Temperature Override

```ruby
# Test different temperatures
run = SearchAgent.last_run
deterministic = run.replay(temperature: 0.0)
creative = run.replay(temperature: 1.0)
```

### Replay with Parameter Overrides

```ruby
# Override specific parameters while keeping others
run = SearchAgent.last_run
run.replay(query: "updated search term")
run.replay(query: "blue shirt", limit: 5)
```

### Checking Replay Status

```ruby
run = SearchAgent.last_run

# Can this execution be replayed?
run.replayable?     # => true (agent class exists and detail record present)

# Is this execution a replay of another?
run.replay?         # => false

# Get the original execution (if this is a replay)
run.replay_source   # => nil (not a replay)

# Find all replays of this execution
run.replays         # => ActiveRecord::Relation
run.replays.count   # => 3
```

### Querying Replays

```ruby
# Find all replays of execution #42
RubyLLM::Agents::Execution.replays_of(42)

# Compare costs across replays
original = SearchAgent.last_run
original.replays.each do |replay|
  puts "Model: #{replay.model_id}, Cost: $#{replay.total_cost}, " \
       "Duration: #{replay.duration_ms}ms"
end
```

### How Replay Works

1. Validates the execution has `agent_type`, a detail record, and a resolvable class
2. Loads the original agent class via `constantize`
3. Reconstructs parameters from the execution detail record
4. Merges any overrides (model, temperature, parameter values)
5. Calls `AgentClass.call(**params)` through the full pipeline
6. The new execution is automatically tracked with `replay_source_id` in metadata

### Replay Errors

`RubyLLM::Agents::ReplayError` is raised when:

- `agent_type` is blank
- The detail record is missing (prompts/parameters unavailable)
- The agent class no longer exists (deleted or renamed without aliases)

```ruby
begin
  execution.replay
rescue RubyLLM::Agents::ReplayError => e
  puts e.message
  # => "Cannot replay execution #42: agent class 'DeletedAgent' not found"
end
```

## Real-World Examples

### Daily Health Check

```ruby
# In a scheduled job or Rake task
agents = [SearchAgent, ContentAgent, SupportAgent]

agents.each do |agent|
  stats = agent.stats(since: 24.hours)
  next if stats[:total].zero?

  if stats[:success_rate] < 95.0
    SlackNotifier.alert(
      "#{agent.name} success rate dropped to #{stats[:success_rate]}%"
    )
  end

  if stats[:total_cost] > 50.0
    SlackNotifier.alert(
      "#{agent.name} spent $#{stats[:total_cost]} in last 24h"
    )
  end
end
```

### Cost Comparison Report

```ruby
# Compare costs across models for a specific agent
SearchAgent.cost_by_model(since: 7.days).each do |model, data|
  puts "#{model}: #{data[:count]} calls, $#{data[:total_cost]} total, " \
       "$#{data[:avg_cost]} avg"
end
```

### Debug Failed Executions

```ruby
# Find and replay recent failures
SearchAgent.failures(since: 1.hour).each do |failure|
  puts "Failed at #{failure.created_at}: #{failure.error_class}"
  puts "  #{failure.error_message}"

  if failure.replayable?
    result = failure.replay
    puts "  Replay: #{result.success? ? 'SUCCESS' : 'FAILED'}"
  end
end
```

### A/B Test Models

```ruby
# Take the last 10 successful runs and replay with a different model
SearchAgent.executions.successful.recent(10).each do |run|
  original_cost = run.total_cost
  replay_result = run.replay(model: "gpt-4o-mini")
  savings = original_cost - replay_result.total_cost

  puts "Run ##{run.id}: saved $#{savings.round(4)} with gpt-4o-mini"
end
```

## Related Pages

- [Agent DSL](Agent-DSL) - Agent configuration reference
- [Execution Tracking](Execution-Tracking) - What gets tracked
- [Database Queries](Database-Queries) - Low-level Execution model queries
- [API Reference](API-Reference) - Complete class documentation
