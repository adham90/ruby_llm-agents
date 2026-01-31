# Plan: Non-Fallback Errors + Smart Retry Strategy

## Goal

1. **Programming errors** → Fail immediately. No retry, no fallback.
2. **Transient/provider errors WITH fallback models** → Don't retry the failed model, move to next fallback immediately.
3. **Transient/provider errors WITHOUT fallback models** → Retry the same model (current retry behavior).

## Current vs Desired Behavior

### With fallback models configured

| Error Type | Example | Current | Desired |
|---|---|---|---|
| Transient | rate limit, quota, 503 | Retry same model → then fallback | **Skip retry, fallback immediately** |
| Provider | API key invalid, model not found | Fallback (no retry) | Fallback (no change) |
| Programming | ArgumentError, TypeError | Fallback (no retry) | **Fail immediately, no fallback** |

### Without fallback models configured

| Error Type | Example | Current | Desired |
|---|---|---|---|
| Transient | rate limit, quota, 503 | Retry same model | Retry same model (no change) |
| Provider | API key invalid | Fail (no retry) | Fail (no change) |
| Programming | ArgumentError, TypeError | Fail (no retry) | **Fail immediately** |

## Implementation (TDD)

### Step 1: Write failing tests

**`spec/lib/reliability_spec.rb`** — Add `describe ".non_fallback_error?"`:
- Returns `true` for: `ArgumentError`, `TypeError`, `NameError`, `NoMethodError`, `NotImplementedError`
- Returns `false` for: `StandardError`, `RuntimeError`, `Timeout::Error`, `IOError`
- Supports `custom_errors:` parameter

**`spec/lib/pipeline/middleware/reliability_spec.rb`**:

Add `context "non-fallback errors"`:
- `ArgumentError` re-raises immediately — no fallback, no retry, only 1 call to app
- Circuit breaker still records failure before re-raise

Add `context "retry skipping with fallback models"`:
- When fallback models exist and transient error occurs on primary → no retry on primary, moves to fallback immediately (app called once per model, not 1 + retries for primary)
- When NO fallback models exist and transient error occurs → retries on same model up to max retries

Add `context "retry skipping without fallback models"`:
- Transient error retries the same model (existing behavior, unchanged)

**`spec/lib/dsl/reliability_spec.rb`** — Add `describe "#non_fallback_errors"`:
- Returns `nil` when not set
- Sets custom non-fallback error classes
- Appears in `reliability_config` hash
- Works in block-style builder

### Step 2: Implement `non_fallback_error?`

**`lib/ruby_llm/agents/infrastructure/reliability.rb`** — Add to `class << self`:
```ruby
def default_non_fallback_errors
  @default_non_fallback_errors ||= [
    ArgumentError, TypeError, NameError,
    NoMethodError, NotImplementedError
  ]
end

def non_fallback_error?(error, custom_errors: [])
  all = default_non_fallback_errors + Array(custom_errors)
  all.any? { |klass| error.is_a?(klass) }
end
```

### Step 3: Modify middleware rescue block

**`lib/ruby_llm/agents/pipeline/middleware/reliability.rb`**

In `try_model_with_retries`, modify the rescue block (currently lines 161-177):

```ruby
rescue StandardError => e
  context.error = e
  breaker&.record_failure!

  # Programming errors fail immediately — no retry, no fallback
  raise if non_fallback_error?(e, config)

  # Check if we should retry (only when no fallback models available)
  if should_retry?(e, config, attempt_index, max_retries, total_deadline)
    attempt_index += 1
    delay = calculate_backoff(retries_config, attempt_index)
    async_aware_sleep(delay)
  else
    # Move to next model (or exhaust if no fallbacks)
    return nil
  end
```

Modify `should_retry?` method (currently lines 202-207) to skip retries when fallbacks exist:

```ruby
def should_retry?(error, config, attempt_index, max_retries, total_deadline)
  return false if attempt_index >= max_retries
  return false if total_deadline && Time.current > total_deadline
  # Don't retry if fallback models are available — move to next model instead
  return false if has_fallback_models?(config)
  retryable_error?(error, config)
end
```

Add private methods:

```ruby
def non_fallback_error?(error, config)
  custom_errors = config[:non_fallback_errors] || []
  Agents::Reliability.non_fallback_error?(error, custom_errors: custom_errors)
end

def has_fallback_models?(config)
  fallbacks = config[:fallback_models]
  fallbacks.is_a?(Array) && fallbacks.any?
end
```

### Step 4: Add DSL support

**`lib/ruby_llm/agents/dsl/reliability.rb`**:
- Add `non_fallback_errors(*error_classes)` method to `Reliability` module
- Add `inherited_non_fallback_errors` private method
- Add to `reliability_config` hash: `non_fallback_errors: non_fallback_errors`
- Add to `ReliabilityBuilder`: `non_fallback_errors` method, `@non_fallback_errors_list` attr
- Wire builder into `reliability` method

### Step 5: Run all tests and verify

```bash
bundle exec rspec spec/lib/reliability_spec.rb \
  spec/lib/pipeline/middleware/reliability_spec.rb \
  spec/lib/dsl/reliability_spec.rb

# Then full suite
bundle exec rspec spec/lib
```

## Files Modified

| File | Change |
|---|---|
| `lib/ruby_llm/agents/infrastructure/reliability.rb` | Add `non_fallback_error?`, `default_non_fallback_errors` |
| `lib/ruby_llm/agents/pipeline/middleware/reliability.rb` | Add `raise if non_fallback_error?` in rescue, modify `should_retry?` to skip retries when fallbacks exist, add `has_fallback_models?` helper |
| `lib/ruby_llm/agents/dsl/reliability.rb` | Add DSL method, builder support, inheritance |
| `spec/lib/reliability_spec.rb` | Tests for `non_fallback_error?` |
| `spec/lib/pipeline/middleware/reliability_spec.rb` | Tests for immediate failure, retry skipping with/without fallbacks |
| `spec/lib/dsl/reliability_spec.rb` | Tests for DSL |

## Key Design Decisions

1. **Retry only makes sense without fallbacks** — If you have backup models, switching is faster than retrying a failing model.
2. **Programming errors bypass everything** — They indicate bugs, not transient issues. Trying another model won't fix `ArgumentError`.
3. **Circuit breaker still records failures** — Even for non-fallback errors, to track systemic issues.
4. **No config changes needed** — `default_non_fallback_errors` is hardcoded in the infrastructure module. Users can extend via DSL `non_fallback_errors` per agent.

## Usage Example

```ruby
class MyAgent < ApplicationAgent
  model 'gemini-2.5-flash'

  reliability do
    retries max: 3                                    # Only used when NO fallbacks
    fallback_models 'gpt-4.1-mini', 'claude-haiku-4-5'
    non_fallback_errors MyCustomValidationError       # Optional: extend defaults
  end
end
```

**Scenario A** — Gemini quota exceeded:
→ Skips retry (fallbacks exist) → Tries gpt-4.1-mini → Success

**Scenario B** — ArgumentError in prompt building:
→ Fails immediately with ArgumentError (no fallback, no retry)

**Scenario C** — No fallbacks configured, Gemini quota exceeded:
→ Retries up to 3 times with backoff → Fails if still down
