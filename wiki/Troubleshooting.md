# Troubleshooting

Common issues and solutions for RubyLLM::Agents.

## Installation Issues

### Migration Errors

```
ActiveRecord::StatementInvalid: table already exists
```

**Solution:**
```bash
rails db:migrate:status
# Find pending migrations and run them individually
rails db:migrate:up VERSION=20240101000000
```

### Missing Dependencies

```
LoadError: cannot load such file -- ruby_llm
```

**Solution:**
```bash
bundle install
```

### Route Not Found

```
No route matches [GET] "/agents"
```

**Solution:**
```ruby
# config/routes.rb
mount RubyLLM::Agents::Engine => "/agents"
```

## Agent Execution Issues

### Timeout Errors

```
Timeout::Error: execution expired
```

**Solutions:**

1. Increase agent timeout:
   ```ruby
   class MyAgent < ApplicationAgent
     timeout 120  # 2 minutes
   end
   ```

2. Use streaming for long responses:
   ```ruby
   streaming true
   ```

3. Add retries:
   ```ruby
   retries max: 3, backoff: :exponential
   ```

### API Key Errors

```
Faraday::UnauthorizedError: Invalid API key
```

**Solutions:**

1. Verify key is set:
   ```ruby
   puts ENV['OPENAI_API_KEY'].present?
   ```

2. Check key format:
   ```ruby
   # OpenAI keys start with sk-
   # Anthropic keys start with sk-ant-
   ```

3. Test key directly:
   ```ruby
   RubyLLM.chat(model: "gpt-4o-mini").ask("test")
   ```

### Rate Limit Errors

```
Faraday::TooManyRequestsError: Rate limit exceeded
```

**Solutions:**

1. Add retries with backoff:
   ```ruby
   retries max: 5, backoff: :exponential, max_delay: 60.0
   ```

2. Add fallback models:
   ```ruby
   fallback_models "gpt-4o-mini", "claude-3-haiku"
   ```

3. Implement request queuing in your application

### Schema Validation Errors

```
JSON::Schema::ValidationError: property missing
```

**Solutions:**

1. Check LLM response format:
   ```ruby
   result = MyAgent.call(query: "test", dry_run: true)
   puts result[:user_prompt]
   ```

2. Make fields nullable:
   ```ruby
   string :field, nullable: true
   ```

3. Provide examples in prompt

## Caching Issues

### Cache Not Working

**Symptoms:** Same query always hits API

**Solutions:**

1. Verify cache is enabled:
   ```ruby
   cache 1.hour
   ```

2. Check cache store:
   ```ruby
   RubyLLM::Agents.configuration.cache_store
   ```

3. Verify cache key:
   ```ruby
   # Different parameters = different cache keys
   MyAgent.call(query: "test", limit: 10)  # Cache 1
   MyAgent.call(query: "test", limit: 20)  # Cache 2
   ```

### Stale Cache

**Solutions:**

1. Bump version:
   ```ruby
   version "2.0"  # Invalidates all caches
   ```

2. Skip cache:
   ```ruby
   MyAgent.call(query: "test", skip_cache: true)
   ```

3. Clear cache:
   ```ruby
   Rails.cache.clear
   ```

## Dashboard Issues

### Dashboard Not Loading

**Solutions:**

1. Check route:
   ```bash
   rails routes | grep agents
   ```

2. Check authentication:
   ```ruby
   # Temporarily allow all
   config.dashboard_auth = ->(_) { true }
   ```

3. Check for JavaScript errors in browser console

### Charts Not Displaying

**Solutions:**

1. Ensure Chartkick is loaded:
   ```ruby
   # application.js
   import "chartkick"
   import "Chart.bundle"
   ```

2. Check for data:
   ```ruby
   RubyLLM::Agents::Execution.count
   ```

### Slow Dashboard

**Solutions:**

1. Add indexes:
   ```bash
   rails generate ruby_llm_agents:upgrade
   rails db:migrate
   ```

2. Limit data:
   ```ruby
   config.retention_period = 30.days
   ```

3. Reduce per-page count:
   ```ruby
   config.dashboard_per_page = 25
   ```

## Execution Tracking Issues

### Executions Not Saved

**Solutions:**

1. Check async logging:
   ```ruby
   # Try sync first
   config.async_logging = false
   ```

2. Check job processor:
   ```bash
   # Sidekiq
   ps aux | grep sidekiq

   # Solid Queue
   bin/jobs
   ```

3. Check for errors:
   ```ruby
   # In rails console
   RubyLLM::Agents::Execution.create!(
     agent_type: "Test",
     status: "success"
   )
   ```

### Missing Fields in Execution

**Solutions:**

1. Run upgrade migration:
   ```bash
   rails generate ruby_llm_agents:upgrade
   rails db:migrate
   ```

2. Check column exists:
   ```ruby
   RubyLLM::Agents::Execution.column_names
   ```

## Reliability Issues

### Retries Not Working

**Solutions:**

1. Verify configuration:
   ```ruby
   retries max: 3, backoff: :exponential
   ```

2. Check error type is retryable:
   ```ruby
   # Default retryable: Timeout, network errors
   # Custom:
   retries max: 3, on: [MyCustomError]
   ```

3. Check total_timeout isn't too short:
   ```ruby
   total_timeout 60  # Enough for retries
   ```

### Fallbacks Not Triggering

**Solutions:**

1. Verify fallback models are configured:
   ```ruby
   fallback_models "gpt-4o-mini", "claude-3-haiku"
   ```

2. Check circuit breaker isn't blocking:
   ```ruby
   RubyLLM::Agents::CircuitBreaker.status("gpt-4o")
   ```

### Circuit Breaker Stuck Open

**Solutions:**

1. Wait for cooldown:
   ```ruby
   status = RubyLLM::Agents::CircuitBreaker.status("gpt-4o")
   puts "Closes at: #{status[:closes_at]}"
   ```

2. Manually close:
   ```ruby
   RubyLLM::Agents::CircuitBreaker.close!("gpt-4o")
   ```

## Budget Issues

### Budget Exceeded Unexpectedly

**Solutions:**

1. Check current usage:
   ```ruby
   RubyLLM::Agents::BudgetTracker.status
   ```

2. Review expensive executions:
   ```ruby
   RubyLLM::Agents::Execution.today
     .order(total_cost: :desc)
     .limit(10)
   ```

3. Check for runaway agents:
   ```ruby
   RubyLLM::Agents::Execution.today
     .group(:agent_type)
     .sum(:total_cost)
   ```

### Alerts Not Sending

**Solutions:**

1. Verify alert configuration:
   ```ruby
   config.alerts = {
     on_events: [:budget_hard_cap],
     slack_webhook_url: ENV['SLACK_WEBHOOK_URL']
   }
   ```

2. Test webhook:
   ```ruby
   RubyLLM::Agents::AlertNotifier.notify(
     :test_event,
     { message: "Test alert" }
   )
   ```

3. Check webhook URL is valid

## Getting Help

### Debug Information

Collect this info when reporting issues:

```ruby
{
  ruby_version: RUBY_VERSION,
  rails_version: Rails.version,
  gem_version: RubyLLM::Agents::VERSION,
  ruby_llm_version: RubyLLM::VERSION,
  config: RubyLLM::Agents.configuration.to_h
}
```

### Reporting Bugs

1. GitHub Issues: https://github.com/adham90/ruby_llm-agents/issues
2. Include:
   - Ruby/Rails versions
   - Gem version
   - Error message and backtrace
   - Minimal reproduction steps

### Community Support

- GitHub Discussions: https://github.com/adham90/ruby_llm-agents/discussions
- RubyLLM Documentation: https://github.com/crmne/ruby_llm

## Related Pages

- [Configuration](Configuration) - Full settings reference
- [Installation](Installation) - Setup guide
- [Production Deployment](Production-Deployment) - Production tips
