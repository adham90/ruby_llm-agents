# Parallel Workflows

Execute multiple agents concurrently and combine their results.

## Defining a Parallel Workflow

Create a parallel workflow by inheriting from `RubyLLM::Agents::Workflow::Parallel`:

```ruby
class LLM::ReviewAnalyzer < RubyLLM::Agents::Workflow::Parallel
  version "1.0"
  timeout 30.seconds
  max_cost 0.50

  branch :sentiment, agent: LLM::SentimentAgent
  branch :entities,  agent: LLM::EntityAgent
  branch :summary,   agent: LLM::SummaryAgent
end

result = LLM::ReviewAnalyzer.call(text: "analyze this content")
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
branch :enhancement, agent: LLM::EnhancerAgent, optional: true
```

### Custom Input Per Branch

Transform input for specific branches:

```ruby
branch :translation, agent: LLM::TranslatorAgent, input: ->(opts) {
  { text: opts[:content], target_language: "es" }
}
```

## Workflow Configuration

### Fail Fast

By default, all branches run to completion. Enable `fail_fast` to abort remaining branches when a required branch fails:

```ruby
class LLM::MyParallel < RubyLLM::Agents::Workflow::Parallel
  fail_fast true  # Stop all branches on first required failure

  branch :critical, agent: LLM::CriticalAgent
  branch :optional, agent: LLM::OptionalAgent, optional: true
end
```

Note: Optional branches don't trigger fail_fast.

### Concurrency Limit

Limit the number of concurrent branches:

```ruby
class LLM::MyParallel < RubyLLM::Agents::Workflow::Parallel
  concurrency 3  # Max 3 branches running simultaneously

  branch :a, agent: LLM::AgentA
  branch :b, agent: LLM::AgentB
  branch :c, agent: LLM::AgentC
  branch :d, agent: LLM::AgentD  # Waits for a slot
end
```

### Timeout

Set a timeout for the entire workflow:

```ruby
class LLM::MyParallel < RubyLLM::Agents::Workflow::Parallel
  timeout 60.seconds
end
```

### Max Cost

Abort if accumulated cost exceeds threshold:

```ruby
class LLM::MyParallel < RubyLLM::Agents::Workflow::Parallel
  max_cost 1.00  # $1.00 maximum for all branches
end
```

## Input Transformation

### Using before_* Hooks

Transform input before a specific branch:

```ruby
class LLM::MyParallel < RubyLLM::Agents::Workflow::Parallel
  branch :sentiment, agent: LLM::SentimentAgent
  branch :summary,   agent: LLM::SummaryAgent

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
branch :translate, agent: LLM::TranslatorAgent, input: ->(opts) {
  { text: opts[:content], target: "spanish" }
}
```

## Result Aggregation

### Default Aggregation

By default, results are merged into a hash:

```ruby
result = LLM::MyParallel.call(text: "input")
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
class LLM::MyParallel < RubyLLM::Agents::Workflow::Parallel
  branch :sentiment, agent: LLM::SentimentAgent
  branch :keywords,  agent: LLM::KeywordAgent

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
result = LLM::MyParallel.call(text: "input")

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
class LLM::MyParallel < RubyLLM::Agents::Workflow::Parallel
  fail_fast true

  branch :a, agent: LLM::AgentA  # If this fails, abort remaining
  branch :b, agent: LLM::AgentB
end
```

### Complete All (Default)

Continue all branches even if some fail:

```ruby
class LLM::MyParallel < RubyLLM::Agents::Workflow::Parallel
  fail_fast false  # Default

  branch :a, agent: LLM::AgentA
  branch :b, agent: LLM::AgentB
end

result = LLM::MyParallel.call(input: data)
result.failed_branches  # [:a] if AgentA failed
result.status           # "partial" or "error"
```

### Optional Branches

Optional branches don't affect workflow success:

```ruby
class LLM::MyParallel < RubyLLM::Agents::Workflow::Parallel
  branch :critical, agent: LLM::CriticalAgent
  branch :nice_to_have, agent: LLM::OptionalAgent, optional: true
end

# If nice_to_have fails, workflow still succeeds (if critical succeeds)
```

## Real-World Examples

### Content Analysis

```ruby
class LLM::ContentAnalyzer < RubyLLM::Agents::Workflow::Parallel
  version "1.0"
  timeout 30.seconds

  branch :sentiment,   agent: LLM::SentimentAgent
  branch :topics,      agent: LLM::TopicExtractor
  branch :entities,    agent: LLM::EntityRecognizer
  branch :readability, agent: LLM::ReadabilityScorer, optional: true

  def aggregate(results)
    {
      sentiment: results[:sentiment]&.content,
      topics: results[:topics]&.content&.dig(:topics) || [],
      entities: results[:entities]&.content || {},
      readability: results[:readability]&.content&.dig(:score)
    }
  end
end

result = LLM::ContentAnalyzer.call(text: article_content)
```

### Multi-Language Translation

```ruby
class LLM::MultiTranslator < RubyLLM::Agents::Workflow::Parallel
  version "1.0"
  concurrency 4  # Limit concurrent API calls

  branch :spanish,  agent: LLM::TranslatorAgent, input: ->(o) { o.merge(target: "es") }
  branch :french,   agent: LLM::TranslatorAgent, input: ->(o) { o.merge(target: "fr") }
  branch :german,   agent: LLM::TranslatorAgent, input: ->(o) { o.merge(target: "de") }
  branch :japanese, agent: LLM::TranslatorAgent, input: ->(o) { o.merge(target: "ja") }
end

translations = LLM::MultiTranslator.call(text: english_text)
translations.branches[:spanish].content  # Spanish translation
```

### Risk Assessment

```ruby
class LLM::RiskAssessment < RubyLLM::Agents::Workflow::Parallel
  version "1.0"
  fail_fast false  # Get all risk assessments even if one fails

  branch :financial,   agent: LLM::FinancialRiskAgent
  branch :operational, agent: LLM::OperationalRiskAgent
  branch :compliance,  agent: LLM::ComplianceRiskAgent

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
class LLM::ModelComparison < RubyLLM::Agents::Workflow::Parallel
  version "1.0"

  branch :gpt4,   agent: LLM::GPT4Agent
  branch :claude, agent: LLM::ClaudeAgent
  branch :gemini, agent: LLM::GeminiAgent

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
class LLM::BaseAnalyzer < RubyLLM::Agents::Workflow::Parallel
  version "1.0"
  timeout 30.seconds

  branch :sentiment, agent: LLM::SentimentAgent
end

class LLM::ExtendedAnalyzer < LLM::BaseAnalyzer
  # Inherits :sentiment branch
  branch :entities, agent: LLM::EntityAgent
  branch :summary,  agent: LLM::SummaryAgent
end
```

## Thread Safety

Branches run in separate threads. Ensure your agent code is thread-safe:

```ruby
module LLM
  class SafeAgent < ApplicationAgent
    def call
      # Avoid shared mutable state
      # Use thread-local storage if needed
      Thread.current[:context] = build_context
      super
    end
  end
end
```

## Best Practices

### Independent Branches

Branches should be independent:

```ruby
# Good: Branches don't depend on each other
class LLM::GoodParallel < RubyLLM::Agents::Workflow::Parallel
  branch :sentiment, agent: LLM::SentimentAgent  # Independent
  branch :entities,  agent: LLM::EntityAgent     # Independent
  branch :keywords,  agent: LLM::KeywordAgent    # Independent
end

# Bad: Use Pipeline if branches depend on each other
```

### Appropriate Parallelism

```ruby
# Good: 2-5 concurrent branches
class LLM::GoodParallel < RubyLLM::Agents::Workflow::Parallel
  branch :a, agent: LLM::AgentA
  branch :b, agent: LLM::AgentB
  branch :c, agent: LLM::AgentC
end

# Consider limiting concurrency for many branches
class LLM::LimitedParallel < RubyLLM::Agents::Workflow::Parallel
  concurrency 3  # Prevent overwhelming API rate limits

  branch :a, agent: LLM::AgentA
  branch :b, agent: LLM::AgentB
  # ... many more branches
end
```

### Handle Partial Failures

```ruby
class LLM::RobustParallel < RubyLLM::Agents::Workflow::Parallel
  fail_fast false

  branch :critical,    agent: LLM::CriticalAgent
  branch :nice_to_have, agent: LLM::OptionalAgent, optional: true
end
```

### Monitor Branch Performance

```ruby
result = LLM::MyParallel.call(input: data)

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
