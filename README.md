# RubyLLM::Agents

[![Gem Version](https://badge.fury.io/rb/ruby_llm-agents.svg)](https://badge.fury.io/rb/ruby_llm-agents)

A powerful Rails engine for building, managing, and monitoring LLM-powered agents using [RubyLLM](https://github.com/crmne/ruby_llm).

## Features

- **🤖 Agent DSL** - Declarative configuration for LLM agents with model, temperature, parameters, and caching
- **📊 Execution Tracking** - Automatic logging of all agent executions with token usage and costs
- **💰 Cost Analytics** - Track spending by agent, model, and time period with detailed breakdowns
- **📈 Dashboard UI** - Beautiful Turbo-powered dashboard for monitoring agents
- **⚡ Performance** - Built-in caching with configurable TTL and cache key versioning
- **🛠️ Generators** - Quickly scaffold new agents with customizable templates
- **🔍 Anomaly Detection** - Automatic warnings for unusual cost or duration patterns
- **🎯 Type Safety** - Structured output with RubyLLM::Schema integration
- **⚡ Real-time Streaming** - Stream LLM responses with time-to-first-token tracking
- **📎 Attachments** - Send images, PDFs, and files to vision-capable models
- **📋 Rich Results** - Access token counts, costs, timing, and model info from every execution
- **🔄 Reliability** - Automatic retries, model fallbacks, and circuit breakers for resilient agents
- **💵 Budget Controls** - Daily/monthly spending limits with hard and soft enforcement
- **🔔 Alerts** - Slack, webhook, and custom notifications for budget and circuit breaker events
- **🔒 PII Redaction** - Automatic sanitization of sensitive data in execution logs

## Requirements

- **Ruby**: >= 3.1.0
- **Rails**: >= 7.0

## Dependencies

The gem includes the following runtime dependencies:

```ruby
gem "rails", ">= 7.0"
gem "ruby_llm", ">= 1.0"          # LLM client library
gem "turbo-rails", ">= 1.0"       # Hotwire Turbo for real-time UI
gem "stimulus-rails", ">= 1.0"    # Hotwire Stimulus for JavaScript
gem "chartkick", ">= 5.0"         # Beautiful charts for analytics
```

## Installation

### 1. Add to your Gemfile

```ruby
gem "ruby_llm-agents"
```

Then run:

```bash
bundle install
```

### 2. Run the install generator

```bash
rails generate ruby_llm_agents:install
rails db:migrate
```

This will:

- Create the `ruby_llm_agents_executions` table for execution tracking
- Add an initializer at `config/initializers/ruby_llm_agents.rb`
- Create `app/agents/application_agent.rb` as the base class for your agents
- Mount the dashboard at `/agents` in your routes

### 3. Configure your LLM provider

Set up your API keys for the LLM providers you want to use:

```bash
# .env or Rails credentials
GOOGLE_API_KEY=your_key_here
OPENAI_API_KEY=your_key_here
ANTHROPIC_API_KEY=your_key_here
```

## Quick Start

### Creating Your First Agent

Use the generator to create a new agent:

```bash
rails generate ruby_llm_agents:agent SearchIntent query:required limit:10
```

This creates `app/agents/search_intent_agent.rb`:

```ruby
class SearchIntentAgent < ApplicationAgent
  model "gemini-2.0-flash"
  temperature 0.0
  version "1.0"

  param :query, required: true
  param :limit, default: 10

  private

  def system_prompt
    <<~PROMPT
      You are a search assistant that parses user queries
      and extracts structured search filters.
    PROMPT
  end

  def user_prompt
    query
  end

  def schema
    @schema ||= RubyLLM::Schema.create do
      string :refined_query, description: "Cleaned and refined search query"
      array :filters, of: :string, description: "Extracted search filters"
      integer :category_id, description: "Detected product category", nullable: true
    end
  end
end
```

### Calling the Agent

```ruby
# Basic call
result = SearchIntentAgent.call(query: "red summer dress under $50")
# => {
#   refined_query: "red summer dress",
#   filters: ["color:red", "season:summer", "price:<50"],
#   category_id: 42
# }

# With custom parameters
result = SearchIntentAgent.call(
  query: "blue jeans",
  limit: 20
)

# Debug mode (no API call, shows prompt)
SearchIntentAgent.call(query: "test", dry_run: true)
# => {
#   dry_run: true,
#   agent: "SearchIntentAgent",
#   model: "gemini-2.0-flash",
#   temperature: 0.0,
#   system_prompt: "You are a search assistant...",
#   user_prompt: "test",
#   schema: "RubyLLM::Schema"
# }

# Skip cache
SearchIntentAgent.call(query: "test", skip_cache: true)
```

### Streaming Responses

Enable real-time streaming to receive LLM responses as they're generated:

```ruby
class StreamingAgent < ApplicationAgent
  model "gpt-4o"
  streaming true  # Enable streaming for this agent

  param :prompt, required: true

  def user_prompt
    prompt
  end
end
```

#### Using Streaming with a Block

```ruby
# Stream responses in real-time
StreamingAgent.call(prompt: "Write a story") do |chunk|
  print chunk  # Process each chunk as it arrives
end
```

#### HTTP Streaming with ActionController::Live

```ruby
class StreamingController < ApplicationController
  include ActionController::Live

  def stream_response
    response.headers['Content-Type'] = 'text/event-stream'
    response.headers['Cache-Control'] = 'no-cache'

    StreamingAgent.call(prompt: params[:prompt]) do |chunk|
      response.stream.write "data: #{chunk}\n\n"
    end
  ensure
    response.stream.close
  end
end
```

#### Time-to-First-Token Tracking

Streaming executions automatically track latency metrics:

```ruby
execution = RubyLLM::Agents::Execution.last
execution.streaming?              # => true
execution.time_to_first_token_ms  # => 245 (milliseconds to first chunk)
```

#### Global Streaming Configuration

Enable streaming by default for all agents:

```ruby
# config/initializers/ruby_llm_agents.rb
RubyLLM::Agents.configure do |config|
  config.default_streaming = true
end
```

### Attachments (Vision & Multimodal)

Send images, PDFs, and other files to vision-capable models using the `with:` option:

```ruby
class VisionAgent < ApplicationAgent
  model "gpt-4o"  # Use a vision-capable model
  param :question, required: true

  def user_prompt
    question
  end
end
```

#### Single Attachment

```ruby
# Local file
VisionAgent.call(question: "Describe this image", with: "photo.jpg")

# URL
VisionAgent.call(question: "What architecture is shown?", with: "https://example.com/building.jpg")
```

#### Multiple Attachments

```ruby
VisionAgent.call(
  question: "Compare these two screenshots",
  with: ["screenshot_v1.png", "screenshot_v2.png"]
)
```

#### Supported File Types

RubyLLM automatically detects file types:

- **Images:** `.jpg`, `.jpeg`, `.png`, `.gif`, `.webp`, `.bmp`
- **Videos:** `.mp4`, `.mov`, `.avi`, `.webm`
- **Audio:** `.mp3`, `.wav`, `.m4a`, `.ogg`, `.flac`
- **Documents:** `.pdf`, `.txt`, `.md`, `.csv`, `.json`, `.xml`
- **Code:** `.rb`, `.py`, `.js`, `.html`, `.css`, and many others

#### Debug Mode with Attachments

```ruby
VisionAgent.call(question: "test", with: "image.png", dry_run: true)
# => { ..., attachments: "image.png", ... }
```

### Execution Results

Every agent call returns a `Result` object with full execution metadata:

```ruby
result = SearchAgent.call(query: "red dress")

# Access the processed response
result.content            # => { refined_query: "red dress", ... }

# Token usage
result.input_tokens       # => 150
result.output_tokens      # => 50
result.total_tokens       # => 200
result.cached_tokens      # => 0

# Cost calculation
result.input_cost         # => 0.000150
result.output_cost        # => 0.000100
result.total_cost         # => 0.000250

# Model info
result.model_id           # => "gpt-4o"
result.chosen_model_id    # => "gpt-4o" (may differ if fallback used)
result.temperature        # => 0.0

# Timing
result.duration_ms        # => 1234
result.started_at         # => 2025-11-27 10:30:00 UTC
result.completed_at       # => 2025-11-27 10:30:01 UTC
result.time_to_first_token_ms # => 245 (streaming only)

# Status
result.finish_reason      # => "stop", "length", "tool_calls", etc.
result.streaming?         # => false
result.success?           # => true
result.truncated?         # => false (true if hit max_tokens)

# Reliability info
result.attempts_count     # => 1
result.used_fallback?     # => false
```

#### Backward Compatibility

The Result object delegates hash methods to content, so existing code continues to work:

```ruby
# Old style (still works)
result[:refined_query]
result.dig(:nested, :key)

# New style (access metadata)
result.content[:refined_query]
result.total_cost
```

#### Full Metadata Hash

```ruby
result.to_h
# => {
#   content: { refined_query: "red dress", ... },
#   input_tokens: 150,
#   output_tokens: 50,
#   total_tokens: 200,
#   cached_tokens: 0,
#   input_cost: 0.000150,
#   output_cost: 0.000100,
#   total_cost: 0.000250,
#   model_id: "gpt-4o",
#   chosen_model_id: "gpt-4o",
#   temperature: 0.0,
#   duration_ms: 1234,
#   finish_reason: "stop",
#   streaming: false,
#   ...
# }
```

## Usage Guide

### Agent DSL

#### Model Configuration

```ruby
class MyAgent < ApplicationAgent
  # LLM model to use
  model "gpt-4o"                  # OpenAI GPT-4
  # model "claude-3-5-sonnet"    # Anthropic Claude
  # model "gemini-2.0-flash"     # Google Gemini (default)

  # Randomness (0.0 = deterministic, 1.0 = creative)
  temperature 0.7

  # Version for cache key generation
  version "2.0"

  # Request timeout in seconds
  timeout 30

  # Enable caching with TTL
  cache 1.hour
end
```

#### Parameter Definition

```ruby
class ProductSearchAgent < ApplicationAgent
  # Required parameter - raises ArgumentError if not provided
  param :query, required: true

  # Optional parameter with default value
  param :limit, default: 10

  # Optional parameter (no default)
  param :filters

  # Multiple required parameters
  param :user_id, required: true
  param :session_id, required: true
end
```

#### Prompt Methods

```ruby
class ContentGeneratorAgent < ApplicationAgent
  param :topic, required: true
  param :tone, default: "professional"
  param :word_count, default: 500

  private

  # System prompt (optional) - sets the AI's role and instructions
  def system_prompt
    <<~PROMPT
      You are a professional content writer specializing in #{topic}.
      Write in a #{tone} tone.
    PROMPT
  end

  # User prompt (required) - the main request to the AI
  def user_prompt
    <<~PROMPT
      Write a #{word_count}-word article about: #{topic}

      Requirements:
      - Clear structure with introduction, body, and conclusion
      - Use examples and data where relevant
      - Maintain a #{tone} tone throughout
    PROMPT
  end
end
```

#### Structured Output with Schema

```ruby
class EmailClassifierAgent < ApplicationAgent
  param :email_content, required: true

  private

  def system_prompt
    "You are an email classification system. Analyze emails and categorize them."
  end

  def user_prompt
    email_content
  end

  def schema
    @schema ||= RubyLLM::Schema.create do
      string :category,
             enum: ["urgent", "important", "spam", "newsletter", "personal"],
             description: "Email category"

      number :priority,
             description: "Priority score from 0 to 10"

      array :tags,
            of: :string,
            description: "Relevant tags for the email"

      boolean :requires_response,
              description: "Whether the email requires a response"

      object :sender_info do
        string :name, nullable: true
        string :company, nullable: true
        boolean :is_known_contact
      end
    end
  end
end
```

#### Response Processing

```ruby
class DataExtractorAgent < ApplicationAgent
  param :text, required: true

  private

  def user_prompt
    "Extract key information from: #{text}"
  end

  def schema
    @schema ||= RubyLLM::Schema.create do
      string :summary
      array :entities, of: :string
    end
  end

  # Post-process the LLM response
  def process_response(response)
    result = super(response)

    # Add custom processing
    result[:entities] = result[:entities].map(&:downcase).uniq
    result[:word_count] = result[:summary].split.length
    result[:extracted_at] = Time.current

    result
  end
end
```

#### Custom Metadata

Add custom data to execution logs for filtering and analytics:

```ruby
class UserQueryAgent < ApplicationAgent
  param :query, required: true
  param :user_id, required: true
  param :source, default: "web"

  # This data will be stored in the execution record's metadata column
  def execution_metadata
    {
      user_id: user_id,
      source: source,
      query_length: query.length,
      timestamp: Time.current.iso8601
    }
  end

  private

  def user_prompt
    query
  end
end
```

### Advanced Examples

#### Multi-Step Agent with Conversation History

```ruby
class ConversationAgent < ApplicationAgent
  param :messages, required: true  # Array of {role:, content:} hashes
  param :context, default: {}

  def call
    return dry_run_response if @options[:dry_run]

    instrument_execution do
      Timeout.timeout(self.class.timeout) do
        client = build_client_with_messages(messages)
        response = client.ask(user_prompt)
        process_response(capture_response(response))
      end
    end
  end

  private

  def system_prompt
    "You are a helpful assistant. Remember the conversation context."
  end

  def user_prompt
    messages.last[:content]
  end
end

# Usage
ConversationAgent.call(
  messages: [
    { role: "user", content: "What's the weather like?" },
    { role: "assistant", content: "I don't have real-time weather data." },
    { role: "user", content: "Okay, tell me a joke then." }
  ]
)
```

#### Agent with Custom Cache Key

```ruby
class RecommendationAgent < ApplicationAgent
  param :user_id, required: true
  param :category, required: true
  param :limit, default: 10

  cache 30.minutes

  private

  # Customize what goes into the cache key
  # This excludes 'limit' from cache key, so different limits
  # will return the same cached result
  def cache_key_data
    { user_id: user_id, category: category }
  end

  def user_prompt
    "Generate #{limit} recommendations for user #{user_id} in category #{category}"
  end
end
```

## Reliability Features

RubyLLM::Agents provides built-in reliability features to make your agents resilient against API failures, rate limits, and transient errors.

### Automatic Retries

Configure retry behavior for transient failures:

```ruby
class ReliableAgent < ApplicationAgent
  model "gpt-4o"

  # Retry up to 3 times with exponential backoff
  retries max: 3, backoff: :exponential, base: 0.5, max_delay: 10.0

  # Only retry on specific errors (defaults include timeout, network errors)
  retries max: 3, on: [Timeout::Error, Net::ReadTimeout, Faraday::TimeoutError]

  param :query, required: true

  def user_prompt
    query
  end
end
```

Backoff strategies:
- `:exponential` - Delay doubles each retry (0.5s, 1s, 2s, 4s...)
- `:constant` - Same delay each retry
- Jitter is automatically added to prevent thundering herd

### Model Fallbacks

Automatically try alternative models if the primary fails:

```ruby
class FallbackAgent < ApplicationAgent
  model "gpt-4o"

  # Try these models in order if primary fails
  fallback_models "gpt-4o-mini", "claude-3-5-sonnet", "gemini-2.0-flash"

  # Combine with retries
  retries max: 2
  fallback_models "gpt-4o-mini", "claude-3-sonnet"

  param :query, required: true

  def user_prompt
    query
  end
end
```

The agent will try `gpt-4o` (with 2 retries), then `gpt-4o-mini` (with 2 retries), and so on.

### Circuit Breaker

Prevent cascading failures by temporarily blocking requests to failing models:

```ruby
class ProtectedAgent < ApplicationAgent
  model "gpt-4o"
  fallback_models "claude-3-sonnet"

  # Open circuit after 10 errors within 60 seconds
  # Keep circuit open for 5 minutes before retrying
  circuit_breaker errors: 10, within: 60, cooldown: 300

  param :query, required: true

  def user_prompt
    query
  end
end
```

Circuit breaker states:
- **Closed** - Normal operation, requests pass through
- **Open** - Model is blocked, requests skip to fallback or fail fast
- **Half-Open** - After cooldown, one request is allowed to test recovery

### Total Timeout

Set a maximum time for the entire operation including all retries:

```ruby
class TimeBoundAgent < ApplicationAgent
  model "gpt-4o"
  retries max: 5
  fallback_models "gpt-4o-mini"

  # Abort everything after 30 seconds total
  total_timeout 30

  param :query, required: true

  def user_prompt
    query
  end
end
```

### Viewing Attempt Details

When reliability features are enabled, the dashboard shows all attempts:

```ruby
execution = RubyLLM::Agents::Execution.last

# Check if retries/fallbacks were used
execution.has_retries?      # => true
execution.used_fallback?    # => true
execution.attempts_count    # => 3

# Get attempt details
execution.attempts.each do |attempt|
  puts "Model: #{attempt['model_id']}"
  puts "Duration: #{attempt['duration_ms']}ms"
  puts "Error: #{attempt['error_class']}" if attempt['error_class']
  puts "Short-circuited: #{attempt['short_circuited']}"
end

# Find the successful attempt
execution.successful_attempt  # => Hash with attempt data
execution.chosen_model_id     # => "claude-3-sonnet" (the model that succeeded)
```

## Governance & Cost Controls

### Budget Limits

Set spending limits at global and per-agent levels:

```ruby
# config/initializers/ruby_llm_agents.rb
RubyLLM::Agents.configure do |config|
  config.budgets = {
    # Global limits apply to all agents combined
    global_daily: 100.0,      # $100/day across all agents
    global_monthly: 2000.0,   # $2000/month across all agents

    # Per-agent limits
    per_agent_daily: {
      "ExpensiveAgent" => 50.0,  # $50/day for this agent
      "CheapAgent" => 5.0        # $5/day for this agent
    },
    per_agent_monthly: {
      "ExpensiveAgent" => 500.0
    },

    # Enforcement mode
    # :hard - Block requests when budget exceeded
    # :soft - Allow requests but log warnings
    enforcement: :hard
  }
end
```

Querying budget status:

```ruby
# Get current budget status
status = RubyLLM::Agents::BudgetTracker.status(agent_type: "MyAgent")
# => {
#   global_daily: { limit: 100.0, current: 45.50, remaining: 54.50, percentage_used: 45.5 },
#   global_monthly: { limit: 2000.0, current: 890.0, remaining: 1110.0, percentage_used: 44.5 }
# }

# Check remaining budget
RubyLLM::Agents::BudgetTracker.remaining_budget(:global, :daily)
# => 54.50
```

### Alerts

Get notified when important events occur:

```ruby
# config/initializers/ruby_llm_agents.rb
RubyLLM::Agents.configure do |config|
  config.alerts = {
    # Events to alert on
    on_events: [
      :budget_soft_cap,   # Budget threshold reached (configurable %)
      :budget_hard_cap,   # Budget exceeded (with hard enforcement)
      :breaker_open       # Circuit breaker opened
    ],

    # Slack webhook
    slack_webhook_url: ENV['SLACK_WEBHOOK_URL'],

    # Generic webhook (receives JSON payload)
    webhook_url: "https://your-app.com/webhooks/llm-alerts",

    # Custom handler
    custom: ->(event, payload) {
      # event: :budget_hard_cap
      # payload: { scope: :global_daily, limit: 100.0, current: 105.0 }

      MyNotificationService.notify(
        title: "LLM Budget Alert",
        message: "#{event}: #{payload}"
      )
    }
  }
end
```

Alert payload examples:

```ruby
# Budget alert
{
  event: :budget_hard_cap,
  scope: :global_daily,
  limit: 100.0,
  current: 105.50,
  agent_type: "ExpensiveAgent"
}

# Circuit breaker alert
{
  event: :breaker_open,
  agent_type: "MyAgent",
  model_id: "gpt-4o",
  failure_count: 10,
  window_seconds: 60
}
```

### PII Redaction

Automatically redact sensitive data from execution logs:

```ruby
# config/initializers/ruby_llm_agents.rb
RubyLLM::Agents.configure do |config|
  config.redaction = {
    # Fields to redact (applied to parameters)
    # Default: password, token, api_key, secret, credential, auth, key, access_token
    fields: %w[ssn credit_card phone_number],

    # Regex patterns to redact from prompts/responses
    patterns: [
      /\b\d{3}-\d{2}-\d{4}\b/,  # SSN
      /\b\d{16}\b/,              # Credit card
      /\b[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}\b/i  # Email
    ],

    # Replacement text
    placeholder: "[REDACTED]",

    # Truncate long values
    max_value_length: 1000
  }

  # Control what gets persisted
  config.persist_prompts = true    # Store system/user prompts
  config.persist_responses = true  # Store LLM responses
end
```

## Configuration

Edit `config/initializers/ruby_llm_agents.rb`:

```ruby
RubyLLM::Agents.configure do |config|
  # ============================================================================
  # Default Settings for All Agents
  # ============================================================================

  # Default LLM model (can be overridden per agent)
  config.default_model = "gemini-2.0-flash"

  # Default temperature (0.0 = deterministic, 1.0 = creative)
  config.default_temperature = 0.0

  # Default timeout for LLM requests (in seconds)
  config.default_timeout = 60

  # Enable streaming by default for all agents
  config.default_streaming = false

  # ============================================================================
  # Caching Configuration
  # ============================================================================

  # Cache store for agent responses (default: Rails.cache)
  config.cache_store = Rails.cache
  # config.cache_store = ActiveSupport::Cache::MemoryStore.new
  # config.cache_store = ActiveSupport::Cache::RedisCacheStore.new(url: ENV['REDIS_URL'])

  # ============================================================================
  # Execution Logging
  # ============================================================================

  # Use background job for logging (recommended for production)
  config.async_logging = true

  # How long to retain execution records (for cleanup tasks)
  config.retention_period = 30.days

  # ============================================================================
  # Anomaly Detection
  # ============================================================================

  # Log warning if an execution costs more than this (in dollars)
  config.anomaly_cost_threshold = 5.00

  # Log warning if an execution takes longer than this (in milliseconds)
  config.anomaly_duration_threshold = 10_000  # 10 seconds

  # ============================================================================
  # Dashboard Configuration
  # ============================================================================

  # Authentication for dashboard access
  # Return true to allow access, false to deny
  config.dashboard_auth = ->(controller) {
    controller.current_user&.admin?
  }

  # Customize the parent controller for dashboard
  config.dashboard_parent_controller = "ApplicationController"
end
```

## Dashboard

### Mounting the Dashboard

The install generator automatically mounts the dashboard, but you can customize the path:

```ruby
# config/routes.rb
mount RubyLLM::Agents::Engine => "/agents"
# or
mount RubyLLM::Agents::Engine => "/admin/ai-agents", as: "agents_dashboard"
```

### Dashboard Features

The dashboard provides:

1. **Overview Page** (`/agents`)
   - Today's execution stats (total, success rate, failures)
   - Real-time cost tracking
   - Performance trends (7-day chart)
   - Top agents by usage

2. **Executions List** (`/agents/executions`)
   - Filterable by agent type, status, date range
   - Sortable by cost, duration, timestamp
   - Real-time updates via Turbo Streams
   - Search by parameters

3. **Execution Detail** (`/agents/executions/:id`)
   - Full system and user prompts
   - Complete LLM response
   - Token usage breakdown (input, output, cached)
   - Cost calculation
   - Execution metadata
   - Error details (if failed)

### Authentication

Protect your dashboard by configuring authentication:

```ruby
# config/initializers/ruby_llm_agents.rb
RubyLLM::Agents.configure do |config|
  config.dashboard_auth = ->(controller) {
    # Example: Devise authentication
    controller.authenticate_user! && controller.current_user.admin?

    # Example: Basic auth
    # controller.authenticate_or_request_with_http_basic do |username, password|
    #   username == ENV['DASHBOARD_USERNAME'] &&
    #   password == ENV['DASHBOARD_PASSWORD']
    # end

    # Example: IP whitelist
    # ['127.0.0.1', '::1'].include?(controller.request.remote_ip)
  }
end
```

## Analytics & Reporting

Query execution data programmatically:

### Daily Reports

```ruby
# Get today's summary
report = RubyLLM::Agents::Execution.daily_report
# => {
#   total_executions: 1250,
#   successful: 1180,
#   failed: 70,
#   success_rate: 94.4,
#   total_cost: 12.45,
#   avg_duration_ms: 850,
#   total_tokens: 450000
# }
```

### Cost Analysis

```ruby
# Cost breakdown by agent for this week
costs = RubyLLM::Agents::Execution.cost_by_agent(period: :this_week)
# => [
#   { agent_type: "SearchIntentAgent", total_cost: 5.67, executions: 450 },
#   { agent_type: "ContentGeneratorAgent", total_cost: 3.21, executions: 120 }
# ]

# Cost breakdown by model
costs = RubyLLM::Agents::Execution.cost_by_model(period: :today)
```

### Agent Statistics

```ruby
# Stats for a specific agent
stats = RubyLLM::Agents::Execution.stats_for("SearchIntentAgent", period: :today)
# => {
#   total: 150,
#   successful: 145,
#   failed: 5,
#   success_rate: 96.67,
#   avg_cost: 0.012,
#   total_cost: 1.80,
#   avg_duration_ms: 450,
#   total_tokens: 75000
# }
```

### Version Comparison

```ruby
# Compare two versions of an agent
comparison = RubyLLM::Agents::Execution.compare_versions(
  "SearchIntentAgent",
  "1.0",
  "2.0",
  period: :this_week
)
# => {
#   "1.0" => { total: 450, success_rate: 94.2, avg_cost: 0.015 },
#   "2.0" => { total: 550, success_rate: 96.8, avg_cost: 0.012 }
# }
```

### Trend Analysis

```ruby
# 7-day trend for an agent
trend = RubyLLM::Agents::Execution.trend_analysis(
  agent_type: "SearchIntentAgent",
  days: 7
)
# => [
#   { date: "2024-01-01", executions: 120, cost: 1.45, avg_duration: 450 },
#   { date: "2024-01-02", executions: 135, cost: 1.62, avg_duration: 430 },
#   ...
# ]
```

### Streaming Analytics

```ruby
# Percentage of executions using streaming
RubyLLM::Agents::Execution.streaming_rate
# => 45.5

# Average time-to-first-token for streaming executions (milliseconds)
RubyLLM::Agents::Execution.avg_time_to_first_token
# => 245.3
```

### Scopes

Chain scopes for complex queries:

```ruby
# All successful executions today
RubyLLM::Agents::Execution.today.successful

# Failed executions for specific agent
RubyLLM::Agents::Execution.by_agent("SearchIntentAgent").failed

# Expensive executions this week
RubyLLM::Agents::Execution.this_week.expensive(1.00)  # cost > $1

# Slow executions
RubyLLM::Agents::Execution.slow(5000)  # duration > 5 seconds

# Complex query
expensive_slow_failures = RubyLLM::Agents::Execution
  .this_week
  .by_agent("ContentGeneratorAgent")
  .failed
  .expensive(0.50)
  .slow(3000)
  .order(created_at: :desc)
```

### Available Scopes

```ruby
# Time-based
.today
.this_week
.this_month
.yesterday

# Status
.successful
.failed
.status_error
.status_timeout
.status_running

# Agent/Model
.by_agent("AgentName")
.by_model("gpt-4o")

# Performance
.expensive(threshold)  # cost > threshold
.slow(milliseconds)    # duration > ms

# Token usage
.high_token_usage(threshold)

# Streaming
.streaming
.non_streaming
```

## Generators

### Agent Generator

```bash
# Basic agent
rails generate ruby_llm_agents:agent MyAgent

# Agent with parameters
rails generate ruby_llm_agents:agent SearchAgent query:required limit:10 filters

# Agent with custom model and temperature
rails generate ruby_llm_agents:agent ContentAgent \
  topic:required \
  --model=gpt-4o \
  --temperature=0.7

# Agent with caching
rails generate ruby_llm_agents:agent CachedAgent \
  key:required \
  --cache=1.hour
```

### Install Generator

```bash
# Initial setup
rails generate ruby_llm_agents:install
```

### Upgrade Generator

```bash
# Upgrade to latest schema (when gem is updated)
rails generate ruby_llm_agents:upgrade
rails db:migrate
```

This creates migrations for new features like:
- `system_prompt` and `user_prompt` columns for prompt persistence
- `attempts` JSONB column for reliability tracking
- `chosen_model_id` for fallback model tracking

## Background Jobs

For production environments, enable async logging:

```ruby
# config/initializers/ruby_llm_agents.rb
RubyLLM::Agents.configure do |config|
  config.async_logging = true
end
```

This uses `RubyLLM::Agents::ExecutionLoggerJob` to log executions in the background.

Make sure you have a job processor running:

```bash
# Using Solid Queue (Rails 7.1+)
bin/jobs

# Or Sidekiq
bundle exec sidekiq
```

## Maintenance Tasks

### Cleanup Old Executions

```ruby
# In a rake task or scheduled job
retention_period = RubyLLM::Agents.configuration.retention_period
RubyLLM::Agents::Execution.where("created_at < ?", retention_period.ago).delete_all
```

### Export Data

```ruby
# Export to CSV
require 'csv'

CSV.open("agent_executions.csv", "wb") do |csv|
  csv << ["Agent", "Status", "Cost", "Duration", "Timestamp"]

  RubyLLM::Agents::Execution.this_month.find_each do |execution|
    csv << [
      execution.agent_type,
      execution.status,
      execution.total_cost,
      execution.duration_ms,
      execution.created_at
    ]
  end
end
```

## Testing

### RSpec Example

```ruby
# spec/agents/search_intent_agent_spec.rb
require 'rails_helper'

RSpec.describe SearchIntentAgent do
  describe ".call" do
    it "extracts search intent from query" do
      result = described_class.call(
        query: "red summer dress under $50",
        dry_run: true  # Use dry_run for testing without API calls
      )

      expect(result[:dry_run]).to be true
      expect(result[:agent]).to eq("SearchIntentAgent")
    end
  end

  describe "parameter validation" do
    it "requires query parameter" do
      expect {
        described_class.call(limit: 10)
      }.to raise_error(ArgumentError, /missing required params/)
    end

    it "uses default limit" do
      agent = described_class.new(query: "test")
      expect(agent.limit).to eq(10)
    end
  end
end
```

### Mocking LLM Responses

```ruby
# spec/support/llm_helpers.rb
module LLMHelpers
  def mock_llm_response(data)
    response = instance_double(RubyLLM::Response, content: data)
    allow_any_instance_of(RubyLLM::Chat).to receive(:ask).and_return(response)
  end
end

# In your spec
RSpec.describe SearchIntentAgent do
  include LLMHelpers

  it "processes search intent" do
    mock_llm_response({
      refined_query: "red dress",
      filters: ["color:red"],
      category_id: 42
    })

    result = described_class.call(query: "red summer dress")

    expect(result[:refined_query]).to eq("red dress")
    expect(result[:filters]).to include("color:red")
  end
end
```

## Development

After checking out the repo:

```bash
# Install dependencies
bin/setup

# Run tests
bundle exec rake spec

# Run linter
bundle exec standardrb

# Fix linting issues
bundle exec standardrb --fix

# Run console
bin/rails console
```

## Troubleshooting

### Agent execution fails with timeout

Increase timeout for specific agent:

```ruby
class SlowAgent < ApplicationAgent
  timeout 120  # 2 minutes
end
```

### Cache not working

Ensure Rails cache is configured:

```ruby
# config/environments/production.rb
config.cache_store = :redis_cache_store, { url: ENV['REDIS_URL'] }
```

### Dashboard not accessible

Check route mounting and authentication:

```ruby
# config/routes.rb
mount RubyLLM::Agents::Engine => "/agents"

# config/initializers/ruby_llm_agents.rb
config.dashboard_auth = ->(controller) { true }  # Allow all (dev only!)
```

### High costs

Monitor and set limits:

```ruby
# config/initializers/ruby_llm_agents.rb
config.anomaly_cost_threshold = 1.00  # Alert at $1

# Check expensive executions
RubyLLM::Agents::Execution.this_week.expensive(0.50)
```

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/adham90/ruby_llm-agents.

1. Fork the repository
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Add some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create a new Pull Request

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).

## Credits

Built with ❤️ by [Adham Eldeeb](https://github.com/adham90)

Powered by [RubyLLM](https://github.com/crmne/ruby_llm)
