# Your First Agent

A step-by-step tutorial for building your first AI agent with RubyLLM::Agents.

## What We'll Build

We'll create a **SearchIntentAgent** that extracts search intent from natural language queries. Given "red summer dress under $50", it will output structured data like:

```ruby
{
  refined_query: "red summer dress",
  filters: ["color:red", "season:summer", "price:<50"],
  category_id: 42
}
```

## Step 1: Generate the Agent

```bash
rails generate ruby_llm_agents:agent SearchIntent query:required limit:10
```

This creates `app/agents/search_intent_agent.rb`:

```ruby
class SearchIntentAgent < ApplicationAgent
  model "gemini-2.0-flash"
  temperature 0.0
  version "1.0"

  param :query, required: true
  param :limit, default: 10

  private

  def system_prompt
    <<~PROMPT
      You are a SearchIntentAgent.
    PROMPT
  end

  def user_prompt
    query
  end
end
```

## Step 2: Define the System Prompt

The system prompt sets the agent's behavior:

```ruby
def system_prompt
  <<~PROMPT
    You are a search assistant that parses user queries and extracts
    structured search filters. Analyze natural language and identify:

    1. The core search query (cleaned and refined)
    2. Any filters (color, size, price range, category, etc.)
    3. The most likely product category

    Be precise and extract only what's explicitly or strongly implied
    in the query.
  PROMPT
end
```

## Step 3: Define the User Prompt

The user prompt is what you send with each request:

```ruby
def user_prompt
  <<~PROMPT
    Extract search intent from this query:

    "#{query}"

    Return up to #{limit} relevant filters.
  PROMPT
end
```

## Step 4: Add a Schema for Structured Output

Schemas ensure the LLM returns valid, typed data:

```ruby
def schema
  @schema ||= RubyLLM::Schema.create do
    string :refined_query,
           description: "The cleaned and refined search query"

    array :filters,
          of: :string,
          description: "Extracted filters in format 'type:value'"

    integer :category_id,
            description: "Detected product category ID",
            nullable: true

    number :confidence,
           description: "Confidence score from 0 to 1"
  end
end
```

## Step 5: Complete Agent

Here's the complete agent:

```ruby
class SearchIntentAgent < ApplicationAgent
  model "gpt-4o"
  temperature 0.0
  version "1.0"
  cache 30.minutes

  param :query, required: true
  param :limit, default: 10

  private

  def system_prompt
    <<~PROMPT
      You are a search assistant that parses user queries and extracts
      structured search filters. Analyze natural language and identify:

      1. The core search query (cleaned and refined)
      2. Any filters (color, size, price range, category, etc.)
      3. The most likely product category

      Be precise and extract only what's explicitly or strongly implied.
    PROMPT
  end

  def user_prompt
    <<~PROMPT
      Extract search intent from: "#{query}"
      Return up to #{limit} filters.
    PROMPT
  end

  def schema
    @schema ||= RubyLLM::Schema.create do
      string :refined_query, description: "Cleaned search query"
      array :filters, of: :string, description: "Filters as 'type:value'"
      integer :category_id, description: "Category ID", nullable: true
      number :confidence, description: "Confidence 0-1"
    end
  end
end
```

## Step 6: Call the Agent

```ruby
# Basic call
result = SearchIntentAgent.call(query: "red summer dress under $50")

# Access structured response
result.content
# => {
#   refined_query: "red summer dress",
#   filters: ["color:red", "season:summer", "price:<50"],
#   category_id: 42,
#   confidence: 0.95
# }

# Access individual fields
result[:refined_query]  # => "red summer dress"
result[:filters]        # => ["color:red", "season:summer", "price:<50"]
```

## Step 7: Access Execution Metadata

Every call includes rich metadata:

```ruby
result = SearchIntentAgent.call(query: "blue jeans")

# Token usage
result.input_tokens   # => 85
result.output_tokens  # => 42
result.total_tokens   # => 127

# Costs
result.input_cost     # => 0.000085
result.output_cost    # => 0.000084
result.total_cost     # => 0.000169

# Timing
result.duration_ms    # => 650
result.started_at     # => 2024-01-15 10:30:00 UTC
result.completed_at   # => 2024-01-15 10:30:00 UTC

# Model info
result.model_id       # => "gpt-4o"
result.finish_reason  # => "stop"
```

## Step 8: Debug Mode

Test without making API calls:

```ruby
result = SearchIntentAgent.call(query: "test", dry_run: true)

# => {
#   dry_run: true,
#   agent: "SearchIntentAgent",
#   model: "gpt-4o",
#   temperature: 0.0,
#   system_prompt: "You are a search assistant...",
#   user_prompt: "Extract search intent from: \"test\"...",
#   schema: "RubyLLM::Schema"
# }
```

## Step 9: View in Dashboard

Visit `/agents` to see:

1. **Overview** - Today's stats and trends
2. **Executions** - All SearchIntentAgent calls
3. **Details** - Click any execution for full details

## Using in a Controller

```ruby
class SearchController < ApplicationController
  def search
    result = SearchIntentAgent.call(query: params[:q])

    @products = Product.where(category_id: result[:category_id])
                       .search(result[:refined_query])
                       .limit(20)
  end
end
```

## Adding Error Handling

```ruby
class SearchController < ApplicationController
  def search
    result = SearchIntentAgent.call(query: params[:q])

    if result.success?
      @products = Product.search(result[:refined_query])
    else
      @products = Product.search(params[:q])  # Fallback to raw query
      Rails.logger.error("Agent failed: #{result.error}")
    end
  end
end
```

## Next Steps

- **[Agent DSL](Agent-DSL)** - All configuration options
- **[Prompts and Schemas](Prompts-and-Schemas)** - Advanced prompt techniques
- **[Reliability](Reliability)** - Add retries and fallbacks
- **[Caching](Caching)** - Cache expensive calls
- **[Examples](Examples)** - More real-world patterns
