# Content Moderation

Content moderation allows agents to automatically check user input and/or LLM output against safety policies before processing. This uses RubyLLM's moderation API (powered by OpenAI) to detect harmful content including hate speech, violence, harassment, and more.

## Why Content Moderation?

- **Safety** - Prevent harmful content from being processed or generated
- **Compliance** - Meet content policy requirements for user-facing applications
- **Cost Efficiency** - Reject problematic inputs before expensive LLM calls
- **Auditability** - Track moderation decisions for compliance reporting

## Moderation Categories

OpenAI's moderation endpoint checks for these categories:

| Category | Description |
|----------|-------------|
| `hate` | Content promoting hatred based on protected characteristics |
| `hate/threatening` | Hateful content with threats of violence |
| `harassment` | Content harassing individuals or groups |
| `harassment/threatening` | Harassment with threats |
| `self-harm` | Content promoting self-harm |
| `self-harm/intent` | Expression of intent to self-harm |
| `self-harm/instructions` | Instructions for self-harm |
| `sexual` | Sexual content |
| `sexual/minors` | Sexual content involving minors |
| `violence` | Content depicting violence |
| `violence/graphic` | Graphic violence |

## Basic Usage

### Input Moderation

Check user input before making the LLM call:

```ruby
module LLM
  class SafeAgent < ApplicationAgent
    model "gpt-4o"
    moderation :input

    param :message, required: true

    def user_prompt
      message
    end
  end
end

# Safe content proceeds normally
result = LLM::SafeAgent.call(message: "Hello!")
result.content  # => "Hi there! How can I help?"

# Flagged content is blocked before LLM call
result = LLM::SafeAgent.call(message: "harmful content")
result.moderation_flagged?  # => true
result.moderation_phase     # => :input
result.content              # => nil
result.status               # => :input_moderation_blocked
```

### Output Moderation

Check LLM output before returning to the user:

```ruby
module LLM
  class ContentGenerator < ApplicationAgent
    model "gpt-4o"
    moderation :output

    param :topic, required: true

    def user_prompt
      "Write a story about #{topic}"
    end
  end
end

result = LLM::ContentGenerator.call(topic: "adventure")
result.moderation_flagged?  # => false if output is clean

# If output contains flagged content
result.status  # => :output_moderation_blocked
```

### Both Input and Output

```ruby
module LLM
  class FullyModeratedAgent < ApplicationAgent
    model "gpt-4o"
    moderation :both  # or: moderation :input, :output

    param :message, required: true

    def user_prompt
      message
    end
  end
end
```

## Configuration Options

### Threshold

Set a score threshold (0.0-1.0) - content is only flagged if the max score meets or exceeds the threshold:

```ruby
module LLM
  class ThresholdAgent < ApplicationAgent
    moderation :input, threshold: 0.8  # Only flag high-confidence matches
  end
end
```

### Categories

Only flag specific categories:

```ruby
module LLM
  class CategoryFilteredAgent < ApplicationAgent
    moderation :input, categories: [:hate, :violence, :harassment]
    # Sexual content won't trigger moderation
  end
end
```

### Model

Specify the moderation model:

```ruby
module LLM
  class CustomModelAgent < ApplicationAgent
    moderation :input, model: "omni-moderation-latest"
  end
end
```

### On Flagged Action

Configure what happens when content is flagged:

```ruby
module LLM
  class ConfiguredAgent < ApplicationAgent
    # :block - Return early with moderation result (default)
    moderation :input, on_flagged: :block

    # :raise - Raise ModerationError exception
    moderation :input, on_flagged: :raise

    # :warn - Log warning but continue
    moderation :input, on_flagged: :warn

    # :log - Log info but continue
    moderation :input, on_flagged: :log
  end
end
```

### Custom Handler

Implement custom moderation logic:

```ruby
module LLM
  class CustomHandlerAgent < ApplicationAgent
    moderation :input, custom_handler: :review_moderation

    param :message, required: true

    def user_prompt
      message
    end

    private

    def review_moderation(result, phase)
      # Log for review
      Rails.logger.warn("Content flagged: #{result.flagged_categories}")

      # Return :continue to proceed anyway, :block to stop
      max_score = result.category_scores.values.max
      max_score > 0.9 ? :block : :continue
    end
  end
end
```

## Block-Based DSL

For complex configurations, use the block syntax:

```ruby
module LLM
  class AdvancedModerationAgent < ApplicationAgent
    model "gpt-4o"

    moderation do
      input enabled: true, threshold: 0.7
      output enabled: true, threshold: 0.9
      model "omni-moderation-latest"
      categories :hate, :violence, :harassment
      on_flagged :block
    end

    param :message, required: true

    def user_prompt
      message
    end
  end
end
```

## Runtime Override

Override moderation settings at call time:

```ruby
# Disable moderation for specific call
result = LLM::SafeAgent.call(message: "test", moderation: false)

# Override threshold
result = LLM::SafeAgent.call(
  message: "content",
  moderation: { threshold: 0.95 }
)

# Override action
result = LLM::SafeAgent.call(
  message: "content",
  moderation: { on_flagged: :warn }
)
```

## Result Object

The Result object includes moderation-related accessors:

```ruby
result = LLM::ModeratedAgent.call(message: "test")

# Status
result.status               # :success, :input_moderation_blocked, or :output_moderation_blocked
result.moderation_flagged?  # Boolean - was content flagged?
result.moderation_passed?   # Boolean - opposite of flagged?
result.moderation_phase     # :input or :output (if blocked)

# Moderation details
result.moderation_result     # Raw moderation result from RubyLLM
result.moderation_categories # Array of flagged categories
result.moderation_scores     # Hash of category => score
```

## ModerationError

When using `on_flagged: :raise`, catch the exception:

```ruby
begin
  result = LLM::StrictAgent.call(message: user_input)
rescue RubyLLM::Agents::ModerationError => e
  puts "Content blocked: #{e.flagged_categories.join(', ')}"
  puts "Phase: #{e.phase}"
  puts "Scores: #{e.category_scores}"
end
```

## Standalone Moderator

For moderation without an agent (background jobs, API endpoints, etc.):

```ruby
# Define a moderator class
class ContentModerator < RubyLLM::Agents::Moderator
  model "omni-moderation-latest"
  threshold 0.7
  categories :hate, :violence, :harassment
end

# Use it
result = ContentModerator.call(text: "content to check")
result.flagged?           # => true/false
result.passed?            # => opposite of flagged?
result.flagged_categories # => [:hate] (filtered by config)
result.category_scores    # => { hate: 0.9, violence: 0.1, ... }
result.max_score          # => 0.9
```

### In a Background Job

```ruby
class ModeratePendingContentJob < ApplicationJob
  def perform(content_id)
    content = UserContent.find(content_id)
    result = ContentModerator.call(text: content.body)

    if result.flagged?
      content.update!(
        status: :flagged,
        moderation_categories: result.flagged_categories
      )
    else
      content.update!(status: :approved)
    end
  end
end
```

### In a Controller

```ruby
class PostsController < ApplicationController
  def create
    result = ContentModerator.call(text: params[:content])

    if result.flagged?
      render json: { error: "Content rejected" }, status: :unprocessable_entity
    else
      @post = Post.create!(content: params[:content])
      render json: @post
    end
  end
end
```

## Global Configuration

Set defaults for all agents:

```ruby
# config/initializers/ruby_llm_agents.rb
RubyLLM::Agents.configure do |config|
  config.default_moderation_model = "omni-moderation-latest"
  config.default_moderation_threshold = nil  # No threshold by default
  config.default_moderation_action = :block
  config.track_moderation = true  # Log moderation to executions table
end
```

## Multi-Tenancy

Moderation respects multi-tenancy - uses tenant's API keys if configured:

```ruby
result = LLM::ModeratedAgent.call(
  message: user_input,
  tenant: current_organization  # Uses tenant's OpenAI key
)
```

## Execution Tracking

When `track_moderation` is enabled, moderation calls are logged to the executions table:

```ruby
# Query moderation executions
RubyLLM::Agents::Execution
  .where(execution_type: "moderation")
  .where("metadata->>'flagged' = ?", "true")
  .recent(10)
```

## Cost Considerations

OpenAI's moderation API is very inexpensive:
- Moderation calls are significantly cheaper than chat completions
- No token limits for moderation (full content can be checked)
- Consider always moderating user input for public-facing applications

## Best Practices

1. **Always moderate user input** - For public-facing applications, moderate all user content
2. **Use appropriate thresholds** - Lower thresholds catch more content but may have false positives
3. **Filter relevant categories** - Only check categories relevant to your use case
4. **Handle blocked content gracefully** - Provide helpful error messages to users
5. **Log moderation events** - Enable tracking for compliance and debugging
6. **Use custom handlers for nuance** - Implement business-specific moderation logic
7. **Test with various inputs** - Verify moderation works as expected

## Example Agent

See the complete example:

```ruby
# app/llm/agents/moderated_agent.rb
module LLM
  class ModeratedAgent < ApplicationAgent
    description "Demonstrates content moderation support"
    version "1.0"

    model "gpt-4o"
    temperature 0.7

    moderation :input,
      threshold: 0.7,
      categories: [:hate, :violence, :harassment]

    param :message, required: true

    def system_prompt
      "You are a helpful and friendly assistant."
    end

    def user_prompt
      message
    end
  end
end
```

## Providers

Currently, moderation is supported via OpenAI's moderation endpoint. Ensure you have an OpenAI API key configured even if using other providers for chat.
