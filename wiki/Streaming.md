# Streaming

Stream LLM responses in real-time as they're generated, reducing perceived latency for users.

## Enabling Streaming

### Per-Agent

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

### Global Default

```ruby
# config/initializers/ruby_llm_agents.rb
RubyLLM::Agents.configure do |config|
  config.default_streaming = true
end
```

## Using Streaming with a Block

Process chunks as they arrive:

```ruby
StreamingAgent.call(prompt: "Write a story") do |chunk|
  print chunk  # Each chunk is a string fragment
end
```

Output appears progressively:
```
Once... upon... a... time...
```

## HTTP Streaming

### Server-Sent Events (SSE)

```ruby
class StreamingController < ApplicationController
  include ActionController::Live

  def stream_response
    response.headers['Content-Type'] = 'text/event-stream'
    response.headers['Cache-Control'] = 'no-cache'
    response.headers['X-Accel-Buffering'] = 'no'  # Disable nginx buffering

    StreamingAgent.call(prompt: params[:prompt]) do |chunk|
      response.stream.write "data: #{chunk.to_json}\n\n"
    end

    response.stream.write "data: [DONE]\n\n"
  rescue ActionController::Live::ClientDisconnected
    # Client disconnected, clean up
  ensure
    response.stream.close
  end
end
```

### Client-Side JavaScript

```javascript
const eventSource = new EventSource('/stream?prompt=' + encodeURIComponent(prompt));

eventSource.onmessage = (event) => {
  if (event.data === '[DONE]') {
    eventSource.close();
    return;
  }

  const chunk = JSON.parse(event.data);
  document.getElementById('output').textContent += chunk;
};

eventSource.onerror = () => {
  eventSource.close();
};
```

## Turbo Streams Integration

### Controller

```ruby
class ChatController < ApplicationController
  def create
    respond_to do |format|
      format.turbo_stream do
        StreamingAgent.call(prompt: params[:message]) do |chunk|
          Turbo::StreamsChannel.broadcast_append_to(
            "chat_#{params[:chat_id]}",
            target: "messages",
            partial: "messages/chunk",
            locals: { content: chunk }
          )
        end
      end
    end
  end
end
```

### View

```erb
<%= turbo_stream_from "chat_#{@chat.id}" %>
<div id="messages"></div>
```

## Time-to-First-Token (TTFT) Tracking

Streaming executions track latency metrics:

```ruby
# After streaming completes
execution = RubyLLM::Agents::Execution.last

execution.streaming?              # => true
execution.time_to_first_token_ms  # => 245 (ms until first chunk)
execution.duration_ms             # => 2500 (total time)
```

### Analytics

```ruby
# Average TTFT for streaming agents
RubyLLM::Agents::Execution
  .streaming
  .average(:time_to_first_token_ms)
# => 312.5

# TTFT by model
RubyLLM::Agents::Execution
  .streaming
  .group(:model_id)
  .average(:time_to_first_token_ms)
# => { "gpt-4o" => 280, "claude-3-sonnet" => 195 }
```

## Streaming with Structured Output

When using schemas, the full response is still validated:

```ruby
class StructuredStreamingAgent < ApplicationAgent
  model "gpt-4o"
  streaming true

  param :topic, required: true

  def user_prompt
    "Write about #{topic}"
  end

  def schema
    @schema ||= RubyLLM::Schema.create do
      string :title
      string :content
    end
  end
end

# Stream the raw text
StructuredStreamingAgent.call(topic: "AI") do |chunk|
  print chunk  # Raw JSON chunks
end
# Result is parsed and validated at the end
```

## Caching and Streaming

**Important:** Streaming responses are not cached by design, as caching would defeat the purpose of real-time streaming.

```ruby
class MyAgent < ApplicationAgent
  streaming true
  cache 1.hour  # Cache is ignored when streaming
end
```

If you need caching with streaming-like UX, consider:

1. Cache the full response
2. Simulate streaming on the client side

## Error Handling

```ruby
begin
  StreamingAgent.call(prompt: "test") do |chunk|
    print chunk
  end
rescue Timeout::Error
  puts "\n[Stream timed out]"
rescue => e
  puts "\n[Stream error: #{e.message}]"
end
```

## Streaming in Background Jobs

For long-running streams, use ActionCable:

```ruby
class StreamingJob < ApplicationJob
  def perform(prompt, channel_id)
    StreamingAgent.call(prompt: prompt) do |chunk|
      ActionCable.server.broadcast(
        channel_id,
        { type: 'chunk', content: chunk }
      )
    end

    ActionCable.server.broadcast(
      channel_id,
      { type: 'complete' }
    )
  end
end
```

## Best Practices

### Use for Long Responses

Streaming is most beneficial for:
- Long-form content generation
- Conversational interfaces
- Real-time transcription/translation

### Handle Disconnections

```ruby
def stream_response
  StreamingAgent.call(prompt: params[:prompt]) do |chunk|
    break if response.stream.closed?
    response.stream.write "data: #{chunk.to_json}\n\n"
  end
ensure
  response.stream.close
end
```

### Set Appropriate Timeouts

```ruby
class LongFormAgent < ApplicationAgent
  streaming true
  timeout 180  # 3 minutes for long content
end
```

### Monitor TTFT

Track time-to-first-token to ensure good UX:

```ruby
# Alert if TTFT is too high
if execution.time_to_first_token_ms > 1000
  Rails.logger.warn("High TTFT: #{execution.time_to_first_token_ms}ms")
end
```

## Related Pages

- [Agent DSL](Agent-DSL) - Configuration options
- [Execution Tracking](Execution-Tracking) - TTFT analytics
- [Dashboard](Dashboard) - Monitoring streaming metrics
