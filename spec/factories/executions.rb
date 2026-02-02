# frozen_string_literal: true

FactoryBot.define do
  factory :execution, class: "RubyLLM::Agents::Execution" do
    agent_type { "TestAgent" }
    agent_version { "1.0" }
    model_id { "gpt-4" }
    temperature { 0.5 }
    started_at { 1.minute.ago }
    completed_at { Time.current }
    duration_ms { 1500 }
    status { "success" }
    input_tokens { 100 }
    output_tokens { 50 }
    total_tokens { 150 }
    cached_tokens { 0 }
    input_cost { 0.003 }
    output_cost { 0.006 }
    total_cost { 0.009 }
    tool_calls_count { 0 }
    metadata { { query: "test query" } }

    # Create a detail record with default values after creation
    after(:create) do |execution|
      unless execution.detail.present?
        execution.create_detail!(
          parameters: { query: "test query" },
          response: { content: "test response" },
          tool_calls: [],
          cache_creation_tokens: 0
        )
      end
    end

    trait :failed do
      status { "error" }
      error_class { "StandardError" }
      after(:create) do |execution|
        execution.detail&.update!(error_message: "Something went wrong") ||
          execution.create_detail!(error_message: "Something went wrong")
      end
    end

    trait :timeout do
      status { "timeout" }
      error_class { "Timeout::Error" }
      after(:create) do |execution|
        execution.detail&.update!(error_message: "Request timed out") ||
          execution.create_detail!(error_message: "Request timed out")
      end
    end

    trait :expensive do
      input_tokens { 50_000 }
      output_tokens { 10_000 }
      total_tokens { 60_000 }
      input_cost { 1.50 }
      output_cost { 1.20 }
      total_cost { 2.70 }
    end

    trait :slow do
      duration_ms { 15_000 }
    end

    trait :yesterday do
      created_at { 1.day.ago }
      started_at { 1.day.ago - 1.minute }
      completed_at { 1.day.ago }
    end

    trait :last_week do
      created_at { 5.days.ago }
      started_at { 5.days.ago - 1.minute }
      completed_at { 5.days.ago }
    end

    trait :with_tool_calls do
      tool_calls_count { 2 }
      finish_reason { "tool_calls" }
      after(:create) do |execution|
        tool_calls_data = [
          {
            "id" => "call_abc123",
            "name" => "search_database",
            "arguments" => { "query" => "test" }
          },
          {
            "id" => "call_def456",
            "name" => "format_response",
            "arguments" => { "format" => "json" }
          }
        ]
        execution.detail ? execution.detail.update!(tool_calls: tool_calls_data) :
          execution.create_detail!(tool_calls: tool_calls_data)
      end
    end

    trait :with_many_tool_calls do
      tool_calls_count { 5 }
      finish_reason { "tool_calls" }
      after(:create) do |execution|
        tool_calls_data = [
          { "id" => "call_001", "name" => "tool_one", "arguments" => { "arg" => "value1" } },
          { "id" => "call_002", "name" => "tool_two", "arguments" => { "arg" => "value2" } },
          { "id" => "call_003", "name" => "tool_three", "arguments" => { "arg" => "value3" } },
          { "id" => "call_004", "name" => "tool_four", "arguments" => { "arg" => "value4" } },
          { "id" => "call_005", "name" => "tool_five", "arguments" => { "arg" => "value5" } }
        ]
        execution.detail ? execution.detail.update!(tool_calls: tool_calls_data) :
          execution.create_detail!(tool_calls: tool_calls_data)
      end
    end

    trait :with_single_tool_call do
      tool_calls_count { 1 }
      finish_reason { "tool_calls" }
      after(:create) do |execution|
        tool_calls_data = [
          { "id" => "call_single", "name" => "single_tool", "arguments" => { "key" => "value" } }
        ]
        execution.detail ? execution.detail.update!(tool_calls: tool_calls_data) :
          execution.create_detail!(tool_calls: tool_calls_data)
      end
    end

    trait :with_tool_calls_no_args do
      tool_calls_count { 1 }
      finish_reason { "tool_calls" }
      after(:create) do |execution|
        tool_calls_data = [
          { "id" => "call_no_args", "name" => "tool_without_args", "arguments" => {} }
        ]
        execution.detail ? execution.detail.update!(tool_calls: tool_calls_data) :
          execution.create_detail!(tool_calls: tool_calls_data)
      end
    end

    trait :with_symbol_key_tool_calls do
      tool_calls_count { 1 }
      finish_reason { "tool_calls" }
      after(:create) do |execution|
        tool_calls_data = [
          { id: "call_sym_123", name: "symbol_tool", arguments: { key: "value" } }
        ]
        execution.detail ? execution.detail.update!(tool_calls: tool_calls_data) :
          execution.create_detail!(tool_calls: tool_calls_data)
      end
    end

    trait :with_enhanced_tool_calls do
      tool_calls_count { 2 }
      finish_reason { "tool_calls" }
      after(:create) do |execution|
        tool_calls_data = [
          {
            "id" => "call_enhanced_1",
            "name" => "weather_lookup",
            "arguments" => { "city" => "Paris" },
            "result" => "15°C, partly cloudy",
            "status" => "success",
            "error_message" => nil,
            "duration_ms" => 245,
            "called_at" => "2025-01-27T10:30:45.123Z",
            "completed_at" => "2025-01-27T10:30:45.368Z"
          },
          {
            "id" => "call_enhanced_2",
            "name" => "database_query",
            "arguments" => { "sql" => "SELECT * FROM users" },
            "result" => "[{\"id\": 1, \"name\": \"Alice\"}]",
            "status" => "success",
            "error_message" => nil,
            "duration_ms" => 89,
            "called_at" => "2025-01-27T10:30:45.400Z",
            "completed_at" => "2025-01-27T10:30:45.489Z"
          }
        ]
        execution.detail ? execution.detail.update!(tool_calls: tool_calls_data) :
          execution.create_detail!(tool_calls: tool_calls_data)
      end
    end

    trait :with_enhanced_tool_call_error do
      tool_calls_count { 1 }
      finish_reason { "tool_calls" }
      after(:create) do |execution|
        tool_calls_data = [
          {
            "id" => "call_error_1",
            "name" => "api_call",
            "arguments" => { "endpoint" => "/users" },
            "result" => nil,
            "status" => "error",
            "error_message" => "ConnectionError: Failed to connect to API",
            "duration_ms" => 5023,
            "called_at" => "2025-01-27T10:30:45.123Z",
            "completed_at" => "2025-01-27T10:30:50.146Z"
          }
        ]
        execution.detail ? execution.detail.update!(tool_calls: tool_calls_data) :
          execution.create_detail!(tool_calls: tool_calls_data)
      end
    end

    trait :with_legacy_tool_calls do
      tool_calls_count { 1 }
      finish_reason { "tool_calls" }
      after(:create) do |execution|
        tool_calls_data = [
          {
            "id" => "call_legacy_1",
            "name" => "old_tool",
            "arguments" => { "param" => "value" }
          }
        ]
        execution.detail ? execution.detail.update!(tool_calls: tool_calls_data) :
          execution.create_detail!(tool_calls: tool_calls_data)
      end
    end

    trait :with_tenant do
      sequence(:tenant_id) { |n| "tenant_#{n}" }
    end

    trait :with_thinking do
      thinking_content { "Let me think through this step by step..." }
      model_id { "claude-3-5-sonnet-20241022" }
    end

    trait :streaming do
      streamed { true }
      finish_reason { "stop" }
    end

    trait :cached do
      cache_hit { true }
      input_tokens { 0 }
      output_tokens { 0 }
      total_tokens { 0 }
      input_cost { 0 }
      output_cost { 0 }
      total_cost { 0 }
      metadata { { response_cache_key: "ruby_llm_agent/TestAgent/v1.0/#{SecureRandom.hex(8)}" } }
    end

    trait :with_moderation do
      moderation_flagged { false }
      moderation_result do
        {
          "flagged" => false,
          "categories" => { "hate" => false, "violence" => false },
          "scores" => { "hate" => 0.001, "violence" => 0.002 }
        }
      end
    end

    trait :moderation_flagged do
      moderation_flagged { true }
      moderation_result do
        {
          "flagged" => true,
          "categories" => { "hate" => true, "violence" => false },
          "scores" => { "hate" => 0.95, "violence" => 0.001 }
        }
      end
    end

    trait :running do
      status { "running" }
      completed_at { nil }
      duration_ms { nil }
    end

    trait :anthropic do
      model_id { "claude-3-5-sonnet-20241022" }
    end

    trait :openai do
      model_id { "gpt-4o" }
    end

    trait :workflow do
      workflow_id { SecureRandom.uuid }
      workflow_type { "workflow" }
      model_id { "workflow" }
    end

    trait :image_generation do
      agent_type { "ImageGenerator" }
      model_id { "dall-e-3" }
      metadata { { prompt: "A sunset over mountains", size: "1024x1024" } }
    end

    trait :embedding do
      agent_type { "Embedder" }
      model_id { "text-embedding-3-small" }
      input_tokens { 50 }
      output_tokens { 0 }
      total_tokens { 50 }
    end

    trait :this_month do
      created_at { Time.current.beginning_of_month + 1.day }
      started_at { Time.current.beginning_of_month + 1.day }
      completed_at { Time.current.beginning_of_month + 1.day + 1.second }
    end

    trait :last_month do
      created_at { 1.month.ago }
      started_at { 1.month.ago }
      completed_at { 1.month.ago + 1.second }
    end
  end
end
