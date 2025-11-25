# RubyLLM::Agents

A Rails engine for building, managing, and monitoring LLM-powered agents using [RubyLLM](https://github.com/crmne/ruby_llm).

## Features

- **Agent DSL** - Declarative configuration for LLM agents (model, temperature, params, caching)
- **Execution Tracking** - Automatic logging of all agent executions with token usage and costs
- **Cost Analytics** - Track spending by agent, model, and time period
- **Mountable Dashboard** - Monitor agents with a beautiful Turbo-powered UI
- **Generators** - Quickly scaffold new agents

## Installation

Add to your Gemfile:

```ruby
gem "ruby_llm-agents"
```

Then run the install generator:

```bash
rails generate ruby_llm_agents:install
rails db:migrate
```

This will:
- Create the `ruby_llm_agents_executions` table
- Add an initializer at `config/initializers/ruby_llm_agents.rb`
- Create `app/agents/application_agent.rb`
- Mount the dashboard at `/agents`

## Usage

### Creating an Agent

Use the generator:

```bash
rails generate ruby_llm_agents:agent SearchIntent query:required limit:10
```

Or create manually:

```ruby
# app/agents/search_intent_agent.rb
class SearchIntentAgent < ApplicationAgent
  model "gemini-2.0-flash"
  temperature 0.0
  version "1.0"
  cache 1.hour

  param :query, required: true
  param :limit, default: 10

  private

  def system_prompt
    <<~PROMPT
      Parse search queries and extract structured filters.
      Return JSON matching the schema.
    PROMPT
  end

  def user_prompt
    query
  end

  def schema
    @schema ||= RubyLLM::Schema.create do
      string :refined_query
      array :filters, of: :string
    end
  end
end
```

### Calling an Agent

```ruby
# Basic call
result = SearchIntentAgent.call(query: "red summer dress under $50")

# Debug mode (no API call)
SearchIntentAgent.call(query: "test", dry_run: true)

# Skip cache
SearchIntentAgent.call(query: "test", skip_cache: true)
```

### Configuration DSL

```ruby
class MyAgent < ApplicationAgent
  model "gpt-4o"           # LLM model
  temperature 0.7           # Randomness (0.0-1.0)
  version "2.0"             # Version for cache keys
  timeout 30                # Seconds before timeout
  cache 1.hour              # Enable caching with TTL

  param :query, required: true       # Required parameter
  param :limit, default: 10          # Optional with default
  param :filters                     # Optional parameter
end
```

### Custom Metadata

Add custom data to execution logs:

```ruby
class MyAgent < ApplicationAgent
  param :user_id

  def execution_metadata
    { user_id: user_id, source: "api" }
  end
end
```

## Configuration

```ruby
# config/initializers/ruby_llm_agents.rb
RubyLLM::Agents.configure do |config|
  # Defaults for all agents
  config.default_model = "gemini-2.0-flash"
  config.default_temperature = 0.0
  config.default_timeout = 60

  # Caching
  config.cache_store = Rails.cache

  # Execution logging
  config.async_logging = true          # Use background job
  config.retention_period = 30.days    # For cleanup tasks

  # Anomaly detection (logged as warnings)
  config.anomaly_cost_threshold = 5.00        # dollars
  config.anomaly_duration_threshold = 10_000  # milliseconds

  # Dashboard authentication
  config.dashboard_auth = ->(controller) { controller.current_user&.admin? }
end
```

## Dashboard

Mount the dashboard in your routes:

```ruby
# config/routes.rb
mount RubyLLM::Agents::Engine => "/agents"
```

The dashboard provides:
- **Overview** - Today's stats, success rate, costs, trends
- **Executions** - Filterable list of all agent calls
- **Execution Detail** - Full prompts, response, token breakdown, costs

## Analytics

Query execution data programmatically:

```ruby
# Daily report
RubyLLM::Agents::Execution.daily_report

# Cost breakdown by agent
RubyLLM::Agents::Execution.cost_by_agent(period: :this_week)

# Stats for specific agent
RubyLLM::Agents::Execution.stats_for("SearchIntentAgent", period: :today)

# Compare versions
RubyLLM::Agents::Execution.compare_versions(
  "SearchIntentAgent", "1.0", "2.0", period: :this_week
)

# Trend analysis
RubyLLM::Agents::Execution.trend_analysis(agent_type: "SearchIntentAgent", days: 7)
```

### Scopes

```ruby
RubyLLM::Agents::Execution.today
RubyLLM::Agents::Execution.this_week
RubyLLM::Agents::Execution.by_agent("SearchIntentAgent")
RubyLLM::Agents::Execution.successful
RubyLLM::Agents::Execution.failed
RubyLLM::Agents::Execution.expensive(1.00)  # cost > $1
RubyLLM::Agents::Execution.slow(5000)       # duration > 5s
```

## Development

After checking out the repo:

```bash
bin/setup
bundle exec rake spec
```

## Contributing

Bug reports and pull requests are welcome on GitHub.

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).
