# Evaluation

Score your agents against test datasets to catch regressions and measure quality over time.

## Quick Start

```ruby
# spec/evals/support_router_eval.rb
class SupportRouter::Eval < RubyLLM::Agents::Eval::EvalSuite
  agent SupportRouter

  test_case "billing",   input: { message: "charged twice" }, expected: "billing"
  test_case "technical", input: { message: "500 error" },     expected: "technical"
  test_case "greeting",  input: { message: "hello" },         expected: "general"
end

run = SupportRouter::Eval.run!
puts run.summary
# SupportRouter eval: 3/3 passed (score: 1.0)
```

## Defining Test Cases

Each `test_case` needs a name, an `input:` hash (matching the agent's params), and an `expected:` value to compare against.

```ruby
class MyAgent::Eval < RubyLLM::Agents::Eval::EvalSuite
  agent MyAgent

  test_case "simple",
    input: { query: "What is Ruby?" },
    expected: "Ruby is a programming language"

  test_case "with options",
    input: { query: "refund?" },
    score: :contains,
    expected: "refund policy"
end
```

## Scoring Methods

### Exact Match (default)

Compares the agent's output to `expected:` after stripping whitespace. Works with strings and hashes.

```ruby
test_case "string match",
  input: { text: "hello" },
  expected: "positive"

test_case "hash match",
  input: { message: "refund" },
  expected: { route: :billing }
```

### Contains

Checks that the agent's response includes the expected text (case-insensitive). Supports a single string or an array.

```ruby
test_case "single keyword",
  input: { query: "refund?" },
  score: :contains,
  expected: "refund policy"

test_case "multiple keywords",
  input: { query: "refund?" },
  score: :contains,
  expected: ["refund", "policy", "30 days"]
```

### LLM Judge

Uses a second LLM to score the response on a 0-10 scale against criteria you define.

```ruby
test_case "helpful response",
  input: { query: "How do I reset my password?" },
  score: :llm_judge,
  criteria: "The response should be helpful, accurate, and include step-by-step instructions"

# Use a specific model as judge
test_case "quality check",
  input: { query: "Explain Ruby blocks" },
  score: :llm_judge,
  criteria: "Should be technically accurate and beginner-friendly",
  judge_model: "gpt-4o"
```

### Custom Lambda

Pass any lambda that returns a numeric score (0.0-1.0), a boolean, or a `Score` object.

```ruby
test_case "custom scoring",
  input: { query: "test" },
  score: ->(result, expected) {
    result.content.length > 100 ? 1.0 : 0.0
  }

# Boolean results are coerced (true => 1.0, false => 0.0)
test_case "boolean check",
  input: { query: "test" },
  score: ->(result, _expected) {
    result.content.include?("Ruby")
  }
```

## YAML Datasets

Load test cases from a YAML file instead of defining them inline.

```yaml
# spec/evals/datasets/support_router.yml
- name: billing
  input:
    message: "charged twice"
  expected: billing

- name: technical
  input:
    message: "500 error"
  expected: technical

- name: sales
  input:
    message: "upgrade plan"
  expected: sales
```

```ruby
class SupportRouter::Eval < RubyLLM::Agents::Eval::EvalSuite
  agent SupportRouter
  dataset "spec/evals/datasets/support_router.yml"
end
```

Paths are resolved relative to `Rails.root`. Use an absolute path to load from elsewhere.

## Running Evals

### Basic Run

```ruby
run = MyAgent::Eval.run!
```

### Filtering Cases

```ruby
# Run a single case
run = MyAgent::Eval.run!(only: "billing")

# Run multiple cases
run = MyAgent::Eval.run!(only: ["billing", "technical"])
```

### Custom Threshold

The default pass threshold is 0.5. Override it per run:

```ruby
run = MyAgent::Eval.run!(pass_threshold: 0.8)
```

### Overrides

Merge extra data into every test case's input. Useful for injecting shared database state.

```ruby
tenant = Tenant.create!(name: "Test Corp")
run = MyAgent::Eval.run!(overrides: { tenant_id: tenant.id })
```

### Eval Model Settings

Set a specific model or temperature for the eval run at the suite level:

```ruby
class MyAgent::Eval < RubyLLM::Agents::Eval::EvalSuite
  agent MyAgent
  eval_model "gpt-4o"
  eval_temperature 0.0

  test_case "case1", input: { query: "test" }, expected: "result"
end
```

Or override per run:

```ruby
run = MyAgent::Eval.run!(model: "gpt-4o-mini")
```

## Working with Results

### EvalRun

```ruby
run = MyAgent::Eval.run!

run.score          # => 0.85 (aggregate)
run.passed         # => 17
run.failed         # => 3
run.total_cases    # => 20
run.pass_rate      # => 0.85
run.duration_ms    # => 12500
run.summary        # => formatted text report

# Inspect failures
run.failures.each do |result|
  puts "#{result.test_case_name}: #{result.score.reason}"
end

# Inspect errors
run.errors.each do |result|
  puts "#{result.test_case_name}: #{result.error.message}"
end

# Export
run.to_h           # => Hash
run.to_json        # => JSON string
```

### EvalResult (per case)

```ruby
result = run.results.first

result.test_case_name  # => "billing"
result.score.value     # => 1.0
result.score.reason    # => nil (or explanation on failure)
result.passed?         # => true
result.failed?         # => false
result.errored?        # => false
result.actual          # => "billing"
result.expected        # => "billing"
result.execution_id    # => 42 (if tracking is enabled)
```

## Lazy Inputs (FactoryBot / Fixtures)

When test cases depend on database records, use a lambda for `input:` so the records are created at run time.

```ruby
class SupportRouter::Eval < RubyLLM::Agents::Eval::EvalSuite
  agent SupportRouter

  test_case "with db record",
    input: -> {
      ticket = FactoryBot.create(:ticket, category: "billing")
      { message: ticket.description, ticket_id: ticket.id }
    },
    expected: "billing"
end
```

Lambdas are re-evaluated on every `run!` call, so each run gets fresh data. Param validation is skipped for lambda inputs since the actual hash isn't available until run time.

## Programmatic Suites

Build a suite on the fly without subclassing:

```ruby
suite = RubyLLM::Agents::Eval::EvalSuite.for(SupportRouter) do
  test_case "billing", input: { message: "charged twice" }, expected: "billing"
  test_case "technical", input: { message: "500 error" }, expected: "technical"
end

run = suite.run!
```

## CI Integration

Gate evals behind an environment variable so they don't run on every commit:

```ruby
# spec/evals/support_router_eval_spec.rb
require "rails_helper"

RSpec.describe "SupportRouter eval", if: ENV["RUN_EVAL"] do
  it "meets quality bar" do
    run = SupportRouter::Eval.run!

    expect(run.score).to be >= 0.9
    expect(run.errors).to be_empty
  end
end
```

```bash
# Run evals explicitly
RUN_EVAL=1 bundle exec rspec spec/evals/
```

## Error Handling

If an agent raises during a test case, the suite catches the error and records it as a score of 0.0. The run completes even if individual cases fail.

```ruby
run = MyAgent::Eval.run!

run.errors.each do |result|
  puts "#{result.test_case_name}: #{result.error.class} - #{result.error.message}"
end
```

`ArgumentError` is the exception -- it propagates immediately since it usually indicates a configuration mistake (like an unknown scorer).

## Related Pages

- [Testing Agents](Testing-Agents) - RSpec patterns and mocking
- [Agent DSL](Agent-DSL) - Agent configuration
- [Routing](Routing) - Message classification and routing
