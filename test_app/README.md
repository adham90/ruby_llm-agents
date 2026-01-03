# Ruby LLM Agents - Test Application

This is a reference Rails application for testing and demonstrating the `ruby_llm-agents` gem.
Use it for manual testing of generators, running the dashboard, and as a reference for example code.

## Quick Start

```bash
cd test_app
bundle install
bin/rails db:setup
bin/rails server
```

Then visit http://localhost:3000/agents to see the dashboard.

## Directory Structure

```
app/
  agents/           # Example agent implementations
    application_agent.rb    # Base agent class
    extractor_agent.rb      # Pipeline: extraction step
    classifier_agent.rb     # Pipeline: classification step
    formatter_agent.rb      # Pipeline: formatting step
    sentiment_agent.rb      # Parallel: sentiment analysis
    keyword_agent.rb        # Parallel: keyword extraction
    summary_agent.rb        # Parallel: summarization
    billing_agent.rb        # Router: billing support
    technical_agent.rb      # Router: technical support
    general_agent.rb        # Router: general support

  workflows/        # Example workflow implementations
    content_pipeline.rb     # Sequential pipeline workflow
    content_analyzer.rb     # Parallel execution workflow
    support_router.rb       # Conditional routing workflow

config/
  initializers/
    ruby_llm_agents.rb      # Gem configuration
```

## Testing Generators

```bash
# Generate a new agent
bin/rails generate ruby_llm_agents:agent MyAgent query:required limit:10

# Generate an agent with options
bin/rails generate ruby_llm_agents:agent SearchIntent query:required --model=gpt-4o --temperature=0.7 --cache=1.hour

# Run the upgrade generator (adds new columns to existing installations)
bin/rails generate ruby_llm_agents:upgrade

# Add multi-tenancy support
bin/rails generate ruby_llm_agents:multi_tenancy
```

## Example Usage (Rails Console)

```bash
bin/rails console
```

### Pipeline Workflow (Sequential Steps)

```ruby
# Process content through extract -> classify -> format steps
result = ContentPipeline.call(text: "Your content here")
result.steps[:extract].content   # Extracted data
result.steps[:classify].content  # Classification result
result.total_cost                # Total cost of all steps
```

### Parallel Workflow (Concurrent Execution)

```ruby
# Analyze content from multiple perspectives concurrently
result = ContentAnalyzer.call(text: "Your content here")
result.branches[:sentiment].content  # Sentiment analysis
result.branches[:keywords].content   # Keyword extraction
result.branches[:summary].content    # Summary
result.total_cost                    # Combined cost
```

### Router Workflow (Conditional Dispatch)

```ruby
# Route customer messages to specialized agents based on intent
result = SupportRouter.call(message: "I was charged twice")
result.routed_to         # :billing, :technical, or :default
result.classification    # Classification details
result.content           # Response from routed agent
```

## Relationship to Parent Gem

This test_app references the parent gem via `gem "ruby_llm-agents", path: ".."` in the Gemfile.
Any changes you make to the gem will be reflected here after restarting the Rails server.

## Notes

- This app uses SQLite for simplicity
- The `spec/dummy` app in the parent gem is separate and used for RSpec tests
- Configuration is in `config/initializers/ruby_llm_agents.rb`
