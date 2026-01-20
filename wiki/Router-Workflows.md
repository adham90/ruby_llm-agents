# Router Workflows

Conditionally dispatch requests to different agents based on classification.

## Defining a Router

Create a router by inheriting from `RubyLLM::Agents::Workflow::Router`:

```ruby
class LLM::SupportRouter < RubyLLM::Agents::Workflow::Router
  version "1.0"
  classifier_model "gpt-4o-mini"
  classifier_temperature 0.0

  route :billing,   to: LLM::BillingAgent,   description: "Billing, charges, refunds"
  route :technical, to: LLM::TechSupportAgent, description: "Bugs, errors, crashes"
  route :sales,     to: LLM::SalesAgent,     description: "Pricing, plans, upgrades"
  route :default,   to: LLM::GeneralAgent    # Fallback route
end

result = LLM::SupportRouter.call(message: "I was charged twice")
result.routed_to  # => :billing
```

## How It Works

```
                    ┌─► BillingAgent
                    │
Input ──► Classify ─┼─► TechSupportAgent
                    │
                    └─► SalesAgent
```

1. Input is classified (via LLM or rules)
2. Route is selected based on classification
3. Selected agent handles the request

## Route Configuration

### Basic Routes

```ruby
route :name, to: LLM::AgentClass, description: "Description for classifier"
```

The `description` is used by the LLM classifier to understand when to route to this agent.

### Default Route

Always provide a fallback for unmatched classifications:

```ruby
route :billing,  to: LLM::BillingAgent, description: "Billing questions"
route :support,  to: LLM::SupportAgent, description: "Technical support"
route :default,  to: LLM::GeneralAgent  # No description needed
```

### Rule-Based Matching

Skip LLM classification for deterministic routing:

```ruby
route :urgent, to: LLM::UrgentAgent, match: ->(input) {
  input[:priority] == "urgent"
}

route :vip, to: LLM::VIPAgent, match: ->(input) {
  input[:user_tier] == "enterprise"
}

route :default, to: LLM::StandardAgent
```

Rules are evaluated in order. First match wins.

## Classification Methods

### 1. LLM-Based Classification (Default)

Uses the classifier model to analyze input and select a route:

```ruby
class LLM::MyRouter < RubyLLM::Agents::Workflow::Router
  classifier_model "gpt-4o-mini"      # Fast, cheap model
  classifier_temperature 0.0           # Deterministic

  route :billing,  to: LLM::BillingAgent,  description: "Billing, charges, payments"
  route :support,  to: LLM::SupportAgent,  description: "Technical issues, bugs"
  route :default,  to: LLM::GeneralAgent
end
```

The router automatically builds a prompt from route descriptions.

### 2. Rule-Based Classification (Fastest)

Use `match` lambdas for deterministic, free routing:

```ruby
class LLM::FastRouter < RubyLLM::Agents::Workflow::Router
  route :urgent, to: LLM::UrgentAgent, match: ->(input) {
    input[:priority] == "urgent"
  }

  route :billing, to: LLM::BillingAgent, match: ->(input) {
    input[:message].downcase.include?("invoice")
  }

  route :default, to: LLM::GeneralAgent
end
```

### 3. Custom Classification

Override `classify` for custom logic:

```ruby
class LLM::CustomRouter < RubyLLM::Agents::Workflow::Router
  route :simple,  to: LLM::SimpleAgent,  description: "Simple requests"
  route :complex, to: LLM::ComplexAgent, description: "Complex requests"

  def classify(input)
    # Return the route name as a symbol
    if input[:message].length > 200
      :complex
    else
      :simple
    end
  end
end
```

## Classifier Configuration

### Model Selection

Use a fast, cheap model for classification:

```ruby
class LLM::MyRouter < RubyLLM::Agents::Workflow::Router
  classifier_model "gpt-4o-mini"  # Default
  # or
  classifier_model "claude-3-haiku"
end
```

### Temperature

Use low temperature for deterministic classification:

```ruby
class LLM::MyRouter < RubyLLM::Agents::Workflow::Router
  classifier_temperature 0.0  # Default: deterministic
end
```

## Input Transformation

### before_route Hook

Transform input before passing to the selected agent:

```ruby
class LLM::MyRouter < RubyLLM::Agents::Workflow::Router
  route :billing,  to: LLM::BillingAgent,  description: "Billing questions"
  route :support,  to: LLM::SupportAgent,  description: "Technical support"

  def before_route(input, chosen_route)
    input.merge(
      route_context: chosen_route,
      priority: input[:urgent] ? "high" : "normal",
      classified_at: Time.current
    )
  end
end
```

## Accessing Results

```ruby
result = LLM::MyRouter.call(message: "I need help")

# Routing info
result.routed_to           # :support - Selected route name
result.classification      # Classification details hash

# Classification details
result.classification[:route]            # :support
result.classification[:method]           # "rule" or "llm"
result.classification[:classifier_model] # "gpt-4o-mini" (if LLM)
result.classification[:classification_time_ms]

# Classifier result (LLM-based only)
result.classifier_result   # Result object from classifier agent

# Route agent result
result.content             # Response from the routed agent
result.branches[:support]  # Full result from selected agent

# Cost breakdown
result.classification_cost # Cost of classification only
result.total_cost         # Classification + route agent cost
result.duration_ms        # Total execution time
```

## Error Handling

### Missing Routes

If no route matches and no default is defined, a `RouterError` is raised:

```ruby
class LLM::MyRouter < RubyLLM::Agents::Workflow::Router
  route :billing, to: LLM::BillingAgent, description: "Billing only"
  # No default route!
end

# Raises RouterError if message doesn't match billing
```

Always provide a default route:

```ruby
route :default, to: LLM::FallbackAgent
```

### Route Agent Failures

Handle failures in routed agents:

```ruby
result = LLM::MyRouter.call(message: "help")

if result.error?
  puts "Route agent failed: #{result.error_message}"
end
```

## Real-World Examples

### Customer Service Router

```ruby
class LLM::CustomerServiceRouter < RubyLLM::Agents::Workflow::Router
  version "1.0"
  classifier_model "gpt-4o-mini"
  classifier_temperature 0.0

  # Priority routing (rule-based, checked first)
  route :urgent, to: LLM::UrgentSupportAgent, match: ->(input) {
    input[:priority] == "urgent" || input[:message].downcase.include?("urgent")
  }

  # LLM-classified routes
  route :order_status, to: LLM::OrderStatusAgent, description: "Order tracking, delivery status, shipping"
  route :returns,      to: LLM::ReturnAgent,      description: "Returns, refunds, exchanges"
  route :product,      to: LLM::ProductAgent,     description: "Product questions, specifications"
  route :billing,      to: LLM::BillingAgent,     description: "Charges, invoices, payment issues"
  route :default,      to: LLM::GeneralSupportAgent

  def before_route(input, chosen_route)
    input.merge(
      escalate: input[:sentiment] == "angry",
      customer_context: fetch_customer_context(input[:customer_id])
    )
  end

  private

  def fetch_customer_context(customer_id)
    # Load customer history, etc.
  end
end

result = LLM::CustomerServiceRouter.call(
  message: "Where is my order?",
  customer_id: 123
)
```

### Multi-Language Router

```ruby
class LLM::LanguageRouter < RubyLLM::Agents::Workflow::Router
  version "1.0"
  classifier_model "gpt-4o-mini"

  route :english,  to: LLM::EnglishAgent,  description: "English language text"
  route :spanish,  to: LLM::SpanishAgent,  description: "Spanish language text"
  route :french,   to: LLM::FrenchAgent,   description: "French language text"
  route :german,   to: LLM::GermanAgent,   description: "German language text"
  route :default,  to: LLM::EnglishAgent   # Fallback to English
end
```

### Content Moderation Router

```ruby
class LLM::ModerationRouter < RubyLLM::Agents::Workflow::Router
  version "1.0"
  classifier_model "gpt-4o-mini"

  route :approve, to: LLM::PublishAgent,       description: "Safe, appropriate content"
  route :review,  to: LLM::HumanReviewAgent,   description: "Questionable content needing review"
  route :reject,  to: LLM::RejectionNotifier,  description: "Clearly inappropriate content"

  def before_route(input, chosen_route)
    input.merge(
      moderation_result: chosen_route,
      flagged_at: Time.current
    )
  end
end
```

### Tiered Support Router

```ruby
class LLM::TieredSupportRouter < RubyLLM::Agents::Workflow::Router
  version "1.0"

  route :tier1, to: LLM::BasicBotAgent,    description: "Simple FAQs, basic questions"
  route :tier2, to: LLM::StandardAgent,    description: "Moderate complexity issues"
  route :tier3, to: LLM::ExpertAgent,      description: "Complex technical problems"

  # Custom classification based on complexity scoring
  def classify(input)
    complexity = calculate_complexity(input[:message])

    case complexity
    when 0..3  then :tier1
    when 4..7  then :tier2
    else            :tier3
    end
  end

  private

  def calculate_complexity(message)
    # Scoring logic based on length, technical terms, etc.
    score = 0
    score += 2 if message.length > 200
    score += 3 if message.match?(/error|exception|stack trace/i)
    score += 2 if message.match?(/api|integration|deployment/i)
    score
  end
end
```

### Hybrid Router (Rules + LLM)

```ruby
class LLM::HybridRouter < RubyLLM::Agents::Workflow::Router
  version "1.0"
  classifier_model "gpt-4o-mini"

  # Rule-based routes (checked first, free)
  route :vip, to: LLM::VIPAgent, match: ->(input) {
    input[:user_tier] == "enterprise"
  }

  route :urgent, to: LLM::UrgentAgent, match: ->(input) {
    input[:priority] == "urgent"
  }

  # LLM-classified routes (fallback)
  route :billing,  to: LLM::BillingAgent,  description: "Billing questions"
  route :support,  to: LLM::SupportAgent,  description: "Technical support"
  route :default,  to: LLM::GeneralAgent
end

# VIP users -> VIPAgent (no LLM cost)
# Urgent -> UrgentAgent (no LLM cost)
# Others -> LLM classification
```

## Inheritance

Routers support inheritance:

```ruby
class LLM::BaseRouter < RubyLLM::Agents::Workflow::Router
  classifier_model "gpt-4o-mini"

  route :billing, to: LLM::BillingAgent, description: "Billing questions"
  route :default, to: LLM::GeneralAgent
end

class LLM::ExtendedRouter < LLM::BaseRouter
  # Inherits :billing and :default routes
  route :technical, to: LLM::TechAgent, description: "Technical issues"
end
```

## Best Practices

### Fast Classifier

Use a fast, cheap model for classification:

```ruby
class LLM::FastRouter < RubyLLM::Agents::Workflow::Router
  classifier_model "gpt-4o-mini"  # Fast and cheap
  classifier_temperature 0.0       # Deterministic
end
```

### Clear Route Categories

Use distinct, non-overlapping descriptions:

```ruby
# Good: Distinct categories
route :billing,  to: LLM::BillingAgent,  description: "Billing, charges, invoices"
route :support,  to: LLM::SupportAgent,  description: "Technical issues, bugs, errors"
route :sales,    to: LLM::SalesAgent,    description: "Pricing, plans, upgrades"

# Bad: Overlapping categories
route :help,       to: LLM::HelpAgent,    description: "Help with anything"
route :support,    to: LLM::SupportAgent, description: "Support for issues"
route :assistance, to: LLM::AssistAgent,  description: "Assistance needed"
```

### Always Have a Default

```ruby
class LLM::SafeRouter < RubyLLM::Agents::Workflow::Router
  route :known,   to: LLM::KnownAgent,   description: "Known request types"
  route :default, to: LLM::FallbackAgent  # Always provide this!
end
```

### Use Rules for Deterministic Cases

```ruby
class LLM::EfficientRouter < RubyLLM::Agents::Workflow::Router
  # Free, instant routing for known patterns
  route :urgent, to: LLM::UrgentAgent, match: ->(i) { i[:priority] == "urgent" }
  route :vip,    to: LLM::VIPAgent,    match: ->(i) { i[:tier] == "enterprise" }

  # LLM only for ambiguous cases
  route :billing, to: LLM::BillingAgent, description: "Billing questions"
  route :default, to: LLM::GeneralAgent
end
```

### Log Classification Decisions

```ruby
class LLM::LoggingRouter < RubyLLM::Agents::Workflow::Router
  route :a, to: LLM::AgentA, description: "Type A"
  route :b, to: LLM::AgentB, description: "Type B"

  def before_route(input, chosen_route)
    Rails.logger.info({
      event: "route_classification",
      input: input[:message].truncate(100),
      route: chosen_route,
      timestamp: Time.current
    }.to_json)

    input
  end
end
```

### Monitor Route Distribution

```ruby
# Track how often each route is used
RubyLLM::Agents::Execution
  .where.not(routed_to: nil)
  .where(created_at: 1.day.ago..)
  .group(:routed_to)
  .count
# => { "billing" => 150, "support" => 300, "sales" => 50 }
```

## Related Pages

- [Workflows](Workflows) - Workflow overview
- [Pipeline Workflows](Pipeline-Workflows) - Sequential execution
- [Parallel Workflows](Parallel-Workflows) - Concurrent execution
- [Examples](Examples) - More router examples
