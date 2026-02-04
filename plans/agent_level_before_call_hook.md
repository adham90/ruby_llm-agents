# Plan: Add Agent-Level Hooks & Remove Built-in Moderation/Redaction

## Goal
Replace built-in moderation/redaction (~2000 lines) with lightweight `before_call` / `after_call` hooks, giving full control to the user.

## Decisions
- Add `before_call(context)` and `after_call(context, response)` hooks to conversation agents
- Matches existing image pipeline pattern (`before_pipeline` / `after_pipeline`)
- Remove all built-in moderation and PII redaction code
- No deprecation cycle needed (single user)

## What Gets Removed

| Component | Files |
|-----------|-------|
| Redactor | `infrastructure/redactor.rb` |
| Moderation DSL | `core/base/moderation_dsl.rb` |
| Moderation Execution | `core/base/moderation_execution.rb` |
| ModerationResult | `results/moderation_result.rb` |
| Standalone Moderator | `text/moderator.rb` |
| Image ContentPolicy | `image/generator/content_policy.rb` |
| ModerationError | Part of `errors.rb` |
| Configuration options | Redaction/moderation config in `configuration.rb` |
| Wiki docs | `wiki/PII-Redaction.md`, `wiki/Moderation.md` |
| Example agents | Moderation example agents |
| Tests | Related spec files |

## Implementation Plan

### 1. Add hooks to conversation agents

**Location:** `lib/ruby_llm/agents/core/base.rb` or a new `core/base/callbacks.rb` module

**API:**
```ruby
class MyAgent < RubyLLM::Agents::Base
  before_call :my_preprocessing
  after_call :my_postprocessing

  # Or with blocks
  before_call { |context| context.params[:sanitized] = true }
  after_call { |context, response| log_response(response) }

  private

  def my_preprocessing(context)
    # Can mutate context
    # Can raise to block execution
  end

  def my_postprocessing(context, response)
    # Can inspect/log response
    # Return value ignored
  end
end
```

**Behavior:**
- `before_call(context)` - runs once before LLM call (not on retries)
- `after_call(context, response)` - runs after successful LLM call
- Hooks are optional
- Can be method names or blocks
- Multiple hooks allowed (run in order defined)

### 2. Remove moderation/redaction code

Delete files:
- `lib/ruby_llm/agents/infrastructure/redactor.rb`
- `lib/ruby_llm/agents/core/base/moderation_dsl.rb`
- `lib/ruby_llm/agents/core/base/moderation_execution.rb`
- `lib/ruby_llm/agents/results/moderation_result.rb`
- `lib/ruby_llm/agents/text/moderator.rb`
- `lib/ruby_llm/agents/image/generator/content_policy.rb`
- `wiki/PII-Redaction.md`
- `wiki/Moderation.md`
- Related spec files
- Example moderation agents

Remove from files:
- `ModerationError` from `core/errors.rb`
- Moderation/redaction config from `configuration.rb`
- Moderation mixins from `core/base.rb`
- Moderation fields from `results/base.rb`
- Dashboard views for moderation status

### 3. Update tests

- Add specs for `before_call` / `after_call` hooks
- Remove all moderation/redaction specs

### 4. Update CHANGELOG

```markdown
## [Unreleased]

### Added
- `before_call` and `after_call` hooks for conversation agents

### Removed
- Built-in moderation system (use `before_call` hook instead)
- Built-in PII redaction (use `before_call` hook instead)
- `Moderator` class
- `ModerationResult` class
- `ModerationError` exception
- `Redactor` utility
- Image content policy
- Related configuration options
```
