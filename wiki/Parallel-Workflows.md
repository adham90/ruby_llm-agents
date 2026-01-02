# Parallel Workflows

Execute multiple agents concurrently and combine their results.

## Basic Parallel Workflow

```ruby
workflow = RubyLLM::Agents::Workflow.parallel(
  sentiment: SentimentAgent,
  entities: EntityAgent,
  summary: SummaryAgent
)

result = workflow.call(text: "analyze this content")
# => {
#   sentiment: { score: 0.8, label: "positive" },
#   entities: { people: [...], places: [...] },
#   summary: { text: "..." }
# }
```

## How It Works

All agents run concurrently:

```
             ┌─► SentimentAgent ─┐
             │                   │
Input ───────┼─► EntityAgent ────┼───► Combined Result
             │                   │
             └─► SummaryAgent ───┘
```

## Branch Configuration

### Named Branches

```ruby
workflow = RubyLLM::Agents::Workflow.parallel(
  analysis: AnalysisAgent,
  recommendations: RecommendationAgent,
  risk_assessment: RiskAgent
)

result = workflow.call(data: input)
result[:analysis]         # AnalysisAgent result
result[:recommendations]  # RecommendationAgent result
result[:risk_assessment] # RiskAgent result
```

### Optional Branches

```ruby
workflow = RubyLLM::Agents::Workflow.parallel(
  required: RequiredAgent,
  optional: { agent: OptionalAgent, optional: true }
)

# If OptionalAgent fails, workflow still succeeds
```

### Conditional Branches

```ruby
workflow = RubyLLM::Agents::Workflow.parallel(
  base: BaseAgent,
  premium: {
    agent: PremiumAgent,
    skip_if: ->(context) { !context[:is_premium] }
  }
)

# Premium branch only runs for premium users
result = workflow.call(data: input, is_premium: false)
```

## Result Aggregation

### Default: Merge Results

```ruby
result = workflow.call(text: content)
# => { sentiment: {...}, entities: {...}, summary: {...} }
```

### Custom Aggregation

```ruby
workflow = RubyLLM::Agents::Workflow.parallel(
  sentiment: SentimentAgent,
  keywords: KeywordAgent,
  aggregate: ->(results) {
    {
      overall_score: calculate_score(results),
      tags: results[:keywords][:words],
      mood: results[:sentiment][:label]
    }
  }
)
```

## Error Handling

### Fail Fast (Default)

If any branch fails, abort all:

```ruby
workflow = RubyLLM::Agents::Workflow.parallel(
  a: AgentA,
  b: AgentB,
  fail_fast: true  # Default
)
```

### Complete All

Continue even if some branches fail:

```ruby
workflow = RubyLLM::Agents::Workflow.parallel(
  a: AgentA,
  b: AgentB,
  fail_fast: false
)

result = workflow.call(input: data)
result[:a]  # Success result or error
result[:b]  # Success result or error
result.errors  # List of branch errors
```

### Branch-Level Error Handling

```ruby
workflow = RubyLLM::Agents::Workflow.parallel(
  critical: CriticalAgent,
  optional: {
    agent: OptionalAgent,
    on_failure: ->(error) {
      { fallback: true, error: error.message }
    }
  }
)
```

## Timeouts

### Workflow Timeout

```ruby
workflow = RubyLLM::Agents::Workflow.parallel(
  a: AgentA,
  b: AgentB,
  timeout: 30  # All branches must complete within 30s
)
```

### Per-Branch Timeouts

Individual agents have their own timeouts:

```ruby
class FastAgent < ApplicationAgent
  timeout 5
end

class SlowAgent < ApplicationAgent
  timeout 60
end
```

## Cost Control

### Max Parallel Cost

```ruby
workflow = RubyLLM::Agents::Workflow.parallel(
  a: AgentA,
  b: AgentB,
  max_cost: 0.50  # Combined cost limit
)
```

### Track Branch Costs

```ruby
result = workflow.call(input: data)

result.branch_results.each do |name, branch|
  puts "#{name}: $#{branch[:cost]}"
end

puts "Total: $#{result.total_cost}"
```

## Real-World Examples

### Content Analysis

```ruby
# Analyze content from multiple perspectives
content_analysis = RubyLLM::Agents::Workflow.parallel(
  sentiment: SentimentAnalyzer,
  topics: TopicExtractor,
  entities: EntityRecognizer,
  readability: ReadabilityScorer
)

result = content_analysis.call(text: article_content)
# All four analyses run concurrently
```

### Multi-Language Translation

```ruby
# Translate to multiple languages at once
translation_workflow = RubyLLM::Agents::Workflow.parallel(
  spanish: SpanishTranslator,
  french: FrenchTranslator,
  german: GermanTranslator,
  japanese: JapaneseTranslator
)

translations = translation_workflow.call(text: english_text)
# All translations run in parallel
```

### Risk Assessment

```ruby
# Multiple risk evaluations
risk_workflow = RubyLLM::Agents::Workflow.parallel(
  financial: FinancialRiskAgent,
  operational: OperationalRiskAgent,
  compliance: ComplianceRiskAgent,
  aggregate: ->(results) {
    {
      overall_risk: calculate_overall(results),
      breakdown: results,
      recommendations: generate_recommendations(results)
    }
  }
)
```

### A/B Model Comparison

```ruby
# Compare responses from different models
comparison_workflow = RubyLLM::Agents::Workflow.parallel(
  gpt4: GPT4Agent,
  claude: ClaudeAgent,
  gemini: GeminiAgent
)

responses = comparison_workflow.call(prompt: user_query)
# Compare quality, cost, and latency
```

## Performance Benefits

Parallel execution significantly reduces total time:

```ruby
# Sequential: 3 agents × 1s each = 3s total
# Parallel: 3 agents running concurrently = ~1s total

# Time savings
sequential_time = agents.sum { |a| a.avg_duration_ms }
parallel_time = agents.max { |a| a.avg_duration_ms }
savings = sequential_time - parallel_time
```

## Thread Safety

Agents in parallel workflows run in separate threads:

```ruby
# Ensure thread-safe agent code
class SafeAgent < ApplicationAgent
  def call
    # Avoid shared mutable state
    # Use thread-local storage if needed
    Thread.current[:agent_context] = context
    super
  end
end
```

## Best Practices

### Independent Branches

```ruby
# Good: Branches don't depend on each other
parallel(
  sentiment: SentimentAgent,    # Independent
  entities: EntityAgent,        # Independent
  keywords: KeywordAgent        # Independent
)

# Bad: Use pipeline if branches depend on each other
```

### Appropriate Parallelism

```ruby
# Good: 2-5 concurrent branches
parallel(a: A, b: B, c: C)

# Avoid: Too many concurrent branches
# Can overwhelm API rate limits
parallel(a: A, b: B, c: C, d: D, e: E, f: F, g: G, h: H)
```

### Handle Partial Failures

```ruby
workflow = RubyLLM::Agents::Workflow.parallel(
  critical: { agent: CriticalAgent },
  nice_to_have: { agent: OptionalAgent, optional: true }
)
```

### Monitor Branch Performance

```ruby
result = workflow.call(input: data)

slowest = result.branch_results.max_by { |_, b| b[:duration_ms] }
puts "Slowest branch: #{slowest[0]} (#{slowest[1][:duration_ms]}ms)"
```

## Related Pages

- [Workflows](Workflows) - Workflow overview
- [Pipeline Workflows](Pipeline-Workflows) - Sequential execution
- [Router Workflows](Router-Workflows) - Conditional dispatch
- [Examples](Examples) - More parallel examples
