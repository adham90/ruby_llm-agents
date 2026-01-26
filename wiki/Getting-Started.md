# Getting Started with RubyLLM::Agents

This guide walks you through installing RubyLLM::Agents and creating your first AI-powered agent in a Rails application.

## Prerequisites

Before you begin, ensure you have:

- **Ruby** >= 3.1.0
- **Rails** >= 7.0
- An API key for at least one LLM provider:
  - [OpenAI](https://platform.openai.com/api-keys)
  - [Anthropic](https://console.anthropic.com/)
  - [Google AI](https://aistudio.google.com/app/apikey)

## Quick Installation

### Step 1: Add the Gem

Add to your `Gemfile`:

```ruby
gem "ruby_llm-agents"
```

### Step 2: Install Dependencies

```bash
bundle install
```

### Step 3: Run the Generator

```bash
rails generate ruby_llm_agents:install
rails db:migrate
```

This creates:
- `db/migrate/xxx_create_ruby_llm_agents_executions.rb` - Database table for tracking
- `config/initializers/ruby_llm_agents.rb` - Configuration file
- `app/agents/application_agent.rb` - Base class for your agents
- Route mount at `/agents` for the dashboard

### Step 4: Configure API Keys

Set up your API keys in environment variables:

```bash
# .env (using dotenv-rails)
OPENAI_API_KEY=sk-...
ANTHROPIC_API_KEY=sk-ant-...
GOOGLE_API_KEY=...
```

Or using Rails credentials:

```bash
rails credentials:edit
```

```yaml
openai:
  api_key: sk-...
anthropic:
  api_key: sk-ant-...
google:
  api_key: ...
```

## Your First Agent

### Generate an Agent

```bash
rails generate ruby_llm_agents:agent Summarizer text:required max_length:500
```

This creates `app/agents/summarizer_agent.rb`:

```ruby
class SummarizerAgent < ApplicationAgent
  model "gemini-2.0-flash"
  temperature 0.0
  version "1.0"

  param :text, required: true
  param :max_length, default: 500

  private

  def system_prompt
    <<~PROMPT
      You are a summarization assistant. Create concise summaries
      that capture the key points while staying under the word limit.
    PROMPT
  end

  def user_prompt
    <<~PROMPT
      Summarize the following text in under #{max_length} words:

      #{text}
    PROMPT
  end
end
```

### Call the Agent

```ruby
# In your Rails console or controller
result = SummarizerAgent.call(
  text: "Long article text here...",
  max_length: 200
)

# Access the response
puts result.content  # The summary text

# Access metadata
puts result.total_tokens   # => 150
puts result.total_cost     # => 0.00025
puts result.duration_ms    # => 850
puts result.model_id       # => "gemini-2.0-flash"
```

### View in Dashboard

Visit `http://localhost:3000/agents` to see:
- Execution history
- Token usage
- Costs
- Performance metrics

## Next Steps

Now that you have your first agent running:

1. **[Agent DSL](Agent-DSL)** - Learn all configuration options
2. **[Prompts and Schemas](Prompts-and-Schemas)** - Structure your outputs
3. **[Reliability](Reliability)** - Add retries and fallbacks
4. **[Dashboard](Dashboard)** - Set up authentication
5. **[Examples](Examples)** - See real-world use cases

## Detailed Guides

- **[Installation](Installation)** - Platform-specific setup instructions
- **[Configuration](Configuration)** - All configuration options
- **[First Agent](First-Agent)** - Detailed agent tutorial
