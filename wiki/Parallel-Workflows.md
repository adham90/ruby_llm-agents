# Parallel Workflows

Execute multiple agents concurrently and combine their results.

## Defining a Parallel Workflow

Create a parallel workflow by inheriting from `RubyLLM::Agents::Workflow::Parallel`:

```ruby
class ReviewAnalyzer < RubyLLM::Agents::Workflow::Parallel
  version "1.0"
  timeout 30.seconds
  max_cost 0.50

  branch :sentiment, agent: SentimentAgent
  branch :entities,  agent: EntityAgent
  branch :summary,   agent: SummaryAgent
end

result = ReviewAnalyzer.call(text: "analyze this content")
```

## How It Works

All branches run concurrently:

```
             ┌─► SentimentAgent ─┐
             │                   │
Input ───────┼─► EntityAgent ────┼───► Combined Result
             │                   │
             └─► SummaryAgent ───┘
```

## Branch Configuration

### Basic Branch

```ruby
branch :name, agent: AgentClass
```

### Optional Branches

Branches that can fail without failing the workflow:

```ruby
branch :enhancement, agent: EnhancerAgent, optional: true
```

### Custom Input Per Branch

Transform input for specific branches:

```ruby
branch :translation, agent: TranslatorAgent, input: ->(opts) {
  { text: opts[:content], target_language: "es" }
}
```

## Workflow Configuration

### Fail Fast

By default, all branches run to completion. Enable `fail_fast` to abort remaining branches when a required branch fails:

```ruby
class MyParallel < RubyLLM::Agents::Workflow::Parallel
  fail_fast true  # Stop all branches on first required failure

  branch :critical, agent: CriticalAgent
  branch :optional, agent: OptionalAgent, optional: true
end
```

Note: Optional branches don't trigger fail_fast.

### Concurrency Limit

Limit the number of concurrent branches:

```ruby
class MyParallel < RubyLLM::Agents::Workflow::Parallel
  concurrency 3  # Max 3 branches running simultaneously

  branch :a, agent: AgentA
  branch :b, agent: AgentB
  branch :c, agent: AgentC
  branch :d, agent: AgentD  # Waits for a slot
end
```

### Timeout

Set a timeout for the entire workflow:

```ruby
class MyParallel < RubyLLM::Agents::Workflow::Parallel
  timeout 60.seconds
end
```

### Max Cost

Abort if accumulated cost exceeds threshold:

```ruby
class MyParallel < RubyLLM::Agents::Workflow::Parallel
  max_cost 1.00  # $1.00 maximum for all branches
end
```

## Input Transformation

### Using before_* Hooks

Transform input before a specific branch:

```ruby
class MyParallel < RubyLLM::Agents::Workflow::Parallel
  branch :sentiment, agent: SentimentAgent
  branch :summary,   agent: SummaryAgent

  def before_sentiment(options)
    { text: options[:content].downcase }
  end

  def before_summary(options)
    { text: options[:content], max_length: 100 }
  end
end
```

### Using input Lambda

```ruby
branch :translate, agent: TranslatorAgent, input: ->(opts) {
  { text: opts[:content], target: "spanish" }
}
```

## Result Aggregation

### Default Aggregation

By default, results are merged into a hash:

```ruby
result = MyParallel.call(text: "input")
result.content
# => {
#   sentiment: <SentimentAgent result>,
#   entities: <EntityAgent result>,
#   summary: <SummaryAgent result>
# }
```

### Custom Aggregation

Override `aggregate` for custom result processing:

```ruby
class MyParallel < RubyLLM::Agents::Workflow::Parallel
  branch :sentiment, agent: SentimentAgent
  branch :keywords,  agent: KeywordAgent

  def aggregate(results)
    {
      overall_score: calculate_score(results),
      tags: results[:keywords]&.content&.dig(:words) || [],
      mood: results[:sentiment]&.content&.dig(:label),
      confidence: average_confidence(results)
    }
  end

  private

  def calculate_score(results)
    # Custom scoring logic
    results[:sentiment]&.content&.dig(:score) || 0.0
  end

  def average_confidence(results)
    scores = results.values.filter_map { |r| r&.content&.dig(:confidence) }
    scores.any? ? scores.sum / scores.size : 0.0
  end
end
```

## Accessing Results

```ruby
result = MyParallel.call(text: "input")

# Aggregated result
result.content                    # Output from aggregate method

# Individual branch results
result.branches[:sentiment]       # Result object for :sentiment branch
result.branches[:sentiment].content
result.branches[:sentiment].total_cost

# Branch status
result.all_branches_successful?   # Boolean
result.failed_branches            # [:entities] - Array of failed branch names
result.successful_branches        # [:sentiment, :summary] - Array of successful

# Aggregate metrics
result.status                     # "success", "error", or "partial"
result.total_cost                 # Sum of all branch costs
result.total_tokens               # Sum of all branch tokens
result.duration_ms                # Total execution time
```

## Error Handling

### Fail Fast (Abort on Error)

```ruby
class MyParallel < RubyLLM::Agents::Workflow::Parallel
  fail_fast true

  branch :a, agent: AgentA  # If this fails, abort remaining
  branch :b, agent: AgentB
end
```

### Complete All (Default)

Continue all branches even if some fail:

```ruby
class MyParallel < RubyLLM::Agents::Workflow::Parallel
  fail_fast false  # Default

  branch :a, agent: AgentA
  branch :b, agent: AgentB
end

result = MyParallel.call(input: data)
result.failed_branches  # [:a] if AgentA failed
result.status           # "partial" or "error"
```

### Optional Branches

Optional branches don't affect workflow success:

```ruby
class MyParallel < RubyLLM::Agents::Workflow::Parallel
  branch :critical, agent: CriticalAgent
  branch :nice_to_have, agent: OptionalAgent, optional: true
end

# If nice_to_have fails, workflow still succeeds (if critical succeeds)
```

## Real-World Examples

### Content Analysis

```ruby
class ContentAnalyzer < RubyLLM::Agents::Workflow::Parallel
  version "1.0"
  timeout 30.seconds

  branch :sentiment,   agent: SentimentAgent
  branch :topics,      agent: TopicExtractor
  branch :entities,    agent: EntityRecognizer
  branch :readability, agent: ReadabilityScorer, optional: true

  def aggregate(results)
    {
      sentiment: results[:sentiment]&.content,
      topics: results[:topics]&.content&.dig(:topics) || [],
      entities: results[:entities]&.content || {},
      readability: results[:readability]&.content&.dig(:score)
    }
  end
end

result = ContentAnalyzer.call(text: article_content)
```

### Multi-Language Translation

```ruby
class MultiTranslator < RubyLLM::Agents::Workflow::Parallel
  version "1.0"
  concurrency 4  # Limit concurrent API calls

  branch :spanish,  agent: TranslatorAgent, input: ->(o) { o.merge(target: "es") }
  branch :french,   agent: TranslatorAgent, input: ->(o) { o.merge(target: "fr") }
  branch :german,   agent: TranslatorAgent, input: ->(o) { o.merge(target: "de") }
  branch :japanese, agent: TranslatorAgent, input: ->(o) { o.merge(target: "ja") }
end

translations = MultiTranslator.call(text: english_text)
translations.branches[:spanish].content  # Spanish translation
```

### Risk Assessment

```ruby
class RiskAssessment < RubyLLM::Agents::Workflow::Parallel
  version "1.0"
  fail_fast false  # Get all risk assessments even if one fails

  branch :financial,   agent: FinancialRiskAgent
  branch :operational, agent: OperationalRiskAgent
  branch :compliance,  agent: ComplianceRiskAgent

  def aggregate(results)
    risks = results.transform_values { |r| r&.content }

    {
      overall_risk: calculate_overall_risk(risks),
      breakdown: risks,
      recommendations: generate_recommendations(risks),
      assessed_at: Time.current
    }
  end

  private

  def calculate_overall_risk(risks)
    scores = risks.values.filter_map { |r| r&.dig(:score) }
    scores.any? ? scores.max : nil
  end

  def generate_recommendations(risks)
    risks.flat_map { |type, risk|
      risk&.dig(:recommendations) || []
    }.uniq
  end
end
```

### A/B Model Comparison

```ruby
class ModelComparison < RubyLLM::Agents::Workflow::Parallel
  version "1.0"

  branch :gpt4,   agent: GPT4Agent
  branch :claude, agent: ClaudeAgent
  branch :gemini, agent: GeminiAgent

  def aggregate(results)
    {
      responses: results.transform_values { |r| r&.content },
      costs: results.transform_values { |r| r&.total_cost },
      latencies: results.transform_values { |r| r&.duration_ms },
      winner: select_best(results)
    }
  end

  private

  def select_best(results)
    # Select based on cost/latency/quality tradeoffs
    results.min_by { |_, r| r&.total_cost || Float::INFINITY }&.first
  end
end
```

## Inheritance

Parallel workflows support inheritance:

```ruby
class BaseAnalyzer < RubyLLM::Agents::Workflow::Parallel
  version "1.0"
  timeout 30.seconds

  branch :sentiment, agent: SentimentAgent
end

class ExtendedAnalyzer < BaseAnalyzer
  # Inherits :sentiment branch
  branch :entities, agent: EntityAgent
  branch :summary,  agent: SummaryAgent
end
```

## Thread Safety

Branches run in separate threads. Ensure your agent code is thread-safe:

```ruby
class SafeAgent < ApplicationAgent
  def call
    # Avoid shared mutable state
    # Use thread-local storage if needed
    Thread.current[:context] = build_context
    super
  end
end
```

## Best Practices

### Independent Branches

Branches should be independent:

```ruby
# Good: Branches don't depend on each other
class GoodParallel < RubyLLM::Agents::Workflow::Parallel
  branch :sentiment, agent: SentimentAgent  # Independent
  branch :entities,  agent: EntityAgent     # Independent
  branch :keywords,  agent: KeywordAgent    # Independent
end

# Bad: Use Pipeline if branches depend on each other
```

### Appropriate Parallelism

```ruby
# Good: 2-5 concurrent branches
class GoodParallel < RubyLLM::Agents::Workflow::Parallel
  branch :a, agent: AgentA
  branch :b, agent: AgentB
  branch :c, agent: AgentC
end

# Consider limiting concurrency for many branches
class LimitedParallel < RubyLLM::Agents::Workflow::Parallel
  concurrency 3  # Prevent overwhelming API rate limits

  branch :a, agent: AgentA
  branch :b, agent: AgentB
  # ... many more branches
end
```

### Handle Partial Failures

```ruby
class RobustParallel < RubyLLM::Agents::Workflow::Parallel
  fail_fast false

  branch :critical,    agent: CriticalAgent
  branch :nice_to_have, agent: OptionalAgent, optional: true
end
```

### Monitor Branch Performance

```ruby
result = MyParallel.call(input: data)

slowest = result.branches.max_by { |_, b| b&.duration_ms || 0 }
puts "Slowest branch: #{slowest[0]} (#{slowest[1]&.duration_ms}ms)"

result.branches.each do |name, branch|
  if branch&.duration_ms && branch.duration_ms > 5000
    Rails.logger.warn("Slow branch: #{name} took #{branch.duration_ms}ms")
  end
end
```

## Related Pages

- [Workflows](Workflows) - Workflow overview
- [Pipeline Workflows](Pipeline-Workflows) - Sequential execution
- [Router Workflows](Router-Workflows) - Conditional dispatch
- [Examples](Examples) - More parallel examples
