# RouterAgent Implementation Plan

## Overview

Create a specialized `RouterAgent` for classifying input and routing to appropriate handlers. Unlike the current `Workflow::Router`, this is a pure classification agent that follows standard agent conventions (prompts, caching, reliability).

## Goals

1. **Pure classification** - Returns route, does NOT execute target agent
2. **Agent conventions** - Uses same DSL as other agents (model, prompts, cache, reliability)
3. **Customizable prompts** - User controls system_prompt and user_prompt
4. **Context injection** - Pass customer, tenant, or any context into classification
5. **Observability** - Track classification cost, tokens, confidence
6. **Dual API** - Class-based for reusable routers, inline for quick use

## Design

### Class-based RouterAgent

```ruby
class SupportRouter < RubyLLM::Agents::RouterAgent
  model "gpt-4o-mini"
  temperature 0.0
  version "1.0"

  # Optional: caching & reliability (inherited from BaseAgent)
  cache_for 1.hour

  reliability do
    retries max: 2
    fallback_models "gpt-3.5-turbo"
  end

  # Route definitions
  route :billing, description: "Billing, charges, refunds, payments"
  route :technical, description: "Bugs, errors, crashes, technical issues"
  route :sales, description: "Pricing, plans, upgrades, discounts"
  default :general

  # Optional: Rule-based matching (checked before LLM)
  match :urgent, when: ->(input) { input[:priority] == "urgent" }
  match :password, when: ->(input) { input[:message] =~ /password|reset/i }

  # Customizable prompts
  def system_prompt
    <<~PROMPT
      You are a customer support classifier for #{company_name}.

      Classify the user's message into exactly ONE category:
      #{formatted_routes}

      Context:
      - Customer tier: #{customer_tier}
      - Account age: #{account_age}

      Respond with ONLY the category name, nothing else.
    PROMPT
  end

  def user_prompt
    "Classify: #{message}"
  end

  private

  def company_name
    options[:company] || "Our Company"
  end

  def customer_tier
    options[:customer]&.tier || "standard"
  end

  def account_age
    options[:customer]&.created_at&.to_date || "unknown"
  end
end
```

### Usage

```ruby
# Basic usage
result = SupportRouter.call(message: "I was charged twice")
result.route       # => :billing
result.agent       # => nil (pure router doesn't map to agents)
result.confidence  # => 0.95 (if model returns it)
result.cost        # => 0.0001
result.cached?     # => false

# With context
result = SupportRouter.call(
  message: "I was charged twice",
  company: "Acme Inc",
  customer: current_user
)

# Caller decides what to do with route
case result.route
when :billing then BillingAgent.call(message: msg)
when :technical then TechAgent.call(message: msg)
else GeneralAgent.call(message: msg)
end
```

### RouterAgent with Agent Mapping

```ruby
class SupportRouter < RubyLLM::Agents::RouterAgent
  model "gpt-4o-mini"

  # Map routes to agent classes
  route :billing, to: BillingAgent, description: "Billing issues"
  route :technical, to: TechAgent, description: "Technical issues"
  default :general, to: GeneralAgent

  def system_prompt
    # ...
  end
end

# Usage
result = SupportRouter.call(message: "refund please")
result.route  # => :billing
result.agent  # => BillingAgent (class, not executed)

# Execute the routed agent
result.agent.call(message: msg)

# Or use convenience method
result.execute(message: msg)  # Calls result.agent.call(...)
```

### Inline API (No Class)

```ruby
# Simple inline classification
route = RubyLLM::Agents.classify(
  message: "I was charged twice",
  model: "gpt-4o-mini",
  routes: {
    billing: "Billing, charges, refunds",
    technical: "Bugs, errors, crashes",
    sales: "Pricing, plans, upgrades"
  },
  default: :general
)
# => :billing

# With custom prompt
route = RubyLLM::Agents.classify(
  message: "I was charged twice",
  model: "gpt-4o-mini",
  routes: { billing: "...", technical: "..." },
  system_prompt: "You are a classifier for Acme Inc. Be precise.",
  default: :general
)

# With agent mapping
result = RubyLLM::Agents.classify(
  message: "refund please",
  model: "gpt-4o-mini",
  routes: {
    billing: { description: "Billing issues", agent: BillingAgent },
    technical: { description: "Tech issues", agent: TechAgent }
  },
  default: { route: :general, agent: GeneralAgent }
)
result.route  # => :billing
result.agent  # => BillingAgent
```

## Implementation

### File Structure

```
lib/ruby_llm/agents/
├── router_agent.rb              # Main RouterAgent class
├── router_agent/
│   ├── dsl.rb                   # Route DSL (route, match, default)
│   ├── classification.rb        # LLM classification logic
│   ├── result.rb                # RouterResult class
│   └── inline.rb                # RubyLLM::Agents.classify helper
```

### Phase 1: Core RouterAgent

1. **Create `RouterAgent` base class**
   - Extend `BaseAgent` (inherit caching, reliability, instrumentation)
   - Add route DSL (`route`, `match`, `default`)
   - Override `call` to return `RouterResult` instead of content

2. **Create `RouterResult` class**
   - `route` - Symbol of chosen route
   - `agent` - Agent class (if mapped)
   - `confidence` - Classification confidence (if available)
   - `cost` - Cost of classification
   - `cached?` - Whether result was cached
   - `execute(**options)` - Convenience method to call the routed agent

3. **Implement classification logic**
   - Check rule-based matches first (`match ... when:`)
   - Fall back to LLM classification
   - Build prompt from routes with descriptions
   - Parse LLM response to extract route

### Phase 2: Prompt Customization

1. **Default prompt generation**
   - Auto-generate from route descriptions
   - Include `formatted_routes` helper

2. **Custom prompt support**
   - `system_prompt` method (like other agents)
   - `user_prompt` method
   - Access to `options` for context injection

### Phase 3: Inline API

1. **Add `RubyLLM::Agents.classify` method**
   - Quick inline classification without defining a class
   - Support routes hash, model, prompt options
   - Return route symbol or RouterResult

### Phase 4: Testing & Documentation

1. **Unit tests**
   - Route matching (rule-based)
   - LLM classification
   - Prompt customization
   - Caching behavior
   - Reliability (retries/fallbacks)

2. **Integration tests**
   - Full flow with real agents
   - Context injection

3. **Documentation**
   - README section
   - YARD docs
   - Example agents

## RouterResult Class

```ruby
module RubyLLM
  module Agents
    class RouterResult < Result
      attr_reader :route, :agent, :confidence, :classified_by

      def initialize(route:, agent: nil, confidence: nil, classified_by: nil, **attrs)
        @route = route
        @agent = agent
        @confidence = confidence
        @classified_by = classified_by  # :rule or :llm
        super(**attrs)
      end

      # Execute the routed agent
      def execute(**options)
        raise RouterError, "No agent mapped for route :#{route}" unless agent
        agent.call(**options)
      end

      # Check if classification was from cache
      def cached?
        @cached || false
      end

      # Check if rule-based match was used
      def rule_matched?
        classified_by == :rule
      end
    end
  end
end
```

## DSL Design

```ruby
module RubyLLM
  module Agents
    class RouterAgent < BaseAgent
      extend RouterAgent::DSL

      class << self
        def routes
          @routes ||= {}
        end

        def matches
          @matches ||= []
        end

        def default_route
          @default_route
        end

        # DSL: Define a route
        def route(name, to: nil, description: nil)
          routes[name] = {
            agent: to,
            description: description
          }
        end

        # DSL: Define a rule-based match
        def match(name, when:)
          matches << { name: name, condition: binding.local_variable_get(:when) }
        end

        # DSL: Set default route
        def default(name, to: nil)
          @default_route = { name: name, agent: to }
        end

        # Helper: Format routes for prompt
        def formatted_routes
          routes.map { |name, config|
            "- #{name}: #{config[:description]}"
          }.join("\n")
        end
      end
    end
  end
end
```

## Migration from Workflow::Router

The existing `Workflow::Router` will remain for backward compatibility but can be deprecated in favor of `RouterAgent`:

| Workflow::Router | RouterAgent |
|------------------|-------------|
| Extends Workflow | Extends BaseAgent |
| Executes routed agent | Returns route only |
| Limited prompt control | Full prompt customization |
| No caching | Caching via `cache_for` |
| Basic reliability | Full reliability DSL |

## Open Questions

1. **Confidence scores** - Not all models return confidence. Should we:
   - Ask for confidence in the prompt?
   - Use logprobs if available?
   - Skip confidence entirely?

2. **Multi-classification** - Should we support returning multiple routes?
   ```ruby
   result.routes  # => [:billing, :technical]
   ```

3. **Structured output** - Should we use JSON mode for more reliable parsing?
   ```ruby
   class MyRouter < RouterAgent
     structured_output true  # Forces JSON response
   end
   ```

4. **Route metadata** - Should routes support additional metadata?
   ```ruby
   route :billing,
         to: BillingAgent,
         description: "Billing issues",
         priority: :high,
         sla_minutes: 30
   ```

## Success Criteria

- [ ] RouterAgent inherits from BaseAgent
- [ ] Full prompt customization (system_prompt, user_prompt)
- [ ] Rule-based matching with `match ... when:`
- [ ] LLM classification with `route ... description:`
- [ ] Caching support (`cache_for`)
- [ ] Reliability support (retries, fallbacks)
- [ ] RouterResult with route, agent, confidence, cost
- [ ] Inline API (`RubyLLM::Agents.classify`)
- [ ] Comprehensive tests
- [ ] Documentation

## Timeline

- Phase 1 (Core): 2-3 hours
- Phase 2 (Prompts): 1 hour
- Phase 3 (Inline): 1 hour
- Phase 4 (Tests/Docs): 2 hours

**Total: ~6-7 hours**
