# Knowledge

The `knows` DSL lets agents declare domain knowledge that is automatically compiled and injected into the system prompt at call time.

## Why

Agents often need context beyond what fits in a single `system` string — product FAQs, compliance rules, customer data. Hard-coding this into prompts creates bloated, unmaintainable agent classes. The Knowledge DSL separates **what the agent knows** from **how it behaves**, keeping both clean.

## Quick Start

```ruby
class SupportAgent < ApplicationAgent
  knowledge_path "knowledge"

  system "You are a support agent. Use the knowledge below to answer questions."

  knows :refund_policy    # loads knowledge/refund_policy.md
  knows :shipping_faq     # loads knowledge/shipping_faq.md
end
```

Create the files:

```
app/knowledge/
├── refund_policy.md
└── shipping_faq.md
```

When the agent runs, the file contents are compiled into headed sections and appended to the system prompt automatically.

## Two Modes

### Static (from files)

```ruby
class MyAgent < ApplicationAgent
  knowledge_path "knowledge"
  knows :ruby_style_guide
end
```

Multiple static entries can be declared inline (same pattern as `tools`):

```ruby
class MyAgent < ApplicationAgent
  knowledge_path "knowledge"
  knows :refund_policy, :shipping_faq, :pricing
end
```

Resolves via `knowledge_path`, trying `.md` first, then the bare name. Path is relative to `Rails.root` when Rails is available.

### Dynamic (from blocks)

```ruby
class MyAgent < ApplicationAgent
  knows :recent_tickets do
    Ticket.where(status: :open).limit(10).pluck(:summary)
  end
end
```

Blocks run via `instance_exec` — `self` is the agent instance, so params and methods are directly available (no `|agent|` parameter needed).

**Return types:**

| Type | Formatting |
|------|------------|
| `String` | Injected as-is |
| `Array` | Formatted as a bullet list (`- item`) |
| `nil` | Entry skipped |
| Anything else | `.to_s` |

## Conditional Inclusion

Use `if:` to gate knowledge on agent state:

```ruby
class ComplianceAgent < ApplicationAgent
  knowledge_path "compliance"
  param :region, required: true

  knows :hipaa, if: -> { region == "us" }
  knows :gdpr,  if: -> { region == "eu" }
  knows :global_rules   # always included
end
```

The `if:` lambda runs via `instance_exec`, so agent params are available. When it returns falsy, the entry is skipped entirely. Works with both static and dynamic entries.

## Knowledge Path

Set per-agent or globally:

```ruby
# Per-agent
class MyAgent < ApplicationAgent
  knowledge_path "agents/support/knowledge"
  knows :faq
end

# Global default
RubyLLM::Agents.configure do |config|
  config.knowledge_path = "knowledge"  # default: nil
end
```

Resolution order: agent class > parent class > global config.

## Inheritance

Subclasses inherit parent knowledge entries and can override by name:

```ruby
class BaseSupport < ApplicationAgent
  knowledge_path "knowledge"
  knows :faq
  knows :policies
end

class PremiumSupport < BaseSupport
  # Overrides parent's :faq, keeps :policies
  knows :faq do
    PremiumFaq.for_tier(tier).pluck(:content).join("\n\n")
  end
end
```

## System Prompt Integration

### Automatic (recommended)

When using the `system` DSL, knowledge is appended after placeholder interpolation:

```ruby
class MyAgent < ApplicationAgent
  system "You help {user_name} with coding."
  knows(:style_guide) { "Use 2-space indentation" }
end

agent = MyAgent.new(user_name: "Alice")
agent.system_prompt
# => "You help Alice with coding.\n\n## Style Guide\n\nUse 2-space indentation"
```

### Manual

When overriding `system_prompt`, call `compiled_knowledge` yourself:

```ruby
class MyAgent < ApplicationAgent
  knows :domain_rules

  def system_prompt
    <<~PROMPT
      You are an expert.

      #{compiled_knowledge}

      Be concise.
    PROMPT
  end
end
```

## Configuration

```ruby
RubyLLM::Agents.configure do |config|
  # Base path for static knowledge files (default: nil)
  config.knowledge_path = "knowledge"
end
```

## Related Pages

- **[Agent DSL](Agent-DSL)** - Full DSL reference
- **[Prompts and Schemas](Prompts-and-Schemas)** - System prompts, user prompts, structured output
- **[Parameters](Parameters)** - Agent parameters (used in `if:` conditions and dynamic blocks)
- **[First Agent](First-Agent)** - Getting started tutorial
