# Plan: Per-Model Error Tracking for Dashboard

## Problem

When multiple models fail during reliability fallback, only the final `AllModelsExhaustedError` is recorded on the dashboard. Individual per-model errors are lost.

## Current State

The infrastructure already exists but isn't wired together:

- **`AttemptTracker`** (`lib/ruby_llm/agents/infrastructure/attempt_tracker.rb`) — tracks per-attempt data (model_id, error_class, error_message, duration, tokens)
- **`Execution.attempts`** — JSON column in the database, already has methods like `failed_attempts`, `successful_attempt`, `short_circuited_attempts`
- **`Pipeline::Context`** — has `metadata` hash and custom `[]=` setter for arbitrary data

**Gap:** The reliability middleware doesn't create `AttemptTracker` records during fallback iterations.

## Implementation

### Step 1: Wire AttemptTracker into reliability middleware

**File:** `lib/ruby_llm/agents/pipeline/middleware/reliability.rb`

In `execute_with_reliability`, create an `AttemptTracker` and populate it during each model attempt:

```ruby
def execute_with_reliability(context, models_to_try, config, total_deadline)
  started_at = Time.current
  last_error = nil
  context.attempts_made = 0
  tracker = Agents::Infrastructure::AttemptTracker.new

  models_to_try.each do |current_model|
    breaker = get_circuit_breaker(current_model, context)
    if breaker&.open?
      tracker.record_short_circuit(current_model)
      next
    end

    result = try_model_with_retries(
      context: context, model: current_model, config: config,
      total_deadline: total_deadline, started_at: started_at,
      breaker: breaker, tracker: tracker
    )

    if result
      # Store attempts in context for instrumentation to persist
      context[:reliability_attempts] = tracker.to_json_array
      return result
    end

    last_error = context.error
  end

  # Store attempts even on total failure
  context[:reliability_attempts] = tracker.to_json_array

  raise Agents::Reliability::AllModelsExhaustedError.new(models_to_try, last_error)
end
```

In `try_model_with_retries`, track each attempt:

```ruby
def try_model_with_retries(context:, model:, config:, total_deadline:, started_at:, breaker:, tracker:)
  # ... existing setup ...
  loop do
    check_total_timeout!(total_deadline, started_at)
    context.attempt = attempt_index + 1
    context.attempts_made += 1

    attempt = tracker.start_attempt(model)

    begin
      original_model = context.model
      context.model = model
      @app.call(context)

      breaker&.record_success!
      tracker.complete_attempt(attempt, success: true, response: context.output)
      return context

    rescue StandardError => e
      context.error = e
      breaker&.record_failure!
      tracker.complete_attempt(attempt, success: false, error: e)

      raise if non_fallback_error?(e, config)

      if should_retry?(e, config, attempt_index, max_retries, total_deadline)
        attempt_index += 1
        delay = calculate_backoff(retries_config, attempt_index)
        async_aware_sleep(delay)
      else
        return nil
      end
    ensure
      context.model = original_model if context.error
    end
  end
end
```

### Step 2: Persist attempts in instrumentation middleware

**File:** `lib/ruby_llm/agents/pipeline/middleware/instrumentation.rb`

In `build_completion_data`, add:

```ruby
# Add reliability attempts if present
if context[:reliability_attempts].present?
  data[:attempts] = context[:reliability_attempts]
  data[:attempts_count] = context[:reliability_attempts].size
end
```

Also in `build_execution_data` (legacy fallback path), add the same block.

### Step 3: Enhance AllModelsExhaustedError (optional)

**File:** `lib/ruby_llm/agents/infrastructure/reliability.rb`

Add `attempts` data to the error so callers can inspect per-model failures without the database:

```ruby
class AllModelsExhaustedError < Error
  attr_reader :models_tried, :last_error, :attempts

  def initialize(models_tried, last_error, attempts: nil)
    @models_tried = models_tried
    @last_error = last_error
    @attempts = attempts
    super("All models exhausted: #{models_tried.join(', ')}. Last error: #{last_error.message}")
  end
end
```

Update the raise site in reliability middleware to pass attempts:

```ruby
raise Agents::Reliability::AllModelsExhaustedError.new(
  models_to_try, last_error,
  attempts: tracker.to_json_array
)
```

### Step 4: Tests

**`spec/lib/pipeline/middleware/reliability_spec.rb`**:
- When primary fails and fallback succeeds, `context[:reliability_attempts]` contains 2 entries (1 failed, 1 success)
- When all models fail, `AllModelsExhaustedError.attempts` contains per-model error details
- Circuit breaker short-circuits are recorded with `short_circuited: true`
- Each attempt entry has `model_id`, `error_class`, `error_message`

**`spec/lib/pipeline/middleware/instrumentation_spec.rb`**:
- When `context[:reliability_attempts]` is present, `build_completion_data` includes `attempts` and `attempts_count`

## Files Modified

| File | Change |
|---|---|
| `lib/ruby_llm/agents/pipeline/middleware/reliability.rb` | Create AttemptTracker, populate during model iteration, store in context |
| `lib/ruby_llm/agents/pipeline/middleware/instrumentation.rb` | Persist `context[:reliability_attempts]` to execution record |
| `lib/ruby_llm/agents/infrastructure/reliability.rb` | Add `attempts` attr to `AllModelsExhaustedError` |
| `spec/lib/pipeline/middleware/reliability_spec.rb` | Tests for attempt tracking in context |
| `spec/lib/pipeline/middleware/instrumentation_spec.rb` | Tests for attempts persistence |

## Dashboard Result

After this change, each execution record will contain:

```json
{
  "attempts": [
    {
      "model_id": "gemini-2.5-flash",
      "started_at": "2025-01-28T10:00:00Z",
      "completed_at": "2025-01-28T10:00:01Z",
      "duration_ms": 1200,
      "error_class": "StandardError",
      "error_message": "You exceeded your current quota...",
      "short_circuited": false
    },
    {
      "model_id": "gpt-4.1-mini",
      "started_at": "2025-01-28T10:00:01Z",
      "completed_at": "2025-01-28T10:00:02Z",
      "duration_ms": 800,
      "error_class": null,
      "error_message": null,
      "input_tokens": 150,
      "output_tokens": 200,
      "short_circuited": false
    }
  ]
}
```

The existing `Execution` model methods (`failed_attempts`, `successful_attempt`, `chosen_model_id`, `used_fallback?`) will work out of the box since the data format matches what they expect.
