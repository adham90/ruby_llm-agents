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
    cache_creation_tokens { 0 }
    input_cost { 0.003 }
    output_cost { 0.006 }
    total_cost { 0.009 }
    parameters { { query: "test query" } }
    response { { content: "test response" } }
    metadata { { query: "test query" } }
    tool_calls { [] }
    tool_calls_count { 0 }

    trait :failed do
      status { "error" }
      error_class { "StandardError" }
      error_message { "Something went wrong" }
    end

    trait :timeout do
      status { "timeout" }
      error_class { "Timeout::Error" }
      error_message { "Request timed out" }
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
      tool_calls do
        [
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
      end
      tool_calls_count { 2 }
      finish_reason { "tool_calls" }
    end
  end
end
