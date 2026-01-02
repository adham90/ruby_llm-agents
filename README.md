# RubyLLM::Agents

> **Production-ready Rails engine for building, managing, and monitoring LLM-powered AI agents**

[![Gem Version](https://badge.fury.io/rb/ruby_llm-agents.svg)](https://rubygems.org/gems/ruby_llm-agents)
[![Ruby](https://img.shields.io/badge/ruby-%3E%3D%203.1-ruby.svg)](https://www.ruby-lang.org)
[![Rails](https://img.shields.io/badge/rails-%3E%3D%207.0-red.svg)](https://rubyonrails.org)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Documentation](https://img.shields.io/badge/docs-wiki-blue.svg)](https://github.com/adham90/ruby_llm-agents/wiki)

Build intelligent AI agents in Ruby with a clean DSL, automatic execution tracking, cost analytics, budget controls, and a beautiful real-time dashboard. Supports **OpenAI GPT-4**, **Anthropic Claude**, **Google Gemini**, and more through [RubyLLM](https://github.com/crmne/ruby_llm).

## Why RubyLLM::Agents?

- **Rails-Native** - Seamlessly integrates with your Rails app: models, jobs, caching, and Hotwire
- **Production-Ready** - Built-in retries, model fallbacks, circuit breakers, and budget limits
- **Full Observability** - Track every execution with costs, tokens, duration, and errors
- **Workflow Orchestration** - Compose agents into pipelines, parallel tasks, and conditional routers
- **Zero Lock-in** - Works with any LLM provider supported by RubyLLM

## Features

| Feature | Description | Docs |
|---------|-------------|------|
| **Agent DSL** | Declarative configuration with model, temperature, parameters | [Agent DSL](https://github.com/adham90/ruby_llm-agents/wiki/Agent-DSL) |
| **Execution Tracking** | Automatic logging with token usage and cost analytics | [Tracking](https://github.com/adham90/ruby_llm-agents/wiki/Execution-Tracking) |
| **Cost Analytics** | Track spending by agent, model, and time period | [Analytics](https://github.com/adham90/ruby_llm-agents/wiki/Execution-Tracking) |
| **Reliability** | Automatic retries, model fallbacks, circuit breakers | [Reliability](https://github.com/adham90/ruby_llm-agents/wiki/Reliability) |
| **Budget Controls** | Daily/monthly limits with hard and soft enforcement | [Budgets](https://github.com/adham90/ruby_llm-agents/wiki/Budget-Controls) |
| **Workflows** | Pipelines, parallel execution, conditional routers | [Workflows](https://github.com/adham90/ruby_llm-agents/wiki/Workflows) |
| **Dashboard** | Real-time Turbo-powered monitoring UI | [Dashboard](https://github.com/adham90/ruby_llm-agents/wiki/Dashboard) |
| **Streaming** | Real-time response streaming with TTFT tracking | [Streaming](https://github.com/adham90/ruby_llm-agents/wiki/Streaming) |
| **Attachments** | Images, PDFs, and multimodal support | [Attachments](https://github.com/adham90/ruby_llm-agents/wiki/Attachments) |
| **PII Redaction** | Automatic sensitive data protection | [Security](https://github.com/adham90/ruby_llm-agents/wiki/PII-Redaction) |
| **Alerts** | Slack, webhook, and custom notifications | [Alerts](https://github.com/adham90/ruby_llm-agents/wiki/Alerts) |

## Quick Start

### Installation

```ruby
# Gemfile
gem "ruby_llm-agents"
```

```bash
bundle install
rails generate ruby_llm_agents:install
rails db:migrate
```

### Configure API Keys

```bash
# .env
OPENAI_API_KEY=sk-...
ANTHROPIC_API_KEY=sk-ant-...
GOOGLE_API_KEY=...
```

### Create Your First Agent

```bash
rails generate ruby_llm_agents:agent SearchIntent query:required
```

```ruby
# app/agents/search_intent_agent.rb
class SearchIntentAgent < ApplicationAgent
  model "gpt-4o"
  temperature 0.0

  param :query, required: true

  def user_prompt
    "Extract search intent from: #{query}"
  end

  def schema
    @schema ||= RubyLLM::Schema.create do
      string :refined_query, description: "Cleaned search query"
      array :filters, of: :string, description: "Extracted filters"
    end
  end
end
```

### Call the Agent

```ruby
result = SearchIntentAgent.call(query: "red summer dress under $50")

result.content        # => { refined_query: "red dress", filters: ["color:red", "price:<50"] }
result.total_cost     # => 0.00025
result.total_tokens   # => 150
result.duration_ms    # => 850
```

## Documentation

| Guide | Description |
|-------|-------------|
| [Getting Started](https://github.com/adham90/ruby_llm-agents/wiki/Getting-Started) | Installation, configuration, first agent |
| [Agent DSL](https://github.com/adham90/ruby_llm-agents/wiki/Agent-DSL) | All DSL options: model, temperature, params, caching |
| [Reliability](https://github.com/adham90/ruby_llm-agents/wiki/Reliability) | Retries, fallbacks, circuit breakers, timeouts |
| [Workflows](https://github.com/adham90/ruby_llm-agents/wiki/Workflows) | Pipelines, parallel execution, routers |
| [Budget Controls](https://github.com/adham90/ruby_llm-agents/wiki/Budget-Controls) | Spending limits, alerts, enforcement |
| [Dashboard](https://github.com/adham90/ruby_llm-agents/wiki/Dashboard) | Setup, authentication, analytics |
| [Production](https://github.com/adham90/ruby_llm-agents/wiki/Production-Deployment) | Deployment best practices, background jobs |
| [API Reference](https://github.com/adham90/ruby_llm-agents/wiki/API-Reference) | Complete class documentation |
| [Examples](https://github.com/adham90/ruby_llm-agents/wiki/Examples) | Real-world use cases and patterns |

## Reliability Features

Build resilient agents with built-in fault tolerance:

```ruby
class ReliableAgent < ApplicationAgent
  model "gpt-4o"

  # Retry on failures with exponential backoff
  retries max: 3, backoff: :exponential

  # Fall back to alternative models
  fallback_models "gpt-4o-mini", "claude-3-5-sonnet"

  # Prevent cascading failures
  circuit_breaker errors: 10, within: 60, cooldown: 300

  # Maximum time for all attempts
  total_timeout 30

  param :query, required: true

  def user_prompt
    query
  end
end
```

## Workflow Orchestration

Compose agents into complex workflows:

```ruby
# Sequential pipeline
workflow = RubyLLM::Agents::Workflow.pipeline(
  ClassifierAgent,
  EnricherAgent,
  FormatterAgent
)
result = workflow.call(input: data)

# Parallel execution
workflow = RubyLLM::Agents::Workflow.parallel(
  sentiment: SentimentAgent,
  entities: EntityAgent,
  summary: SummaryAgent
)
result = workflow.call(text: content)

# Conditional routing
workflow = RubyLLM::Agents::Workflow.router(
  classifier: IntentClassifier,
  routes: {
    "support" => SupportAgent,
    "sales" => SalesAgent,
    "general" => GeneralAgent
  }
)
result = workflow.call(message: user_input)
```

## Cost & Budget Controls

Track and limit LLM spending:

```ruby
# config/initializers/ruby_llm_agents.rb
RubyLLM::Agents.configure do |config|
  config.budgets = {
    global_daily: 100.0,      # $100/day limit
    global_monthly: 2000.0,   # $2000/month limit
    per_agent_daily: {
      "ExpensiveAgent" => 50.0
    },
    enforcement: :hard        # Block when exceeded
  }

  config.alerts = {
    on_events: [:budget_soft_cap, :budget_hard_cap, :breaker_open],
    slack_webhook_url: ENV['SLACK_WEBHOOK_URL']
  }
end
```

## Dashboard

Mount the real-time monitoring dashboard:

```ruby
# config/routes.rb
mount RubyLLM::Agents::Engine => "/agents"
```

![RubyLLM Agents Dashboard](screenshot.png)

Features:
- Execution history with filtering and search
- Cost analytics by agent, model, and time period
- Performance trends and charts
- Token usage breakdowns
- Error tracking and debugging

## Requirements

- **Ruby** >= 3.1.0
- **Rails** >= 7.0
- **RubyLLM** >= 1.0

## Contributing

Bug reports and pull requests are welcome at [GitHub](https://github.com/adham90/ruby_llm-agents).

1. Fork the repository
2. Create your feature branch (`git checkout -b my-feature`)
3. Commit your changes (`git commit -am 'Add feature'`)
4. Push to the branch (`git push origin my-feature`)
5. Create a Pull Request

## License

The gem is available as open source under the [MIT License](https://opensource.org/licenses/MIT).

## Credits

Built with love by [Adham Eldeeb](https://github.com/adham90)

Powered by [RubyLLM](https://github.com/crmne/ruby_llm)
