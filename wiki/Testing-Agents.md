# Testing Agents

Best practices for testing RubyLLM::Agents in your Rails application.

## RSpec Setup

### Basic Configuration

```ruby
# spec/rails_helper.rb
RSpec.configure do |config|
  # Disable async logging in tests
  config.before(:each) do
    RubyLLM::Agents.configure do |c|
      c.async_logging = false
    end
  end
end
```

### Test Support Helpers

```ruby
# spec/support/agent_helpers.rb
module AgentHelpers
  def mock_llm_response(content)
    response = double(
      content: content.to_json,
      input_tokens: 100,
      output_tokens: 50,
      model_id: "gpt-4o"
    )
    allow_any_instance_of(RubyLLM::Chat).to receive(:ask).and_return(response)
  end
end

RSpec.configure do |config|
  config.include AgentHelpers, type: :agent
end
```

## Dry Run Mode

Use `dry_run: true` to test agent configuration without making API calls:

```ruby
RSpec.describe SearchIntentAgent do
  describe ".call" do
    it "builds correct prompts" do
      result = described_class.call(
        query: "red dress under $50",
        dry_run: true
      )

      expect(result[:dry_run]).to be true
      expect(result[:agent]).to eq("SearchIntentAgent")
      expect(result[:model]).to eq("gpt-4o")
      expect(result[:user_prompt]).to include("red dress")
    end

    it "includes schema in dry run" do
      result = described_class.call(query: "test", dry_run: true)

      expect(result[:schema]).to be_present
    end
  end
end
```

### Dry Run Response Structure

```ruby
result = MyAgent.call(params, dry_run: true)

result[:dry_run]       # => true
result[:agent]         # => "MyAgent"
result[:model]         # => "gpt-4o"
result[:temperature]   # => 0.0
result[:system_prompt] # => "You are..."
result[:user_prompt]   # => "Process: ..."
result[:schema]        # => #<RubyLLM::Schema...>
result[:tools]         # => [SearchTool, ...]
result[:attachments]   # => ["image.png"]
```

## Mocking LLM Responses

### Basic Mocking

```ruby
RSpec.describe SearchIntentAgent do
  describe ".call" do
    let(:mock_response) do
      {
        refined_query: "red dress",
        filters: ["color:red", "price:<50"],
        confidence: 0.95
      }
    end

    before do
      allow_any_instance_of(RubyLLM::Chat).to receive(:ask).and_return(
        double(
          content: mock_response.to_json,
          input_tokens: 100,
          output_tokens: 50,
          model_id: "gpt-4o"
        )
      )
    end

    it "extracts search intent" do
      result = described_class.call(query: "red dress under $50")

      expect(result.content[:refined_query]).to eq("red dress")
      expect(result.content[:filters]).to include("color:red")
    end
  end
end
```

### Using RSpec Doubles

```ruby
RSpec.describe ContentAgent do
  let(:chat_instance) { instance_double(RubyLLM::Chat) }

  before do
    allow(RubyLLM).to receive(:chat).and_return(chat_instance)
    allow(chat_instance).to receive(:with_model).and_return(chat_instance)
    allow(chat_instance).to receive(:with_temperature).and_return(chat_instance)
    allow(chat_instance).to receive(:ask).and_return(mock_response)
  end

  let(:mock_response) do
    double(
      content: { title: "Test", body: "Content" }.to_json,
      input_tokens: 200,
      output_tokens: 100,
      model_id: "gpt-4o"
    )
  end

  it "generates content" do
    result = described_class.call(topic: "Testing")
    expect(result.content[:title]).to eq("Test")
  end
end
```

## Testing Reliability Features

### Testing Retries

```ruby
RSpec.describe ReliableAgent do
  it "retries on transient failures" do
    call_count = 0

    allow_any_instance_of(RubyLLM::Chat).to receive(:ask) do
      call_count += 1
      if call_count < 3
        raise Faraday::TimeoutError
      else
        double(content: { result: "success" }.to_json, input_tokens: 100, output_tokens: 50)
      end
    end

    result = described_class.call(query: "test")

    expect(result.success?).to be true
    expect(result.attempts_count).to eq(3)
  end
end
```

### Testing Fallbacks

```ruby
RSpec.describe FallbackAgent do
  it "falls back to secondary model" do
    primary_called = false

    allow_any_instance_of(RubyLLM::Chat).to receive(:ask) do |chat|
      if chat.model_id == "gpt-4o"
        primary_called = true
        raise RubyLLM::RateLimitError
      else
        double(content: { result: "fallback" }.to_json, input_tokens: 50, output_tokens: 25)
      end
    end

    result = described_class.call(query: "test")

    expect(primary_called).to be true
    expect(result.used_fallback?).to be true
    expect(result.chosen_model_id).to eq("gpt-4o-mini")
  end
end
```

### Testing Circuit Breakers

```ruby
RSpec.describe CircuitBreakerAgent do
  before do
    # Reset circuit breaker state
    RubyLLM::Agents::CircuitBreaker.reset_all
  end

  it "opens circuit after threshold errors" do
    allow_any_instance_of(RubyLLM::Chat).to receive(:ask)
      .and_raise(Faraday::ConnectionFailed)

    # Trip the circuit breaker
    10.times do
      described_class.call(query: "test") rescue nil
    end

    expect {
      described_class.call(query: "test")
    }.to raise_error(RubyLLM::Agents::CircuitBreakerOpenError)
  end
end
```

## VCR and WebMock Patterns

### VCR Configuration

```ruby
# spec/support/vcr.rb
VCR.configure do |config|
  config.cassette_library_dir = "spec/cassettes"
  config.hook_into :webmock
  config.configure_rspec_metadata!

  # Filter sensitive data
  config.filter_sensitive_data("<OPENAI_API_KEY>") { ENV["OPENAI_API_KEY"] }
  config.filter_sensitive_data("<ANTHROPIC_API_KEY>") { ENV["ANTHROPIC_API_KEY"] }
end
```

### Using VCR with Agents

```ruby
RSpec.describe SearchAgent, :vcr do
  it "searches successfully", vcr: { cassette_name: "search_agent/success" } do
    result = described_class.call(query: "ruby programming")

    expect(result.success?).to be true
    expect(result.content[:results]).to be_present
  end
end
```

### WebMock Direct

```ruby
RSpec.describe MyAgent do
  before do
    stub_request(:post, "https://api.openai.com/v1/chat/completions")
      .to_return(
        status: 200,
        body: {
          choices: [{ message: { content: '{"result": "test"}' } }],
          usage: { prompt_tokens: 100, completion_tokens: 50 }
        }.to_json,
        headers: { "Content-Type" => "application/json" }
      )
  end

  it "makes API call" do
    result = described_class.call(query: "test")
    expect(result.success?).to be true
  end
end
```

## Testing Execution Logging

```ruby
RSpec.describe "Execution logging" do
  it "creates execution record" do
    mock_llm_response({ result: "success" })

    expect {
      MyAgent.call(query: "test")
    }.to change(RubyLLM::Agents::Execution, :count).by(1)

    execution = RubyLLM::Agents::Execution.last
    expect(execution.agent_type).to eq("MyAgent")
    expect(execution.status).to eq("success")
  end

  it "logs errors" do
    allow_any_instance_of(RubyLLM::Chat).to receive(:ask)
      .and_raise(StandardError, "API Error")

    expect {
      MyAgent.call(query: "test") rescue nil
    }.to change(RubyLLM::Agents::Execution, :count).by(1)

    execution = RubyLLM::Agents::Execution.last
    expect(execution.status).to eq("error")
    expect(execution.error_message).to include("API Error")
  end
end
```

## Testing with Factories

```ruby
# spec/factories/executions.rb
FactoryBot.define do
  factory :execution, class: "RubyLLM::Agents::Execution" do
    agent_type { "TestAgent" }
    model_id { "gpt-4o" }
    status { "success" }
    input_tokens { 100 }
    output_tokens { 50 }
    total_cost { 0.00025 }
    duration_ms { 500 }

    trait :failed do
      status { "error" }
      error_message { "Something went wrong" }
    end

    trait :with_fallback do
      chosen_model_id { "gpt-4o-mini" }
      attempts_count { 2 }
      fallback_chain { ["gpt-4o", "gpt-4o-mini"] }
    end
  end
end
```

## Integration Testing

### Controller Integration

```ruby
RSpec.describe SearchController, type: :controller do
  describe "POST #search" do
    before do
      mock_llm_response({ results: ["item1", "item2"] })
    end

    it "returns search results" do
      post :search, params: { query: "test" }

      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)["results"]).to be_present
    end
  end
end
```

### System Tests

```ruby
RSpec.describe "Search", type: :system do
  before do
    # Use dry_run for system tests to avoid API calls
    allow_any_instance_of(SearchAgent).to receive(:call)
      .and_wrap_original do |method, *args|
        if Rails.env.test?
          # Return mock result
          RubyLLM::Agents::Result.new(
            content: { results: ["Mock result"] },
            success: true
          )
        else
          method.call(*args)
        end
      end
  end

  it "displays search results" do
    visit search_path
    fill_in "Query", with: "test query"
    click_button "Search"

    expect(page).to have_content("Mock result")
  end
end
```

## Best Practices

1. **Use dry_run for configuration tests** - Verify prompts and parameters without API calls
2. **Mock at the RubyLLM level** - Mock `RubyLLM::Chat#ask` for most tests
3. **Use VCR for integration tests** - Record real responses for critical paths
4. **Reset state between tests** - Clear circuit breakers and caches
5. **Test error paths** - Verify retry, fallback, and error handling behavior
6. **Disable async logging** - Ensure execution records are created synchronously

## Related Pages

- [Agent DSL](Agent-DSL) - Agent configuration
- [Result Object](Result-Object) - Understanding results
- [Error Handling](Error-Handling) - Error types
- [Reliability](Reliability) - Retries and fallbacks
