# Router Workflows

Conditionally dispatch requests to different agents based on classification.

## Basic Router

```ruby
workflow = RubyLLM::Agents::Workflow.router(
  classifier: IntentClassifier,
  routes: {
    "support" => SupportAgent,
    "sales" => SalesAgent,
    "billing" => BillingAgent,
    "general" => GeneralAgent
  }
)

result = workflow.call(message: "I need help with my order")
# IntentClassifier determines: "support"
# SupportAgent handles the request
```

## How It Works

```
                    ┌─► SupportAgent
                    │
Input ──► Classifier ──► SalesAgent
                    │
                    └─► BillingAgent
```

1. Classifier agent analyzes input
2. Returns a route key
3. Corresponding agent handles request

## Classifier Agent

The classifier must return a route key:

```ruby
class IntentClassifier < ApplicationAgent
  model "gpt-4o-mini"
  param :message, required: true

  def user_prompt
    "Classify this customer message: #{message}"
  end

  def schema
    @schema ||= RubyLLM::Schema.create do
      string :intent,
             enum: ["support", "sales", "billing", "general"],
             description: "The detected intent"
      number :confidence,
             description: "Confidence score 0-1"
    end
  end
end
```

## Route Configuration

### Simple Routes

```ruby
routes: {
  "support" => SupportAgent,
  "sales" => SalesAgent
}
```

### Routes with Options

```ruby
routes: {
  "support" => {
    agent: SupportAgent,
    transform: ->(input, classification) {
      input.merge(priority: classification[:confidence] > 0.9 ? "high" : "normal")
    }
  }
}
```

## Default Route

Handle unmatched classifications:

```ruby
workflow = RubyLLM::Agents::Workflow.router(
  classifier: IntentClassifier,
  routes: {
    "support" => SupportAgent,
    "sales" => SalesAgent
  },
  default: GeneralAgent  # Fallback for unknown intents
)
```

## Classification Field

Specify which field contains the route key:

```ruby
workflow = RubyLLM::Agents::Workflow.router(
  classifier: IntentClassifier,
  classification_field: :intent,  # Default
  routes: { ... }
)

# Classifier returns: { intent: "support", confidence: 0.95 }
# Router uses :intent field
```

## Confidence Thresholds

Route based on confidence levels:

```ruby
workflow = RubyLLM::Agents::Workflow.router(
  classifier: IntentClassifier,
  routes: {
    "support" => SupportAgent,
    "sales" => SalesAgent
  },
  default: GeneralAgent,
  confidence_threshold: 0.8  # Use default if confidence < 80%
)
```

Custom threshold logic:

```ruby
workflow = RubyLLM::Agents::Workflow.router(
  classifier: IntentClassifier,
  routes: { ... },
  select_route: ->(classification, routes) {
    if classification[:confidence] < 0.7
      :default
    else
      classification[:intent]
    end
  }
)
```

## Input Transformation

Transform input before passing to route agent:

```ruby
workflow = RubyLLM::Agents::Workflow.router(
  classifier: IntentClassifier,
  routes: {
    "support" => SupportAgent,
    "sales" => SalesAgent
  },
  transform_input: ->(input, classification) {
    input.merge(
      detected_intent: classification[:intent],
      confidence: classification[:confidence]
    )
  }
)
```

## Result Metadata

Router results include classification info:

```ruby
result = workflow.call(message: "help")

result.content           # Route agent's response
result.classification    # Classifier's output
result.routed_to         # Agent that handled request
result.total_cost        # Classifier + route agent costs
```

## Error Handling

### Classifier Failure

```ruby
workflow = RubyLLM::Agents::Workflow.router(
  classifier: IntentClassifier,
  routes: { ... },
  on_classifier_failure: ->(error) {
    # Fall back to default route
    :default
  }
)
```

### Route Agent Failure

```ruby
workflow = RubyLLM::Agents::Workflow.router(
  classifier: IntentClassifier,
  routes: {
    "support" => {
      agent: SupportAgent,
      on_failure: ->(error) {
        { error: true, fallback_message: "Please try again later" }
      }
    }
  }
)
```

## Real-World Examples

### Customer Service Router

```ruby
class CustomerServiceRouter
  def self.workflow
    RubyLLM::Agents::Workflow.router(
      classifier: CustomerIntentClassifier,
      routes: {
        "order_status" => OrderStatusAgent,
        "return_request" => ReturnAgent,
        "product_question" => ProductAgent,
        "complaint" => ComplaintAgent,
        "billing" => BillingAgent
      },
      default: GeneralSupportAgent,
      confidence_threshold: 0.75,
      transform_input: ->(input, classification) {
        input.merge(
          escalate: classification[:sentiment] == "angry"
        )
      }
    )
  end
end

result = CustomerServiceRouter.workflow.call(
  message: "Where is my order?",
  customer_id: 123
)
```

### Multi-Language Router

```ruby
language_router = RubyLLM::Agents::Workflow.router(
  classifier: LanguageDetector,
  classification_field: :language,
  routes: {
    "en" => EnglishAgent,
    "es" => SpanishAgent,
    "fr" => FrenchAgent,
    "de" => GermanAgent
  },
  default: EnglishAgent  # Fallback to English
)
```

### Content Moderation Router

```ruby
moderation_router = RubyLLM::Agents::Workflow.router(
  classifier: ContentModerator,
  classification_field: :action,
  routes: {
    "approve" => PublishAgent,
    "review" => HumanReviewAgent,
    "reject" => RejectionNotifier
  },
  transform_input: ->(input, classification) {
    input.merge(
      moderation_flags: classification[:flags],
      risk_score: classification[:risk_score]
    )
  }
)
```

### Tiered Support Router

```ruby
tiered_router = RubyLLM::Agents::Workflow.router(
  classifier: ComplexityAnalyzer,
  routes: {
    "simple" => Tier1Agent,      # Basic FAQ bot
    "moderate" => Tier2Agent,    # Standard support
    "complex" => Tier3Agent      # Advanced support
  },
  select_route: ->(classification, routes) {
    case classification[:complexity_score]
    when 0..3 then "simple"
    when 4..7 then "moderate"
    else "complex"
    end
  }
)
```

## Best Practices

### Fast Classifier

```ruby
# Use a fast, cheap model for classification
class IntentClassifier < ApplicationAgent
  model "gpt-4o-mini"  # Fast and cheap
  temperature 0.0      # Deterministic
end
```

### Clear Route Categories

```ruby
# Good: Distinct, non-overlapping categories
routes: {
  "support" => SupportAgent,
  "sales" => SalesAgent,
  "billing" => BillingAgent
}

# Bad: Ambiguous categories
routes: {
  "help" => HelpAgent,      # Overlaps with support
  "support" => SupportAgent,
  "assistance" => AssistAgent
}
```

### Always Have a Default

```ruby
workflow = RubyLLM::Agents::Workflow.router(
  classifier: Classifier,
  routes: { ... },
  default: FallbackAgent  # Always provide a default
)
```

### Log Classification Decisions

```ruby
workflow = RubyLLM::Agents::Workflow.router(
  classifier: Classifier,
  routes: { ... },
  after_classification: ->(input, classification) {
    Rails.logger.info({
      input: input[:message],
      intent: classification[:intent],
      confidence: classification[:confidence]
    }.to_json)
  }
)
```

### Monitor Route Distribution

```ruby
# Track how often each route is used
RubyLLM::Agents::Execution
  .where(workflow_id: workflow_id)
  .where.not(routed_to: nil)
  .group(:agent_type)
  .count
# => { "SupportAgent" => 450, "SalesAgent" => 200, ... }
```

## Related Pages

- [Workflows](Workflows) - Workflow overview
- [Pipeline Workflows](Pipeline-Workflows) - Sequential execution
- [Parallel Workflows](Parallel-Workflows) - Concurrent execution
- [Examples](Examples) - More router examples
