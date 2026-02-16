# Prompts and Schemas

Learn how to craft effective prompts and structure LLM outputs with schemas.

## Prompts Overview

RubyLLM::Agents uses a three-role DSL for building conversations:

| Role | DSL | Purpose | When Sent |
|------|-----|---------|-----------|
| System | `system` | Sets the agent's role and behavior | First message in conversation |
| User | `user` | The specific request to process | Each call |
| Assistant | `assistant` | Pre-fill / steer the response | After user message, before generation |
| _(context)_ | `messages` | Conversation history for context | Before user message |

> **Note:** In versions prior to v2.2.0, the `prompt` DSL was used instead of `user`. The `prompt` method still works as a deprecated alias but will emit a warning. All new code should use `user`.

For multi-turn conversations, see [Conversation History](Conversation-History).

## System Prompts

### Basic System Prompt

```ruby
system "You are a helpful assistant."
```

### Detailed System Prompt

```ruby
system do
  <<~S
    You are a professional content analyst specializing in e-commerce.

    Your responsibilities:
    - Analyze product descriptions for quality
    - Identify missing information
    - Suggest improvements
    - Rate content on a scale of 1-10

    Guidelines:
    - Be specific and actionable
    - Focus on SEO best practices
    - Consider mobile readability
    - Maintain brand voice consistency
  S
end
```

### Dynamic System Prompts

Use the block form when you need conditionals or method calls:

```ruby
system do
  <<~S
    You are an assistant for #{company_name}.

    Current context:
    - User role: #{user_role}
    - Department: #{department}
    - Language: #{locale}

    #{additional_instructions if admin_mode}
  S
end
```

## User Prompts

### Simple User Prompt

Use `{placeholder}` syntax to auto-register params:

```ruby
user "{query}"
```

### Structured User Prompt

```ruby
user do
  <<~S
    ## Task
    Analyze the following product description.

    ## Input
    {product_description}

    ## Requirements
    - Identify at least 3 strengths
    - Identify at least 3 areas for improvement
    - Provide an overall quality score
  S
end
```

### User Prompt with Examples

```ruby
user do
  <<~S
    Classify the following customer message.

    ## Examples

    Message: "When will my order arrive?"
    Classification: shipping_inquiry

    Message: "I want to return this item"
    Classification: return_request

    Message: "The product is broken"
    Classification: complaint

    ## Your Task

    Message: "{customer_message}"
    Classification:
  S
end
```

## Assistant Prefill (v2.2+)

The `assistant` DSL pre-fills the assistant turn so the LLM continues from that text instead of generating from scratch. This is the third role in the three-role DSL.

### Forcing JSON Output

The most common use case is forcing the model to begin its response with `{`, which reliably produces valid JSON:

```ruby
class EntityExtractor < ApplicationAgent
  model "claude-sonnet-4-20250514"

  system "You extract named entities from text and return them as JSON."
  user   "{text}"
  assistant "{"

  returns do
    array :people, of: :string
    array :organizations, of: :string
    array :locations, of: :string
  end
end
```

### Steering Response Format

You can use longer prefills to steer the structure of the response:

```ruby
class StepByStepSolver < ApplicationAgent
  model "gpt-4o"

  system "You are a math tutor."
  user   "Solve: {problem}"
  assistant "Let me solve this step by step.\n\nStep 1:"
end
```

### Dynamic Assistant Prefill

Use the block form when the prefill depends on runtime data:

```ruby
class TranslationAgent < ApplicationAgent
  model "gpt-4o"

  system "You are a translator."
  user   "Translate to {language}: {text}"
  assistant { "#{language.capitalize} translation:" }
end
```

## The `.ask` Shorthand (v2.2+)

`.ask` is a one-shot convenience method for sending a user message without pre-defining a `user` prompt on the class. It is ideal for ad-hoc queries, REPL exploration, and scripts.

### Basic Usage

```ruby
result = MyAgent.ask("Summarize this article: #{text}")
result.content
```

### With Parameters

```ruby
result = MyAgent.ask("Translate {text} to {language}", text: article, language: "French")
```

### Block Form

```ruby
result = MyAgent.ask { "The time is #{Time.current}. What day is it?" }
```

### When to Use `.ask` vs `.call`

| Method | Best for |
|--------|----------|
| `.call` | Production agents with a `user` prompt defined on the class |
| `.ask`  | Ad-hoc queries, scripts, REPL sessions, one-off tasks |

```ruby
# .call -- the user prompt is defined on the class
class SummaryAgent < ApplicationAgent
  model "gpt-4o"
  user "Summarize: {text}"
end
SummaryAgent.call(text: article)

# .ask -- no user prompt needed on the class
SummaryAgent.ask("What is the capital of France?")
```

## Schemas

Schemas ensure LLMs return structured, typed data.

### Basic Schema

```ruby
def schema
  @schema ||= RubyLLM::Schema.create do
    string :result, description: "The analysis result"
  end
end
```

### Schema Field Types

```ruby
def schema
  @schema ||= RubyLLM::Schema.create do
    # String
    string :name, description: "User's name"

    # Number (float)
    number :score, description: "Score from 0 to 1"

    # Integer
    integer :count, description: "Number of items"

    # Boolean
    boolean :is_valid, description: "Whether input is valid"

    # Array
    array :tags, of: :string, description: "List of tags"

    # Enum (restricted values)
    string :status,
           enum: ["pending", "approved", "rejected"],
           description: "Current status"
  end
end
```

### Nullable Fields

```ruby
def schema
  @schema ||= RubyLLM::Schema.create do
    string :category, description: "Primary category"
    string :subcategory, description: "Subcategory", nullable: true
    integer :priority, description: "Priority level", nullable: true
  end
end
```

### Nested Objects

```ruby
def schema
  @schema ||= RubyLLM::Schema.create do
    string :summary, description: "Brief summary"

    object :metadata do
      string :author
      string :created_at
      integer :word_count
    end

    array :sections, of: :object do
      string :title
      string :content
      integer :order
    end
  end
end
```

### Complex Schema Example

```ruby
def schema
  @schema ||= RubyLLM::Schema.create do
    string :refined_query,
           description: "Cleaned and normalized search query"

    array :filters, of: :object do
      string :field, description: "Field name to filter"
      string :operator,
             enum: ["eq", "neq", "gt", "lt", "contains"],
             description: "Filter operator"
      string :value, description: "Filter value"
    end

    object :sorting do
      string :field, description: "Field to sort by"
      string :direction,
             enum: ["asc", "desc"],
             description: "Sort direction"
    end

    integer :category_id,
            description: "Detected category ID",
            nullable: true

    number :confidence,
           description: "Confidence score from 0 to 1"

    array :suggestions,
          of: :string,
          description: "Alternative search suggestions"
  end
end
```

## Response Processing

### Basic Processing

The schema automatically parses the response:

```ruby
result = MyAgent.call(query: "test")
result.content  # Already parsed and typed
```

### Custom Post-Processing

Override `process_response` for additional processing:

```ruby
def process_response(response)
  result = super(response)

  # Transform data
  result[:tags] = result[:tags].map(&:downcase).uniq

  # Add computed fields
  result[:word_count] = result[:summary].split.size
  result[:processed_at] = Time.current

  # Validate
  result[:score] = result[:score].clamp(0, 1)

  result
end
```

### Error Handling in Processing

```ruby
def process_response(response)
  result = super(response)

  # Handle missing fields gracefully
  result[:category] ||= "uncategorized"
  result[:tags] ||= []

  # Type coercion
  result[:count] = result[:count].to_i

  result
rescue => e
  Rails.logger.error("Response processing failed: #{e}")
  { error: "Processing failed", raw: response }
end
```

## Prompt Engineering Tips

### Be Specific

```ruby
# Less effective
user "Summarize this: {text}"

# More effective
user do
  <<~S
    Create a 2-3 sentence summary of the following text.
    Focus on the main argument and key supporting points.
    Use simple language suitable for a general audience.

    Text:
    {text}
  S
end
```

### Provide Context

```ruby
system do
  <<~S
    You are a customer service assistant for TechStore, an electronics retailer.

    Key information:
    - Return policy: 30 days for unopened items
    - Shipping: Free over $50, otherwise $5.99
    - Support hours: 9 AM - 9 PM EST

    Always be helpful, professional, and accurate.
  S
end
```

### Use Structured Formats

```ruby
user do
  <<~S
    Analyze this product review and extract:

    1. Overall sentiment (positive/negative/neutral)
    2. Key points mentioned
    3. Any issues reported
    4. Purchase recommendation

    Review:
    {review_text}
  S
end
```

### Handle Edge Cases

```ruby
user do
  <<~S
    Parse the following address into components.

    If any component is missing or unclear:
    - Leave it as null
    - Do not guess or infer values
    - Note the issue in the "parsing_notes" field

    Address:
    {raw_address}
  S
end
```

## Related Pages

- [Agent DSL](Agent-DSL) - Full DSL reference
- [Parameters](Parameters) - Input parameters
- [Conversation History](Conversation-History) - Multi-turn conversations
- [Result Object](Result-Object) - Working with responses
- [Examples](Examples) - Real-world patterns
