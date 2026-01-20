# Tools

Tools enable agents to perform actions and retrieve information from external systems. When an agent has tools available, the LLM can decide to call them to gather information or perform operations before providing a final response.

## Defining Tools

Tools inherit from `RubyLLM::Tool` and use a DSL to define their behavior:

```ruby
class SearchTool < RubyLLM::Tool
  description "Search for products by query"

  param :query, desc: "Search query", required: true
  param :limit, desc: "Maximum results to return", default: 10

  def execute(query:, limit: 10)
    Product.search(query).limit(limit).map(&:to_s).join("\n")
  end
end
```

## Tool DSL

### description

Describes what the tool does. This is shown to the LLM to help it decide when to use the tool:

```ruby
class WeatherTool < RubyLLM::Tool
  description "Get current weather for a location. Returns temperature, conditions, and forecast."
end
```

### param

Define parameters the tool accepts:

```ruby
class SearchTool < RubyLLM::Tool
  # Required parameter
  param :query, desc: "Search query text", required: true

  # Optional with default
  param :limit, desc: "Max results", default: 10

  # Optional without default (will be nil)
  param :category, desc: "Category filter"

  # Array type
  param :colors, desc: "Colors to filter by", type: :array

  # Boolean type
  param :in_stock_only, desc: "Only show in-stock items", type: :boolean
end
```

**Parameter Options:**

| Option | Description |
|--------|-------------|
| `:desc` | Description shown to LLM |
| `:required` | Whether parameter is required (default: false) |
| `:default` | Default value if not provided |
| `:type` | Parameter type (`:array`, `:boolean`, etc.) |

### execute

The main method that performs the tool's action:

```ruby
def execute(query:, limit: 10, **filters)
  # Perform the action
  results = search(query, filters)

  # Return a string for the LLM
  format_results(results)
end
```

**Important:** The `execute` method should return a string that the LLM can understand and use.

## Using Tools in Agents

### Static Tools (Class-Level)

Register tools at the class level using the `tools` DSL:

```ruby
module LLM
  class ProductAgent < ApplicationAgent
    tools [SearchTool, GetProductTool, CompareTool]

    param :query, required: true

    def system_prompt
      "You are a helpful shopping assistant."
    end

    def user_prompt
      "Help the user with: #{query}"
    end
  end
end
```

### Dynamic Tools (Instance Method)

For runtime tool selection, override `tools` as an instance method:

```ruby
module LLM
  class SmartAgent < ApplicationAgent
    param :query, required: true
    param :user_role

    def tools
      base_tools = [SearchTool, GetInfoTool]

      # Add admin tools for admin users
      if user_role == "admin"
        base_tools + [DeleteTool, UpdateTool]
      else
        base_tools
      end
    end

    def user_prompt
      query
    end
  end
end
```

## Tool Execution Flow

When an agent with tools is called:

1. **Initial Request** - Agent sends prompt to LLM with tool definitions
2. **Tool Decision** - LLM analyzes the request and may decide to call tools
3. **Tool Execution** - RubyLLM automatically executes requested tools
4. **Result Return** - Tool results are sent back to the LLM
5. **Iteration** - LLM may call more tools or provide final answer
6. **Completion** - Loop ends when LLM provides a final response

```
User Request
     |
     v
+----------+    tool_call    +-----------+
|   LLM    | --------------> |   Tool    |
|          | <-------------- |           |
+----------+    result       +-----------+
     |
     | (may repeat)
     v
Final Response
```

## Accessing Tool Calls

After execution, you can inspect which tools were called:

```ruby
result = LLM::ProductAgent.call(query: "Find red shoes under $100")

result.tool_calls         # Array of tool call records
result.tool_calls_count   # Number of tools called
result.has_tool_calls?    # Boolean - were any tools called?

# Each tool call contains:
result.tool_calls.each do |call|
  puts call["name"]       # Tool name
  puts call["arguments"]  # Arguments passed
end
```

## Complete Example

Here's a full example with a base tool class and multiple tools:

### Base Tool (Optional)

```ruby
# app/tools/base_tool.rb
class BaseTool < RubyLLM::Tool
  private

  def format_error(message)
    "Error: #{message}"
  end

  def format_results(items)
    return "No results found." if items.empty?
    items.map(&:to_s).join("\n\n")
  end
end
```

### Search Tool

```ruby
# app/tools/product/search_tool.rb
class Product::SearchTool < BaseTool
  description "Search products with advanced filtering. Supports text search, price ranges, categories, and more."

  param :query, desc: "Search text (semantic search)", required: false
  param :category, desc: "Product category (tops, bottoms, shoes, accessories)", required: false
  param :price_min, desc: "Minimum price in USD", required: false
  param :price_max, desc: "Maximum price in USD", required: false
  param :colors, desc: "Array of colors to filter by", type: :array
  param :sizes, desc: "Array of sizes to filter by", type: :array
  param :in_stock_only, desc: "Only show in-stock products", type: :boolean
  param :limit, desc: "Maximum results to return", default: 20

  def execute(query: nil, limit: 20, **filters)
    products = Product.all

    # Apply filters
    products = products.search(query) if query.present?
    products = products.where(category: filters[:category]) if filters[:category]
    products = products.where("price >= ?", filters[:price_min]) if filters[:price_min]
    products = products.where("price <= ?", filters[:price_max]) if filters[:price_max]
    products = products.where(color: filters[:colors]) if filters[:colors].present?
    products = products.where(size: filters[:sizes]) if filters[:sizes].present?
    products = products.in_stock if filters[:in_stock_only]

    format_results(products.limit(limit))
  rescue => e
    format_error(e.message)
  end
end
```

### Get Tool

```ruby
# app/tools/product/get_tool.rb
class Product::GetTool < BaseTool
  description "Get detailed information about a specific product by ID"

  param :id, desc: "Product ID", required: true

  def execute(id:)
    product = Product.find(id)
    product.to_detailed_string
  rescue ActiveRecord::RecordNotFound
    format_error("Product not found with ID: #{id}")
  end
end
```

### Agent Using Tools

```ruby
# app/llm/agents/shopping_agent.rb
module LLM
  class ShoppingAgent < ApplicationAgent
    model "gpt-4o"
    tools [Product::SearchTool, Product::GetTool]

    param :query, required: true
    param :user_id

    def system_prompt
      <<~PROMPT
        You are a helpful shopping assistant. Use the available tools to:
        - Search for products matching user requests
        - Get detailed product information
        - Compare products when asked

        Always be helpful and provide specific product recommendations.
      PROMPT
    end

    def user_prompt
      query
    end

    def execution_metadata
      { user_id: user_id }
    end
  end
end
```

### Usage

```ruby
result = LLM::ShoppingAgent.call(
  query: "I'm looking for red sneakers under $150",
  user_id: current_user.id
)

puts result.content
# => "I found 3 great options for red sneakers under $150..."

puts result.tool_calls_count
# => 1 (SearchTool was called)
```

## Best Practices

### 1. Return Readable Strings

Format tool output for LLM comprehension:

```ruby
def execute(id:)
  product = Product.find(id)

  <<~OUTPUT
    Product: #{product.name}
    Price: $#{product.price}
    Category: #{product.category}
    In Stock: #{product.in_stock? ? 'Yes' : 'No'}
    Description: #{product.description}
  OUTPUT
end
```

### 2. Write Clear Descriptions

Help the LLM understand when to use each tool:

```ruby
# Good - specific and actionable
description "Search products by text query, with optional filters for price, category, and availability"

# Bad - vague
description "Search stuff"
```

### 3. Handle Errors Gracefully

Return error messages the LLM can understand:

```ruby
def execute(id:)
  product = Product.find(id)
  format_product(product)
rescue ActiveRecord::RecordNotFound
  "Product with ID #{id} was not found. Please check the ID and try again."
rescue => e
  "Unable to retrieve product: #{e.message}"
end
```

### 4. Keep Tools Focused

One tool should do one thing well:

```ruby
# Good - separate concerns
class SearchTool < RubyLLM::Tool
  description "Search for products"
end

class CreateOrderTool < RubyLLM::Tool
  description "Create a new order"
end

# Bad - too many responsibilities
class ProductTool < RubyLLM::Tool
  description "Search, create, update, delete products and orders"
end
```

### 5. Use Appropriate Types

Specify types for non-string parameters:

```ruby
param :tags, desc: "Filter tags", type: :array
param :active, desc: "Only active items", type: :boolean
param :count, desc: "Number of items", type: :integer
```

## Related Pages

- [Agent DSL](Agent-DSL) - Full agent configuration reference
- [Result Object](Result-Object) - Accessing tool call data
- [Execution Tracking](Execution-Tracking) - Tool calls in execution logs
