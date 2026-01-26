# Caching

Cache LLM responses to reduce costs and latency for repeated requests.

## Enabling Caching

### Per-Agent

```ruby
class CachedAgent < ApplicationAgent
  model "gpt-4o"
  cache 1.hour  # Cache responses for 1 hour

  param :query, required: true

  def user_prompt
    query
  end
end
```

### Cache Duration Options

```ruby
cache 30.minutes
cache 1.hour
cache 6.hours
cache 1.day
cache 1.week
```

## How Caching Works

1. Cache key is generated from:
   - Agent class name
   - Agent version
   - All parameters
   - System prompt
   - User prompt

2. Before making an API call, the cache is checked
3. If found, cached response is returned immediately
4. If not found, API call is made and response is cached

## Cache Key Generation

### Default Behavior

All parameters are included in the cache key:

```ruby
class SearchAgent < ApplicationAgent
  cache 1.hour
  param :query, required: true
  param :limit, default: 10
end

# These produce DIFFERENT cache keys
SearchAgent.call(query: "test", limit: 10)
SearchAgent.call(query: "test", limit: 20)
```

### Custom Cache Keys

Override `cache_key_data` to control what affects caching:

```ruby
class SearchAgent < ApplicationAgent
  cache 1.hour
  param :query, required: true
  param :limit, default: 10
  param :request_id  # Should NOT affect caching

  def cache_key_data
    # Only query and limit affect the cache key
    { query: query, limit: limit }
    # request_id is excluded
  end
end

# These now use the SAME cache (request_id ignored)
SearchAgent.call(query: "test", limit: 10, request_id: "abc")
SearchAgent.call(query: "test", limit: 10, request_id: "xyz")
```

## Version-Based Invalidation

Change the version to invalidate all cached responses:

```ruby
class MyAgent < ApplicationAgent
  version "1.0"  # Current cache
  cache 1.day
end

# After updating prompts, bump the version
class MyAgent < ApplicationAgent
  version "1.1"  # New version = new cache keys
  cache 1.day
end
```

## Bypassing Cache

### Skip Cache for Specific Call

```ruby
# Force a fresh API call
result = MyAgent.call(query: "test", skip_cache: true)
```

### Check if Result Was Cached

```ruby
result = MyAgent.call(query: "test")
result.cached?  # => true/false (if available)
```

## Cache Store Configuration

### Default (Rails.cache)

```ruby
# Uses whatever Rails.cache is configured to
config.cache_store = Rails.cache
```

### Memory Store (Development)

```ruby
config.cache_store = ActiveSupport::Cache::MemoryStore.new(
  size: 64.megabytes
)
```

### Redis (Production)

```ruby
config.cache_store = ActiveSupport::Cache::RedisCacheStore.new(
  url: ENV['REDIS_URL'],
  namespace: 'llm_agents',
  expires_in: 1.day
)
```

### File Store

```ruby
config.cache_store = ActiveSupport::Cache::FileStore.new(
  Rails.root.join('tmp', 'llm_cache'),
  expires_in: 1.day
)
```

## Caching Strategies

### Static Content

High TTL for stable, factual responses:

```ruby
class FactAgent < ApplicationAgent
  version "1.0"
  cache 1.week  # Facts don't change often

  param :topic, required: true

  def user_prompt
    "Explain: #{topic}"
  end
end
```

### User-Specific Content

Include user context in cache key:

```ruby
class PersonalizedAgent < ApplicationAgent
  cache 1.hour
  param :query, required: true
  param :user_id, required: true

  def cache_key_data
    { query: query, user_id: user_id }
  end
end
```

### Time-Sensitive Content

Short TTL or no caching:

```ruby
class NewsAgent < ApplicationAgent
  # No caching - always fetch fresh
  param :topic, required: true
end

# Or very short cache
class WeatherAgent < ApplicationAgent
  cache 15.minutes
end
```

## Caching and Streaming

**Important:** Streaming responses are never cached.

```ruby
class StreamingAgent < ApplicationAgent
  streaming true
  cache 1.hour  # Ignored when streaming
end

# This will always make an API call
StreamingAgent.call(prompt: "test") do |chunk|
  print chunk
end
```

## Cache Metrics

Track cache performance:

```ruby
# In your monitoring/metrics
cache_hits = 0
cache_misses = 0

# Wrap agent calls
result = MyAgent.call(query: query)
if result.cached?
  cache_hits += 1
else
  cache_misses += 1
end

hit_rate = cache_hits.to_f / (cache_hits + cache_misses)
```

## Clearing Cache

### Clear All Agent Cache

```ruby
Rails.cache.delete_matched("ruby_llm_agents/*")
```

### Clear Specific Agent Cache

```ruby
# Clear all SearchAgent caches
Rails.cache.delete_matched("ruby_llm_agents/SearchAgent/*")
```

### Clear in Development

```bash
rails tmp:cache:clear
```

## Best Practices

### Cache Deterministic Responses

```ruby
class ClassifierAgent < ApplicationAgent
  temperature 0.0  # Deterministic
  cache 1.day      # Safe to cache
end
```

### Be Careful with High Temperature

```ruby
class CreativeAgent < ApplicationAgent
  temperature 1.0  # Non-deterministic
  cache 30.minutes # Short cache or no cache
end
```

### Include Relevant Context in Cache Key

```ruby
def cache_key_data
  {
    query: query,
    user_locale: locale,      # Different locales = different responses
    model_version: version    # Track model updates
  }
end
```

### Monitor Cache Size

```ruby
# Redis
redis = Redis.new(url: ENV['REDIS_URL'])
redis.info('memory')['used_memory_human']

# Memory store
Rails.cache.instance_variable_get(:@data).size
```

## Troubleshooting

### Cache Not Working

1. Verify cache is enabled:
   ```ruby
   cache 1.hour  # Must be set
   ```

2. Check cache store is configured:
   ```ruby
   RubyLLM::Agents.configuration.cache_store
   ```

3. Verify cache key is consistent:
   ```ruby
   result = MyAgent.call(query: "test", dry_run: true)
   # Check parameters in output
   ```

### Stale Responses

1. Bump the version:
   ```ruby
   version "2.0"  # Invalidates all caches
   ```

2. Clear cache manually:
   ```ruby
   Rails.cache.clear
   ```

## Related Pages

- [Agent DSL](Agent-DSL) - Cache configuration
- [Configuration](Configuration) - Cache store setup
- [Production Deployment](Production-Deployment) - Production caching
