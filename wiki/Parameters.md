# Parameters

Parameters define the inputs your agent accepts. They provide validation, defaults, and accessor methods.

## Defining Parameters

### Required Parameters

Parameters that must be provided:

```ruby
class MyAgent < ApplicationAgent
  param :query, required: true
  param :user_id, required: true
end

# This raises ArgumentError
MyAgent.call(query: "test")
# => ArgumentError: SearchAgent missing required params: [:user_id]
```

### Optional Parameters with Defaults

Parameters that have fallback values:

```ruby
class MyAgent < ApplicationAgent
  param :limit, default: 10
  param :format, default: "json"
  param :include_metadata, default: false
end

# These are equivalent
MyAgent.call(query: "test")
MyAgent.call(query: "test", limit: 10, format: "json", include_metadata: false)
```

### Optional Parameters without Defaults

Parameters that default to `nil`:

```ruby
class MyAgent < ApplicationAgent
  param :filters      # nil if not provided
  param :context      # nil if not provided
end
```

## Accessing Parameters

Parameters become instance methods:

```ruby
class SearchAgent < ApplicationAgent
  param :query, required: true
  param :limit, default: 10
  param :filters

  def user_prompt
    prompt = "Search: #{query}"
    prompt += " (limit: #{limit})" if limit
    prompt += " with filters: #{filters.join(', ')}" if filters&.any?
    prompt
  end
end
```

## Parameter Types

Parameters can be any Ruby type:

```ruby
class MyAgent < ApplicationAgent
  # Strings
  param :query, required: true

  # Numbers
  param :limit, default: 10
  param :threshold, default: 0.5

  # Booleans
  param :include_metadata, default: false

  # Arrays
  param :tags, default: []

  # Hashes
  param :options, default: {}

  # Complex objects
  param :user  # Pass ActiveRecord models, etc.
end

# Usage
MyAgent.call(
  query: "search term",
  limit: 20,
  threshold: 0.8,
  include_metadata: true,
  tags: ["featured", "new"],
  options: { sort: :relevance },
  user: current_user
)
```

## Using Parameters in Prompts

### Direct Interpolation

```ruby
def user_prompt
  "Find #{query} with limit #{limit}"
end
```

### Conditional Content

```ruby
def user_prompt
  <<~PROMPT
    Search query: #{query}
    #{"Maximum results: #{limit}" if limit}
    #{"Filters: #{filters.join(', ')}" if filters&.any?}
  PROMPT
end
```

### Complex Logic

```ruby
def user_prompt
  parts = ["Search for: #{query}"]

  if advanced_mode
    parts << "Use advanced parsing"
    parts << "Include synonyms: #{include_synonyms}"
  end

  parts << format_constraints if constraints.present?

  parts.join("\n")
end

private

def format_constraints
  constraints.map { |c| "- #{c}" }.join("\n")
end
```

## Parameter Validation

Add custom validation in the agent:

```ruby
class MyAgent < ApplicationAgent
  param :limit, default: 10

  def call
    validate_parameters!
    super
  end

  private

  def validate_parameters!
    raise ArgumentError, "limit must be positive" if limit <= 0
    raise ArgumentError, "limit cannot exceed 100" if limit > 100
  end
end
```

## Parameters in Execution Metadata

Parameters are automatically included in execution logs:

```ruby
execution = RubyLLM::Agents::Execution.last
execution.parameters
# => { "query" => "test", "limit" => 10 }
```

You can filter executions by parameters:

```ruby
RubyLLM::Agents::Execution
  .by_agent("SearchAgent")
  .where("parameters->>'query' LIKE ?", "%dress%")
```

## Parameter Redaction

Sensitive parameters are automatically redacted in logs:

```ruby
class MyAgent < ApplicationAgent
  param :api_key, required: true  # Redacted by default
  param :password, required: true # Redacted by default
  param :secret_token             # Redacted by default
end
```

See [PII Redaction](PII-Redaction) for configuring redaction.

## Parameters in Cache Keys

By default, all parameters are included in cache keys. Customize with `cache_key_data`:

```ruby
class MyAgent < ApplicationAgent
  param :query, required: true
  param :user_id, required: true
  param :request_id  # Don't include in cache key

  cache 1.hour

  def cache_key_data
    # Only these affect caching
    { query: query, user_id: user_id }
  end
end
```

## Passing Parameters at Call Time

### Standard Call

```ruby
MyAgent.call(query: "test", limit: 20)
```

### With Options

```ruby
MyAgent.call(
  query: "test",
  dry_run: true,      # Debug mode
  skip_cache: true    # Bypass cache
)
```

### With Streaming Block

```ruby
MyAgent.call(query: "test") do |chunk|
  print chunk
end
```

### With Attachments

```ruby
MyAgent.call(
  query: "Describe this image",
  with: "photo.jpg"
)
```

## Best Practices

### Use Descriptive Names

```ruby
# Good
param :search_query, required: true
param :max_results, default: 10
param :include_archived, default: false

# Avoid
param :q, required: true
param :n, default: 10
param :ia, default: false
```

### Group Related Parameters

```ruby
class SearchAgent < ApplicationAgent
  # Search parameters
  param :query, required: true
  param :filters

  # Pagination
  param :page, default: 1
  param :per_page, default: 20

  # User context
  param :user_id, required: true
  param :locale, default: "en"
end
```

### Document Complex Parameters

```ruby
class MyAgent < ApplicationAgent
  # Array of filter strings in format "field:operator:value"
  # Example: ["price:lt:100", "category:eq:electronics"]
  param :filters, default: []

  # Hash of sort options
  # Example: { field: "created_at", direction: "desc" }
  param :sort_options
end
```

## Related Pages

- [Agent DSL](Agent-DSL) - Full DSL reference
- [Prompts and Schemas](Prompts-and-Schemas) - Using parameters in prompts
- [PII Redaction](PII-Redaction) - Protecting sensitive parameters
