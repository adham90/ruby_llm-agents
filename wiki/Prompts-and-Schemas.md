# Prompts and Schemas

Learn how to craft effective prompts and structure LLM outputs with schemas.

## Prompts Overview

RubyLLM::Agents uses these prompt types:

| Prompt | Purpose | When Sent |
|--------|---------|-----------|
| `system_prompt` | Sets the agent's role and behavior | First message in conversation |
| `messages` | Conversation history for context | Before user_prompt |
| `user_prompt` | The specific request to process | Each call |

For multi-turn conversations, see [Conversation History](Conversation-History).

## System Prompts

### Basic System Prompt

```ruby
def system_prompt
  "You are a helpful assistant."
end
```

### Detailed System Prompt

```ruby
def system_prompt
  <<~PROMPT
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
  PROMPT
end
```

### Dynamic System Prompts

```ruby
def system_prompt
  <<~PROMPT
    You are an assistant for #{company_name}.

    Current context:
    - User role: #{user_role}
    - Department: #{department}
    - Language: #{locale}

    #{additional_instructions if admin_mode}
  PROMPT
end
```

## User Prompts

### Simple User Prompt

```ruby
def user_prompt
  query
end
```

### Structured User Prompt

```ruby
def user_prompt
  <<~PROMPT
    ## Task
    Analyze the following product description.

    ## Input
    #{product_description}

    ## Requirements
    - Identify at least 3 strengths
    - Identify at least 3 areas for improvement
    - Provide an overall quality score
  PROMPT
end
```

### User Prompt with Examples

```ruby
def user_prompt
  <<~PROMPT
    Classify the following customer message.

    ## Examples

    Message: "When will my order arrive?"
    Classification: shipping_inquiry

    Message: "I want to return this item"
    Classification: return_request

    Message: "The product is broken"
    Classification: complaint

    ## Your Task

    Message: "#{customer_message}"
    Classification:
  PROMPT
end
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
result = LLM::MyAgent.call(query: "test")
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
def user_prompt
  "Summarize this: #{text}"
end

# More effective
def user_prompt
  <<~PROMPT
    Create a 2-3 sentence summary of the following text.
    Focus on the main argument and key supporting points.
    Use simple language suitable for a general audience.

    Text:
    #{text}
  PROMPT
end
```

### Provide Context

```ruby
def system_prompt
  <<~PROMPT
    You are a customer service assistant for TechStore, an electronics retailer.

    Key information:
    - Return policy: 30 days for unopened items
    - Shipping: Free over $50, otherwise $5.99
    - Support hours: 9 AM - 9 PM EST

    Always be helpful, professional, and accurate.
  PROMPT
end
```

### Use Structured Formats

```ruby
def user_prompt
  <<~PROMPT
    Analyze this product review and extract:

    1. Overall sentiment (positive/negative/neutral)
    2. Key points mentioned
    3. Any issues reported
    4. Purchase recommendation

    Review:
    #{review_text}
  PROMPT
end
```

### Handle Edge Cases

```ruby
def user_prompt
  <<~PROMPT
    Parse the following address into components.

    If any component is missing or unclear:
    - Leave it as null
    - Do not guess or infer values
    - Note the issue in the "parsing_notes" field

    Address:
    #{raw_address}
  PROMPT
end
```

## Related Pages

- [Agent DSL](Agent-DSL) - Full DSL reference
- [Parameters](Parameters) - Input parameters
- [Conversation History](Conversation-History) - Multi-turn conversations
- [Result Object](Result-Object) - Working with responses
- [Examples](Examples) - Real-world patterns
