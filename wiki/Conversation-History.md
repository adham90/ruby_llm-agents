# Conversation History

Build multi-turn conversational agents by providing message history to your agents.

## Overview

Conversation history allows agents to maintain context across multiple turns, enabling:
- **ChatBots** - Build conversational interfaces with memory
- **Follow-up Questions** - Handle "What about X?" style queries
- **Context Accumulation** - Build on previous responses

## Quick Start

```ruby
result = ChatAgent.call(
  query: "What's my name?",
  messages: [
    { role: :user, content: "My name is Alice" },
    { role: :assistant, content: "Nice to meet you, Alice!" }
  ]
)

result.content  # => "Your name is Alice!"
```

## Three Approaches

### 1. Call-Time Messages

Pass messages directly when calling the agent:

```ruby
SearchAgent.call(
  query: "Find more like this",
  messages: [
    { role: :user, content: "I'm looking for sci-fi books" },
    { role: :assistant, content: "Here are some sci-fi recommendations..." }
  ]
)
```

**Best for:** One-off calls with dynamic history, testing, simple integrations.

### 2. Chainable Method

Use `with_messages` for a fluent interface:

```ruby
agent = ChatAgent.new(query: "Continue please")

agent.with_messages([
  { role: :user, content: "Tell me a joke" },
  { role: :assistant, content: "Why did the chicken cross the road?" }
]).call
```

**Best for:** Building conversation flows, conditional message injection.

### 3. Template Method Override

Override the `messages` method in your agent class:

```ruby
class CustomerSupportAgent < ApplicationAgent
  model "gpt-4o"

  param :conversation_id, required: true
  param :message, required: true

  def user_prompt
    message
  end

  # Template method - override to provide conversation history
  def messages
    Conversation.find(conversation_id).messages.map do |msg|
      { role: msg.role.to_sym, content: msg.content }
    end
  end
end

# Usage
CustomerSupportAgent.call(
  conversation_id: 123,
  message: "I need help with my order"
)
```

**Best for:** Database-backed conversations, complex message loading logic.

## Message Format

Each message is a hash with two keys:

```ruby
{
  role: :user,           # Required: :user, :assistant, or :system
  content: "Hello!"      # Required: The message text
}
```

### Role Types

| Role | Description | Example Use |
|------|-------------|-------------|
| `:user` | Messages from the user | Questions, requests |
| `:assistant` | Messages from the AI | Previous responses |
| `:system` | System context messages | Additional instructions |

### Example Conversation

```ruby
messages = [
  { role: :system, content: "The user prefers concise answers" },
  { role: :user, content: "What's the weather like?" },
  { role: :assistant, content: "It's sunny and 72F today." },
  { role: :user, content: "Should I bring an umbrella?" },
  { role: :assistant, content: "No, the forecast shows no rain." }
]
```

## Priority Resolution

When messages are specified in multiple places, this priority applies:

1. **`with_messages`** - Highest priority (override)
2. **Call-time `messages:`** - Medium priority (options)
3. **Template method** - Default (class definition)

```ruby
class MyAgent < ApplicationAgent
  def messages
    [{ role: :user, content: "Default history" }]  # Priority 3
  end
end

# Call-time messages override template method
MyAgent.call(
  query: "test",
  messages: [{ role: :user, content: "Call-time history" }]  # Priority 2
)

# with_messages overrides everything
agent = MyAgent.new(query: "test")
agent.with_messages([{ role: :user, content: "Override history" }])  # Priority 1
agent.call
```

## Use Cases

### ChatBot with Database Persistence

```ruby
class ChatAgent < ApplicationAgent
  model "gpt-4o"
  temperature 0.7

  param :conversation_id, required: true
  param :user_message, required: true

  def system_prompt
    "You are a helpful assistant. Be concise and friendly."
  end

  def user_prompt
    user_message
  end

  def messages
    conversation.chat_messages.order(:created_at).map do |msg|
      { role: msg.role.to_sym, content: msg.content }
    end
  end

  private

  def conversation
    @conversation ||= Conversation.find(conversation_id)
  end
end

# In your controller
class ChatsController < ApplicationController
  def create
    result = ChatAgent.call(
      conversation_id: params[:conversation_id],
      user_message: params[:message]
    )

    # Save the exchange
    @conversation.chat_messages.create!(role: :user, content: params[:message])
    @conversation.chat_messages.create!(role: :assistant, content: result.content)

    render json: { response: result.content }
  end
end
```

### Context-Aware Agent

```ruby
class ContextAwareAgent < ApplicationAgent
  param :context_type, required: true
  param :query, required: true

  def messages
    case context_type
    when :technical
      technical_context
    when :billing
      billing_context
    else
      []
    end
  end

  private

  def technical_context
    [
      { role: :system, content: "User is asking about technical issues" },
      { role: :assistant, content: "I can help with technical questions." }
    ]
  end

  def billing_context
    [
      { role: :system, content: "User is asking about billing" },
      { role: :assistant, content: "I can help with billing inquiries." }
    ]
  end
end
```

### Session-Based Conversations

```ruby
class SessionChatAgent < ApplicationAgent
  param :session_messages, default: []
  param :query, required: true

  def user_prompt
    query
  end

  def messages
    session_messages.map do |msg|
      { role: msg[:role].to_sym, content: msg[:content] }
    end
  end
end

# In a Rails controller with session storage
class ChatController < ApplicationController
  def chat
    session[:messages] ||= []

    result = SessionChatAgent.call(
      query: params[:message],
      session_messages: session[:messages]
    )

    # Update session
    session[:messages] << { role: :user, content: params[:message] }
    session[:messages] << { role: :assistant, content: result.content }

    render json: { response: result.content }
  end
end
```

## Best Practices

### Keep History Manageable

Long conversation histories increase token usage and costs. Consider:

```ruby
def messages
  # Only keep last 10 messages
  conversation.messages.order(:created_at).last(10).map do |msg|
    { role: msg.role.to_sym, content: msg.content }
  end
end
```

### Summarize Old Context

For long conversations, summarize older messages:

```ruby
def messages
  recent = conversation.messages.last(5)
  older = conversation.messages.where.not(id: recent.pluck(:id))

  summary_messages = []
  if older.any?
    summary_messages << {
      role: :system,
      content: "Summary of earlier conversation: #{conversation.summary}"
    }
  end

  summary_messages + recent.map { |m| { role: m.role.to_sym, content: m.content } }
end
```

### Validate Message Format

```ruby
def messages
  raw_messages.map do |msg|
    raise ArgumentError, "Invalid role" unless [:user, :assistant, :system].include?(msg[:role])
    raise ArgumentError, "Content required" if msg[:content].blank?
    msg
  end
end
```

## Related Pages

- [Agent DSL](Agent-DSL) - Full DSL reference
- [Prompts and Schemas](Prompts-and-Schemas) - Crafting prompts
- [Streaming](Streaming) - Real-time responses
- [Examples](Examples) - More use cases
