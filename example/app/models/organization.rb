# frozen_string_literal: true

# Organization model with full LLMTenant DSL demonstration
#
# This model showcases all LLMTenant features:
# - Custom tenant ID (using slug instead of id)
# - Custom display name for budgets
# - Comprehensive budget limits (cost, tokens, executions)
# - Hard enforcement mode
# - API key management per provider
# - Global config inheritance
#
# @example Creating an organization
#   org = Organization.create!(slug: "acme", name: "Acme Corp", plan: "enterprise")
#   org.llm_tenant_id  # => "acme"
#   org.llm_budget     # Auto-created with configured limits
#
# @example Configuring budget manually
#   org.llm_configure_budget do |budget|
#     budget.daily_limit = 200.0
#     budget.enforcement = "hard"
#   end
#
# @example Checking usage
#   org.llm_cost_today            # => 45.23
#   org.llm_tokens_today          # => 125_000
#   org.llm_executions_today      # => 42
#   org.llm_usage_summary         # => { cost: 45.23, tokens: 125_000, ... }
#   org.llm_within_budget?        # => true
#
# @example Using with agents
#   SummaryAgent.call(text: "...", tenant: org)
#
# @see RubyLLM::Agents::LLMTenant
class Organization < ApplicationRecord
  include RubyLLM::Agents::LLMTenant

  # Encrypt API keys at rest (Rails 7+ Active Record Encryption)
  encrypts :openai_api_key, :anthropic_api_key, :gemini_api_key

  # Plans for validation
  PLANS = %w[free starter business enterprise].freeze

  validates :slug, presence: true, uniqueness: true,
                   format: { with: /\A[a-z0-9-]+\z/, message: 'only allows lowercase letters, numbers, and hyphens' }
  validates :name, presence: true
  validates :plan, inclusion: { in: PLANS }

  # LLMTenant DSL Configuration
  #
  # This declares the model as an LLM tenant with:
  # - id: :slug - Use slug column as tenant_id
  # - name: :name - Use name column for budget display name
  # - limits: Default budget limits auto-created for each organization
  # - enforcement: :hard - Reject executions that exceed budget
  # - inherit_global: true - Inherit global config defaults
  # - api_keys: Map providers to model methods/columns
  llm_tenant(
    id: :slug,
    name: :name,
    limits: {
      daily_cost: 100.0,
      monthly_cost: 1000.0,
      daily_tokens: 1_000_000,
      monthly_tokens: 10_000_000,
      daily_executions: 500,
      monthly_executions: 10_000
    },
    enforcement: :hard,
    inherit_global: true,
    api_keys: {
      openai: :openai_api_key,
      anthropic: :anthropic_api_key,
      gemini: :gemini_api_key
    }
  )

  # Scopes
  scope :active, -> { where(active: true) }
  scope :by_plan, ->(plan) { where(plan: plan) }
  scope :enterprise, -> { where(plan: 'enterprise') }

  # Helper to check if enterprise tier
  def enterprise?
    plan == 'enterprise'
  end

  # Helper to check if free tier
  def free?
    plan == 'free'
  end
end
