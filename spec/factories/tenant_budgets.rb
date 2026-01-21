# frozen_string_literal: true

FactoryBot.define do
  factory :tenant_budget, class: "RubyLLM::Agents::TenantBudget" do
    sequence(:tenant_id) { |n| "tenant_#{n}" }
    enforcement { "soft" }
    inherit_global_defaults { true }

    trait :with_cost_limits do
      daily_limit { 50.0 }
      monthly_limit { 500.0 }
    end

    trait :with_token_limits do
      daily_token_limit { 1_000_000 }
      monthly_token_limit { 10_000_000 }
    end

    trait :with_execution_limits do
      daily_execution_limit { 500 }
      monthly_execution_limit { 10_000 }
    end

    trait :with_all_limits do
      with_cost_limits
      with_token_limits
      with_execution_limits
    end

    trait :hard_enforcement do
      enforcement { "hard" }
    end

    trait :soft_enforcement do
      enforcement { "soft" }
    end

    trait :no_enforcement do
      enforcement { "none" }
    end

    trait :no_inheritance do
      inherit_global_defaults { false }
    end

    trait :with_per_agent_limits do
      per_agent_daily { { "TestAgent" => 10.0, "ExpensiveAgent" => 25.0 } }
      per_agent_monthly { { "TestAgent" => 100.0, "ExpensiveAgent" => 250.0 } }
    end

    trait :strict do
      hard_enforcement
      with_all_limits
      with_per_agent_limits
    end

    trait :generous do
      soft_enforcement
      daily_limit { 1000.0 }
      monthly_limit { 10_000.0 }
      daily_token_limit { 100_000_000 }
      monthly_token_limit { 1_000_000_000 }
    end

    trait :minimal do
      no_enforcement
      daily_limit { nil }
      monthly_limit { nil }
      daily_token_limit { nil }
      monthly_token_limit { nil }
    end
  end
end
