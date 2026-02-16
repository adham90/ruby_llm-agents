# Installation

Detailed installation instructions for RubyLLM::Agents.

## Requirements

| Dependency | Minimum Version | Notes |
|------------|-----------------|-------|
| Ruby | 3.1.0 | Required for pattern matching |
| Rails | 7.0 | Requires Hotwire for dashboard |
| PostgreSQL/MySQL/SQLite | Any | For execution tracking |

## Gem Dependencies

RubyLLM::Agents automatically installs:

```ruby
gem "rails", ">= 7.0"
gem "ruby_llm", ">= 1.12.0"       # LLM client library
gem "turbo-rails", ">= 1.0"       # Hotwire Turbo for real-time UI
gem "stimulus-rails", ">= 1.0"    # Hotwire Stimulus for JavaScript
gem "chartkick", ">= 5.0"         # Beautiful charts for analytics
```

## Installation Steps

### 1. Add to Gemfile

```ruby
# Gemfile
gem "ruby_llm-agents"
```

### 2. Bundle Install

```bash
bundle install
```

### 3. Run Install Generator

```bash
rails generate ruby_llm_agents:install
```

This creates:

```
create  db/migrate/xxx_create_ruby_llm_agents_executions.rb
create  config/initializers/ruby_llm_agents.rb
create  app/agents/application_agent.rb
insert  config/routes.rb
```

### 4. Run Migrations

```bash
rails db:migrate
```

### 5. Configure API Keys

Choose one method:

#### Environment Variables

```bash
# .env
OPENAI_API_KEY=sk-...
ANTHROPIC_API_KEY=sk-ant-...
GOOGLE_API_KEY=...
```

#### Rails Credentials

```bash
EDITOR="code --wait" rails credentials:edit
```

```yaml
openai:
  api_key: sk-...
anthropic:
  api_key: sk-ant-...
google:
  api_key: ...
```

#### Unified Configuration (Recommended, v2.1+)

Configure API keys directly in `RubyLLM::Agents.configure` — no separate initializer needed:

```ruby
# config/initializers/ruby_llm_agents.rb
RubyLLM::Agents.configure do |config|
  # API keys (forwarded to RubyLLM automatically)
  config.openai_api_key = ENV['OPENAI_API_KEY']
  config.anthropic_api_key = ENV['ANTHROPIC_API_KEY']
  config.gemini_api_key = ENV['GOOGLE_API_KEY']

  # Agent settings
  config.default_model = "gpt-4o"
end
```

See [Configuration](Configuration#unified-api-key-configuration-v21) for all supported provider attributes.

## Verify Installation

### Check Dashboard

Start your Rails server and visit:

```
http://localhost:3000/agents
```

You should see the RubyLLM::Agents dashboard.

### Test an Agent

```ruby
# rails console
class TestAgent < ApplicationAgent
  model "gpt-4o-mini"
  user "{message}"
end

result = TestAgent.call(message: "Hello!")
puts result.content

# Or use .ask for a conversational back-and-forth:
agent = TestAgent.new
result = agent.ask("Hello!")
puts result.content

result = agent.ask("What was my first message?")
puts result.content  # The agent remembers "Hello!"
```

## Upgrading

When upgrading to a new version:

```bash
bundle update ruby_llm-agents
rails generate ruby_llm_agents:upgrade
rails db:migrate
```

The upgrade generator adds any new database columns or tables.

## Troubleshooting

### Missing Migrations

```bash
rails generate ruby_llm_agents:install
rails db:migrate
```

### Dashboard Not Found

Ensure the route is mounted:

```ruby
# config/routes.rb
mount RubyLLM::Agents::Engine => "/agents"
```

### API Key Errors

Verify your keys are set:

```ruby
# rails console
puts ENV['OPENAI_API_KEY'].present?
```

See [Troubleshooting](Troubleshooting) for more solutions.

## Platform Notes

### Heroku

Add buildpacks if using native extensions:

```bash
heroku buildpacks:add --index 1 heroku/ruby
```

### Docker

Ensure your Dockerfile includes:

```dockerfile
ENV OPENAI_API_KEY=${OPENAI_API_KEY}
```

### CI/CD

Set environment variables in your CI configuration:

```yaml
# .github/workflows/test.yml
env:
  OPENAI_API_KEY: ${{ secrets.OPENAI_API_KEY }}
```
