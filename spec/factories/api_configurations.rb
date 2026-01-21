# frozen_string_literal: true

FactoryBot.define do
  factory :api_configuration, class: "RubyLLM::Agents::ApiConfiguration" do
    scope_type { "global" }
    scope_id { nil }

    trait :global do
      scope_type { "global" }
      scope_id { nil }
    end

    trait :tenant do
      scope_type { "tenant" }
      sequence(:scope_id) { |n| "tenant_#{n}" }
    end

    trait :with_openai do
      openai_api_key { "sk-test-openai-#{SecureRandom.hex(8)}" }
    end

    trait :with_anthropic do
      anthropic_api_key { "sk-ant-#{SecureRandom.hex(16)}" }
    end

    trait :with_gemini do
      gemini_api_key { "AIza#{SecureRandom.hex(32)}" }
    end

    trait :with_deepseek do
      deepseek_api_key { "sk-deepseek-#{SecureRandom.hex(8)}" }
    end

    trait :with_all_providers do
      with_openai
      with_anthropic
      with_gemini
      with_deepseek
    end

    trait :with_default_model do
      default_model { "gpt-4o" }
    end

    trait :with_default_temperature do
      default_temperature { 0.7 }
    end

    trait :with_default_max_tokens do
      default_max_tokens { 4096 }
    end

    trait :complete do
      with_all_providers
      with_default_model
      with_default_temperature
      with_default_max_tokens
    end
  end
end
