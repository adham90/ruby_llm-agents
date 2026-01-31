<picture>
  <source media="(prefers-color-scheme: dark)" srcset="./logo_dark.png">
  <source media="(prefers-color-scheme: light)" srcset="./logo_light.png">
  <img alt="RubyLLM::Agents" src="./logo_light.png">
</picture>

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

## Show Me the Code

```ruby
# app/agents/search_intent_agent.rb
class SearchIntentAgent < ApplicationAgent
  model "gpt-4o"
  temperature 0.0

  param :query, required: true

  def user_prompt
    "Extract search intent from: #{query}"
  end

  schema do
    string :refined_query, description: "Cleaned search query"
    array :filters, of: :string, description: "Extracted filters"
  end
end

result = SearchIntentAgent.call(query: "red summer dress under $50")

result.content        # => { refined_query: "red dress", filters: ["color:red", "price:<50"] }
result.total_cost     # => 0.00025
result.total_tokens   # => 150
result.duration_ms    # => 850
```

```ruby
# Multi-turn conversations
result = ChatAgent.call(
  query: "What's my name?",
  messages: [
    { role: :user, content: "My name is Alice" },
    { role: :assistant, content: "Nice to meet you, Alice!" }
  ]
)
# => "Your name is Alice!"
```

```ruby
# Resilient agents with automatic retries and fallbacks
class ReliableAgent < ApplicationAgent
  model "gpt-4o"

  reliability do
    retries max: 3, backoff: :exponential
    fallback_models "gpt-4o-mini", "claude-3-5-sonnet"
    circuit_breaker errors: 10, within: 60, cooldown: 300
    total_timeout 30
  end

  param :query, required: true

  def user_prompt
    query
  end
end
```

```ruby
# Vector embeddings for semantic search and RAG
# app/agents/embedders/document_embedder.rb
module Embedders
  class DocumentEmbedder < ApplicationEmbedder
    model "text-embedding-3-small"
    dimensions 512
    cache_for 1.week
  end
end

result = Embedders::DocumentEmbedder.call(text: "Hello world")
result.vector       # => [0.123, -0.456, ...]
result.dimensions   # => 512

# Batch embedding
result = Embedders::DocumentEmbedder.call(texts: ["Hello", "World", "Ruby"])
result.vectors      # => [[...], [...], [...]]
```

```ruby
# Image generation, analysis, and pipelines
# app/agents/images/logo_generator.rb
module Images
  class LogoGenerator < ApplicationImageGenerator
    model "gpt-image-1"
    size "1024x1024"
    quality "hd"
    style "vivid"
    template "Professional logo design: {prompt}. Minimalist, scalable."
  end
end

result = Images::LogoGenerator.call(prompt: "tech startup logo")
result.url          # => "https://..."
result.save("logo.png")
```

```ruby
# Workflow orchestration - sequential, parallel, routing in one DSL
class OrderWorkflow < RubyLLM::Agents::Workflow
  description "End-to-end order processing"
  timeout 60.seconds
  max_cost 1.50

  input do
    required :order_id, String
    optional :priority, String, default: "normal"
  end

  step :validate, ValidatorAgent
  step :enrich,   EnricherAgent, input: -> { { data: validate.content } }

  parallel :analysis do
    step :sentiment, SentimentAgent, optional: true
    step :classify,  ClassifierAgent
  end

  step :handle, on: -> { classify.category } do |route|
    route.billing    BillingAgent
    route.technical  TechnicalAgent
    route.default    GeneralAgent
  end

  step :format, FormatterAgent, optional: true
end

result = OrderWorkflow.call(order_id: "123")
result.steps[:classify].content  # Individual step result
result.total_cost                # Sum of all steps
result.success?                  # true/false
```

## Features

| Feature | Description | Docs |
|---------|-------------|------|
| **Agent DSL** | Declarative configuration with model, temperature, parameters, description | [Agent DSL](https://github.com/adham90/ruby_llm-agents/wiki/Agent-DSL) |
| **Execution Tracking** | Automatic logging with token usage, cost analytics, and fallback tracking | [Tracking](https://github.com/adham90/ruby_llm-agents/wiki/Execution-Tracking) |
| **Cost Analytics** | Track spending by agent, model, tenant, and time period | [Analytics](https://github.com/adham90/ruby_llm-agents/wiki/Execution-Tracking) |
| **Reliability** | Automatic retries, model fallbacks, circuit breakers with block DSL | [Reliability](https://github.com/adham90/ruby_llm-agents/wiki/Reliability) |
| **Budget Controls** | Daily/monthly limits with hard and soft enforcement | [Budgets](https://github.com/adham90/ruby_llm-agents/wiki/Budget-Controls) |
| **Multi-Tenancy** | Per-tenant API keys, budgets, circuit breakers, and execution isolation | [Multi-Tenancy](https://github.com/adham90/ruby_llm-agents/wiki/Multi-Tenancy) |
| **Workflows** | Pipelines, parallel execution, conditional routers | [Workflows](https://github.com/adham90/ruby_llm-agents/wiki/Workflows) |
| **Async/Fiber** | Concurrent execution with Ruby fibers for high-throughput workloads | [Async](https://github.com/adham90/ruby_llm-agents/wiki/Async-Fiber) |
| **Dashboard** | Real-time Turbo-powered monitoring UI | [Dashboard](https://github.com/adham90/ruby_llm-agents/wiki/Dashboard) |
| **Streaming** | Real-time response streaming with TTFT tracking | [Streaming](https://github.com/adham90/ruby_llm-agents/wiki/Streaming) |
| **Conversation History** | Multi-turn conversations with message history | [Conversation History](https://github.com/adham90/ruby_llm-agents/wiki/Conversation-History) |
| **Attachments** | Images, PDFs, and multimodal support | [Attachments](https://github.com/adham90/ruby_llm-agents/wiki/Attachments) |
| **PII Redaction** | Automatic sensitive data protection | [Security](https://github.com/adham90/ruby_llm-agents/wiki/PII-Redaction) |
| **Content Moderation** | Input/output safety checks with OpenAI moderation API | [Moderation](https://github.com/adham90/ruby_llm-agents/wiki/Moderation) |
| **Embeddings** | Vector embeddings with batching, caching, and preprocessing | [Embeddings](https://github.com/adham90/ruby_llm-agents/wiki/Embeddings) |
| **Image Operations** | Generation, analysis, editing, pipelines with cost tracking | [Images](https://github.com/adham90/ruby_llm-agents/wiki/Image-Generation) |
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

### Generate an Agent

```bash
rails generate ruby_llm_agents:agent SearchIntent query:required
```

This creates `app/agents/search_intent_agent.rb` with the agent class ready to customize.

### Mount the Dashboard

```ruby
# config/routes.rb
mount RubyLLM::Agents::Engine => "/agents"
```

![RubyLLM Agents Dashboard](screenshot.png)

## Documentation

> **AI Agents:** For comprehensive documentation optimized for AI consumption, see [LLMS.txt](LLMS.txt)

> **Note:** Wiki content lives in the [`wiki/`](wiki/) folder. To sync changes to the [GitHub Wiki](https://github.com/adham90/ruby_llm-agents/wiki), run `./scripts/sync-wiki.sh`.

| Guide | Description |
|-------|-------------|
| [Getting Started](https://github.com/adham90/ruby_llm-agents/wiki/Getting-Started) | Installation, configuration, first agent |
| [Agent DSL](https://github.com/adham90/ruby_llm-agents/wiki/Agent-DSL) | All DSL options: model, temperature, params, caching, description |
| [Reliability](https://github.com/adham90/ruby_llm-agents/wiki/Reliability) | Retries, fallbacks, circuit breakers, timeouts, reliability block |
| [Workflows](https://github.com/adham90/ruby_llm-agents/wiki/Workflows) | Pipelines, parallel execution, routers |
| [Budget Controls](https://github.com/adham90/ruby_llm-agents/wiki/Budget-Controls) | Spending limits, alerts, enforcement |
| [Multi-Tenancy](https://github.com/adham90/ruby_llm-agents/wiki/Multi-Tenancy) | Per-tenant budgets, isolation, configuration |
| [Async/Fiber](https://github.com/adham90/ruby_llm-agents/wiki/Async-Fiber) | Concurrent execution with Ruby fibers |
| [Testing Agents](https://github.com/adham90/ruby_llm-agents/wiki/Testing-Agents) | RSpec patterns, mocking, dry_run mode |
| [Error Handling](https://github.com/adham90/ruby_llm-agents/wiki/Error-Handling) | Error types, recovery patterns |
| [Moderation](https://github.com/adham90/ruby_llm-agents/wiki/Moderation) | Content moderation for input/output safety |
| [Embeddings](https://github.com/adham90/ruby_llm-agents/wiki/Embeddings) | Vector embeddings, batching, caching, preprocessing |
| [Image Generation](https://github.com/adham90/ruby_llm-agents/wiki/Image-Generation) | Text-to-image, templates, content policy, cost tracking |
| [Dashboard](https://github.com/adham90/ruby_llm-agents/wiki/Dashboard) | Setup, authentication, analytics |
| [Production](https://github.com/adham90/ruby_llm-agents/wiki/Production-Deployment) | Deployment best practices, background jobs |
| [API Reference](https://github.com/adham90/ruby_llm-agents/wiki/API-Reference) | Complete class documentation |
| [Examples](https://github.com/adham90/ruby_llm-agents/wiki/Examples) | Real-world use cases and patterns |

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
