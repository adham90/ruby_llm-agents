# Class-Level Schema DSL

## Goal

Add a class-level `schema` DSL so agents can declare structured output schemas declaratively, consistent with other class-level DSL methods (`model`, `tools`, `temperature`, etc.).

## Current State

- `schema` is an instance method on `BaseAgent` that returns `nil` by default (`base_agent.rb:265`)
- Users override it per-agent to return a `RubyLLM::Schema` or a JSON Schema hash
- Requires boilerplate: method override + `@schema ||=` memoization
- Other config like `model`, `tools`, `timeout` already use class-level DSL

## Desired API

```ruby
# Static schema via class-level DSL (new)
class SummarizerAgent < ApplicationAgent
  schema do
    string :summary, description: "A concise summary"
  end
end

# Instance method override still works (existing, for dynamic schemas)
class DynamicAgent < ApplicationAgent
  def schema
    # runtime logic here
  end
end
```

## Implementation Plan

### 1. Add `schema` class method to `DSL::Base` (`lib/ruby_llm/agents/dsl/base.rb`)

- Accept a block, evaluate it via `RubyLLM::Schema.create(&block)`, store result in `@schema`
- When called without a block, return stored `@schema` (with `inherited_or_default` fallback to `nil`)
- Follows the same pattern as `model`, `timeout`, etc.

```ruby
def schema(&block)
  @schema = RubyLLM::Schema.create(&block) if block
  @schema || inherited_or_default(:schema, nil)
end
```

### 2. Update `BaseAgent` instance `schema` method (`lib/ruby_llm/agents/base_agent.rb:265`)

- Change default to delegate to the class-level value:

```ruby
def schema
  self.class.schema
end
```

- Users can still override this instance method for dynamic schemas — standard Ruby method override takes precedence.

### 3. No changes needed to `build_client`

- `build_client` already calls `client.with_schema(schema)` if schema is truthy (`base_agent.rb:492`)
- The instance method delegation means it just works.

### 4. Tests

- Add spec: class-level `schema` block produces correct schema object
- Add spec: schema inherits from parent class
- Add spec: instance method override takes precedence over class-level DSL
- Add spec: agent without schema still returns `nil`
- Add spec: agent with class-level schema passes it to the LLM client

### 5. Update README/examples

- Add example using class-level `schema do ... end`
- Update `SchemaAgent` example to use the new DSL

## Files to Change

| File | Change |
|------|--------|
| `lib/ruby_llm/agents/dsl/base.rb` | Add `schema` class method |
| `lib/ruby_llm/agents/base_agent.rb` | Update default `schema` to delegate to `self.class.schema` |
| `spec/lib/base_agent_execution_spec.rb` | Add schema DSL specs |
| `example/app/agents/schema_agent.rb` | Update to use new DSL |
| `README.md` | Update schema documentation |

## Notes

- No breaking changes — existing instance method overrides continue to work
- The class-level DSL depends on `RubyLLM::Schema.create` which is provided by the upstream `ruby_llm` gem
