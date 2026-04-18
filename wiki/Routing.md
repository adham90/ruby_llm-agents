# Routing

Classify user messages and route them to the right handler using LLM-powered classification.

## Overview

The `Routing` concern adds classification capabilities to any `BaseAgent` subclass. Define routes with descriptions, and the agent automatically generates a classification prompt, sends it to the LLM, and returns a structured `RoutingResult`.

**Key design decisions:**
- **Thin concern, not a base class** — Include `Routing` in any agent, reusing all existing infrastructure
- **Pure classification** — Returns a route symbol, never executes a target agent
- **Zero duplication** — Caching, reliability, retries, instrumentation all come free from BaseAgent

## Quick Start

```ruby
# app/agents/support_router.rb
class SupportRouter < ApplicationAgent
  include RubyLLM::Agents::Routing

  model "gpt-4o-mini"
  temperature 0.0

  route :billing,   "Billing, charges, refunds, payments"
  route :technical,  "Bugs, errors, crashes, technical issues"
  route :sales,      "Pricing, plans, upgrades, discounts"
  default_route :general
end
```

```ruby
result = SupportRouter.call(message: "I was charged twice")
result.route        # => :billing
result.success?     # => true
result.total_cost   # => 0.00008
```

## Route DSL

### Defining Routes

Each route has a name (symbol) and a description that tells the LLM what messages belong to it:

```ruby
class AppRouter < ApplicationAgent
  include RubyLLM::Agents::Routing

  model "gpt-4o-mini"
  temperature 0.0

  route :billing,     "Billing, invoices, charges, refunds, payment methods"
  route :technical,    "Bugs, errors, crashes, performance issues, technical support"
  route :sales,        "Pricing, plans, upgrades, discounts, enterprise inquiries"
  route :account,      "Password resets, profile changes, account settings"
  default_route :general
end
```

### Default Route

The `default_route` is used when the LLM response doesn't match any defined route:

```ruby
default_route :general            # Default fallback
default_route :support            # Custom name
default_route :general, agent: GeneralAgent  # With agent mapping
```

If no `default_route` is set, it defaults to `:general`.

### Route-to-Agent Mapping

Optionally map routes to agent classes for downstream dispatch:

```ruby
class AppRouter < ApplicationAgent
  include RubyLLM::Agents::Routing

  model "gpt-4o-mini"
  temperature 0.0

  route :billing,   "Billing questions",   agent: BillingAgent
  route :technical,  "Technical issues",    agent: TechnicalAgent
  route :sales,      "Sales inquiries",     agent: SalesAgent
  default_route :general, agent: GeneralAgent
end

result = AppRouter.call(message: "I was charged twice")
result.route            # => :billing
result.delegated?       # => true
result.delegated_to     # => BillingAgent
result.content          # => BillingAgent's response content
result.routing_cost     # => cost of classification step
result.total_cost       # => classification + delegation combined
result.delegated_result # => full Result from BillingAgent
```

When a route has an `agent:` mapping, the router automatically classifies and then invokes that agent, returning the delegated agent's response as the result content. Routes without `agent:` just classify.

### Disabling Auto-Delegation

Pass `auto_delegate: false` to classify only and skip the downstream call. The mapped `agent_class` is still exposed on the result so you can invoke it yourself — useful when you want to log, enrich params, or conditionally dispatch:

```ruby
result = AppRouter.call(message: "I was charged twice", auto_delegate: false)

result.route         # => :billing
result.delegated?    # => false
result.agent_class   # => BillingAgent  (still populated for manual dispatch)

# Do something before dispatching...
AuditLog.record(user: current_user, route: result.route)

# ...then invoke the mapped agent manually with extra context
result.agent_class.call(
  message: "I was charged twice",
  user_tier: current_user.tier,
  locale: I18n.locale
)
```

Auto-delegation defaults to `true`, so existing callers are unaffected.

### Streaming Through Delegation

When the caller passes a block and the delegated agent has `streaming true`, chunks from the delegated agent flow through the caller's block — streaming works end-to-end:

```ruby
class BillingAgent < ApplicationAgent
  model "gpt-4o"
  streaming true

  system "You are a billing support specialist."
  user   "{message}"
end

class SupportRouter < ApplicationAgent
  include RubyLLM::Agents::Routing

  model "gpt-4o-mini"
  temperature 0.0

  route :billing, "Billing questions", agent: BillingAgent
  default_route :general
end

SupportRouter.call(message: "I was charged twice") do |chunk|
  print chunk.content
end
# Chunks from BillingAgent stream live into the block.
# The final RoutingResult is returned once delegation completes.
```

The router itself does not need to have streaming enabled — the block is forwarded to the delegated agent regardless. Whether the block fires depends on the **delegated** agent's `streaming` setting.

Combine with `auto_delegate: false` for fully manual streaming dispatch:

```ruby
result = SupportRouter.call(message: msg, auto_delegate: false)
log_classification(result.route)

result.agent_class.call(message: msg) do |chunk|
  stream_to_browser(chunk)
end
```

## RoutingResult

`RoutingResult` extends the standard `Result` with routing-specific fields:

```ruby
result = SupportRouter.call(message: "I was charged twice")

# Routing fields
result.route            # => :billing (Symbol)
result.agent_class      # => BillingAgent or nil
result.raw_response     # => "billing" (raw LLM text)

# Delegation fields (when route has agent: mapping)
result.delegated?       # => true/false
result.delegated_to     # => BillingAgent or nil
result.delegated_result # => full Result from delegated agent, or nil
result.content          # => delegated agent's content (when delegated)
result.routing_cost     # => cost of classification step only
result.total_cost       # => classification + delegation combined

# Standard Result fields (all available)
result.success?       # => true
result.input_tokens   # => 85
result.output_tokens  # => 3
result.duration_ms    # => 280
result.model_id       # => "gpt-4o-mini"
result.cached?        # => false

# Serialization
result.to_h           # => { route: :billing, agent_class: "BillingAgent", delegated: true, ... }
```

## Custom Prompts

### Auto-Generated Prompts

By default, the system prompt is auto-generated from your route definitions:

```
You are a message classifier. Classify the user's message into exactly one
of the following categories:

- billing: Billing, charges, refunds, payments
- technical: Bugs, errors, crashes, technical issues
- sales: Pricing, plans, upgrades, discounts
- general: Default / general category

If none of the categories clearly match, classify as: general

Respond with ONLY the category name, nothing else.
```

### Override System Prompt

Use the `routing_system_prompt` and `routing_categories_text` helpers in custom prompts:

```ruby
class CustomRouter < ApplicationAgent
  include RubyLLM::Agents::Routing

  model "gpt-4o-mini"
  temperature 0.0

  route :urgent,    "Time-sensitive issues requiring immediate attention"
  route :standard,  "Normal priority requests"
  route :feedback,  "Product feedback, suggestions, feature requests"
  default_route :standard

  def system_prompt
    <<~PROMPT
      You are a priority classifier for Acme Corp's support team.

      Classify the following message into one of these categories:
      #{routing_categories_text}

      If unsure, classify as: #{self.class.default_route_name}
    PROMPT
  end
end
```

### Context Injection

Pass extra parameters to enrich the classification:

```ruby
class ContextualRouter < ApplicationAgent
  include RubyLLM::Agents::Routing

  model "gpt-4o-mini"
  temperature 0.0

  route :billing,   "Billing, charges, refunds"
  route :technical,  "Bugs, errors, crashes"
  default_route :general

  param :customer_tier, required: false
  param :locale, default: "en"

  def system_prompt
    base = routing_system_prompt
    extras = []
    extras << "The customer is on the #{customer_tier} tier." if customer_tier
    extras << "The message is in #{locale}." if locale != "en"
    extras.any? ? "#{base}\n\n#{extras.join("\n")}" : base
  end
end

result = ContextualRouter.call(
  message: "J'ai ete facture deux fois",
  customer_tier: "enterprise",
  locale: "fr"
)
result.route  # => :billing
```

## Inline Classification

For one-off classifications without defining a class:

```ruby
route = RubyLLM::Agents::Routing.classify(
  message: "I was charged twice",
  routes: {
    billing: "Billing, charges, refunds",
    technical: "Bugs, errors, crashes",
    sales: "Pricing, plans, upgrades"
  },
  default: :general,
  model: "gpt-4o-mini"
)
# => :billing
```

This creates an anonymous router class under the hood. For repeated use, define a class instead.

## Using with BaseAgent Features

### Caching

Cache identical classifications to avoid redundant API calls:

```ruby
class CachedRouter < ApplicationAgent
  include RubyLLM::Agents::Routing

  model "gpt-4o-mini"
  temperature 0.0
  cache_for 1.hour

  route :billing,  "Billing questions"
  route :technical, "Technical issues"
  default_route :general
end
```

### Reliability

Add retries and fallback models:

```ruby
class ReliableRouter < ApplicationAgent
  include RubyLLM::Agents::Routing

  model "gpt-4o-mini"
  temperature 0.0

  reliability do
    retries max: 2, backoff: :exponential
    fallback_models "gpt-3.5-turbo"
  end

  route :billing,  "Billing questions"
  route :technical, "Technical issues"
  default_route :general
end
```

### Multi-Tenancy

Route per-tenant:

```ruby
result = SupportRouter.call(
  message: "I was charged twice",
  tenant: current_tenant
)
```

### Dry Run

Preview the classification prompt without making an API call:

```ruby
result = SupportRouter.call(message: "test", dry_run: true)
result.content[:system_prompt]  # => "You are a message classifier..."
result.content[:user_prompt]    # => "test"
```

## Inheritance

Routes are inherited from parent classes:

```ruby
class BaseRouter < ApplicationAgent
  include RubyLLM::Agents::Routing

  model "gpt-4o-mini"
  temperature 0.0

  route :billing,  "Billing questions"
  route :technical, "Technical issues"
  default_route :general
end

class ExtendedRouter < BaseRouter
  route :sales, "Sales inquiries"  # Added to inherited routes
end

ExtendedRouter.routes.keys  # => [:billing, :technical, :general, :sales]
```

## Dashboard

Router agents appear in the dashboard with:
- A cyan **Router** badge
- A dedicated **routers** tab in the agents list
- Route definitions displayed in the agent detail view
- Full execution history, cost tracking, and performance charts

## Testing

### Unit Testing Routes

```ruby
RSpec.describe SupportRouter do
  it "classifies billing messages" do
    # Stub the pipeline to return a fake result
    allow(RubyLLM::Agents::Pipeline::Executor).to receive(:execute) do |context|
      context.output = RubyLLM::Agents::Routing::RoutingResult.new(
        base_result: RubyLLM::Agents::Result.new(content: "billing", model_id: "gpt-4o-mini"),
        route_data: { route: :billing, agent_class: nil, raw_response: "billing" }
      )
      context
    end

    result = described_class.call(message: "I was charged twice")
    expect(result.route).to eq(:billing)
  end
end
```

### Testing Response Parsing

Test `process_response` directly without any LLM call:

```ruby
RSpec.describe SupportRouter do
  let(:agent) { described_class.new(message: "test") }

  it "parses clean route names" do
    response = OpenStruct.new(content: "billing")
    result = agent.process_response(response)
    expect(result[:route]).to eq(:billing)
  end

  it "falls back to default for unknown responses" do
    response = OpenStruct.new(content: "unknown_category")
    result = agent.process_response(response)
    expect(result[:route]).to eq(:general)
  end

  it "handles messy LLM output" do
    response = OpenStruct.new(content: "  **Billing**  \n")
    result = agent.process_response(response)
    expect(result[:route]).to eq(:billing)
  end
end
```

### Dry Run Testing

```ruby
RSpec.describe SupportRouter do
  it "generates correct prompts" do
    result = described_class.call(message: "test", dry_run: true)
    expect(result.content[:system_prompt]).to include("billing")
    expect(result.content[:user_prompt]).to eq("test")
  end
end
```

## API Reference

### Module: `RubyLLM::Agents::Routing`

**Class Methods** (added via `ClassMethods`):

| Method | Description |
|--------|-------------|
| `route(name, description, agent: nil)` | Define a classification route |
| `default_route(name, agent: nil)` | Set the default/fallback route |
| `routes` | Returns all defined routes (Hash) |
| `default_route_name` | Returns the default route name (Symbol) |
| `agent_type` | Returns `:router` |

**Instance Methods:**

| Method | Description |
|--------|-------------|
| `routing_system_prompt` | Auto-generated system prompt from routes |
| `routing_categories_text` | Formatted route list for custom prompts |
| `system_prompt` | Returns routing system prompt (overridable) |
| `user_prompt` | Returns the message parameter |
| `process_response(response)` | Parses LLM output to route hash |
| `auto_delegate?` | Whether this call will auto-invoke the mapped agent (default `true`) |

**Call-time Options:**

| Option | Type | Description |
|--------|------|-------------|
| `message:` | String | The message to classify |
| `auto_delegate:` | Boolean | Skip auto-delegation when `false` (default `true`) |
| `tenant:` | Object | Tenant context — standard BaseAgent option |
| `dry_run:` | Boolean | Preview prompts without calling the LLM |

When a block is passed, it is forwarded to the delegated agent. Streaming fires when the delegated agent declares `streaming true`.

**Class Method:**

| Method | Description |
|--------|-------------|
| `Routing.classify(message:, routes:, default:, model:)` | Inline classification without a class |

### Class: `RubyLLM::Agents::Routing::RoutingResult`

Inherits from `Result`. Additional attributes:

| Attribute | Type | Description |
|-----------|------|-------------|
| `route` | Symbol | The classified route name |
| `agent_class` | Class/nil | Mapped agent class (if defined) |
| `raw_response` | String | Raw text from the LLM |
| `delegated?` | Boolean | Whether auto-delegation occurred |
| `delegated_to` | Class/nil | The agent that was auto-invoked |
| `delegated_result` | Result/nil | Full result from the delegated agent |
| `routing_cost` | Float | Cost of classification step only |
