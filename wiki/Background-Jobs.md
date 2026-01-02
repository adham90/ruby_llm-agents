# Background Jobs

Configure async logging and job processing for production performance.

## Why Async Logging?

Synchronous logging blocks agent execution:

```
Agent Call ──► LLM Request ──► DB Write ──► Response
                               ↑
                          Adds latency
```

Async logging moves DB writes to background:

```
Agent Call ──► LLM Request ──► Queue Job ──► Response (fast!)
                                    │
                                    └──► DB Write (background)
```

## Enabling Async Logging

```ruby
# config/initializers/ruby_llm_agents.rb
RubyLLM::Agents.configure do |config|
  config.async_logging = true
end
```

## Job Processor Setup

### Solid Queue (Rails 7.1+)

```bash
# Start the job processor
bin/jobs
```

Configuration:

```yaml
# config/solid_queue.yml
production:
  workers:
    - queues: [default, llm_logging]
      threads: 5
```

### Sidekiq

```bash
# Start Sidekiq
bundle exec sidekiq
```

Configuration:

```yaml
# config/sidekiq.yml
:concurrency: 10
:queues:
  - default
  - llm_logging
```

### Other Processors

Works with any ActiveJob adapter:

```ruby
# config/application.rb
config.active_job.queue_adapter = :delayed_job
# or :resque, :good_job, :que, etc.
```

## The ExecutionLoggerJob

RubyLLM::Agents uses `ExecutionLoggerJob` for async logging:

```ruby
class RubyLLM::Agents::ExecutionLoggerJob < ApplicationJob
  queue_as :llm_logging

  def perform(execution_data)
    RubyLLM::Agents::Execution.create!(execution_data)
  end
end
```

### Queue Configuration

Specify a dedicated queue:

```ruby
# In your job processor config
queues:
  - llm_logging  # High priority
  - default
```

### Retry Configuration

```ruby
# config/initializers/ruby_llm_agents.rb
RubyLLM::Agents::ExecutionLoggerJob.retry_on(
  ActiveRecord::RecordInvalid,
  wait: 5.seconds,
  attempts: 3
)
```

## Fallback Logging

If async logging fails, the gem falls back to sync logging:

```ruby
# Automatic fallback behavior:
# 1. Try to enqueue job
# 2. If queue fails, log synchronously
# 3. If sync fails, log error and continue
```

## Monitoring Job Health

### Check Queue Depth

```ruby
# Sidekiq
Sidekiq::Queue.new('llm_logging').size

# Solid Queue
SolidQueue::Job.where(queue_name: 'llm_logging').count
```

### Failed Jobs

```ruby
# Sidekiq
Sidekiq::DeadSet.new.size

# Check for logging failures
Sidekiq::DeadSet.new.each do |job|
  if job.item['class'] == 'RubyLLM::Agents::ExecutionLoggerJob'
    puts "Failed logging: #{job.item['args']}"
  end
end
```

### Alerts for Queue Backup

```ruby
# In a monitoring job
class QueueMonitorJob < ApplicationJob
  def perform
    queue_size = Sidekiq::Queue.new('llm_logging').size

    if queue_size > 1000
      SlackNotifier.notify(
        "LLM logging queue backed up: #{queue_size} jobs"
      )
    end
  end
end
```

## Performance Tuning

### Batch Logging

For high-volume scenarios:

```ruby
# Custom batch logging job
class BatchExecutionLoggerJob < ApplicationJob
  def perform(execution_batch)
    RubyLLM::Agents::Execution.insert_all(execution_batch)
  end
end
```

### Connection Pooling

Ensure adequate database connections:

```yaml
# config/database.yml
production:
  pool: <%= ENV.fetch("RAILS_MAX_THREADS") { 5 }.to_i + 5 %>
```

### Memory Optimization

For large responses:

```ruby
config.persist_responses = false  # Don't store large responses

# Or truncate
config.redaction = {
  max_value_length: 10_000  # Truncate at 10KB
}
```

## Sync vs Async Comparison

| Aspect | Sync | Async |
|--------|------|-------|
| Agent latency | Higher | Lower |
| Data consistency | Immediate | Eventually |
| Failure handling | Blocks agent | Graceful fallback |
| Resource usage | DB connection per request | Shared pool |

## Development vs Production

```ruby
RubyLLM::Agents.configure do |config|
  # Sync in development for easier debugging
  config.async_logging = !Rails.env.development?
end
```

## Viewing Pending Logs

Jobs waiting to be processed:

```ruby
# Sidekiq
Sidekiq::Queue.new('llm_logging').each do |job|
  puts job.args
end

# Solid Queue
SolidQueue::Job.where(queue_name: 'llm_logging').find_each do |job|
  puts job.arguments
end
```

## Troubleshooting

### Executions Not Appearing

1. Check job processor is running:
   ```bash
   # Sidekiq
   ps aux | grep sidekiq

   # Solid Queue
   ps aux | grep solid_queue
   ```

2. Check queue:
   ```ruby
   Sidekiq::Queue.new('llm_logging').size
   ```

3. Check for failed jobs:
   ```ruby
   Sidekiq::DeadSet.new.size
   ```

4. Try sync logging:
   ```ruby
   config.async_logging = false
   ```

### Jobs Failing

1. Check error logs:
   ```ruby
   Sidekiq::DeadSet.new.each { |j| puts j.item['error_message'] }
   ```

2. Common issues:
   - Database connection pool exhausted
   - Schema mismatch (run migrations)
   - Serialization errors

### High Latency Despite Async

1. Check if fallback to sync is happening:
   ```ruby
   Rails.logger.grep("Falling back to sync")
   ```

2. Verify job processor is healthy

3. Check Redis/queue health

## Related Pages

- [Configuration](Configuration) - Full settings guide
- [Production Deployment](Production-Deployment) - Production setup
- [Execution Tracking](Execution-Tracking) - What gets logged
- [Troubleshooting](Troubleshooting) - Common issues
