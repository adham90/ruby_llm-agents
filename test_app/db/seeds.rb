# frozen_string_literal: true

# Seeds for testing ruby_llm-agents with Organizations and LLMTenant DSL
#
# This seed file demonstrates:
# - Organization model with full LLMTenant DSL
# - llm_configure_budget block syntax
# - All limit types (cost, tokens, executions)
# - All enforcement modes (none, soft, hard)
# - Usage tracking methods
# - Various agent executions including showcase agents
#
# Run with: bin/rails db:seed
# Reset and reseed: bin/rails db:seed:replant

puts "Seeding test data for ruby_llm-agents..."

# Helper to generate realistic execution data
def create_execution(attrs = {})
  defaults = {
    agent_version: "1.0",
    model_id: "gpt-4o-mini",
    model_provider: "openai",
    temperature: 0.7,
    status: "success",
    started_at: Time.current - rand(1..60).minutes,
    input_tokens: rand(100..2000),
    output_tokens: rand(50..1000),
    streaming: [true, false].sample
  }

  merged = defaults.merge(attrs)

  # Calculate derived fields
  merged[:completed_at] ||= merged[:started_at] + rand(500..5000) / 1000.0 if merged[:status] != "running"
  merged[:duration_ms] ||= ((merged[:completed_at] - merged[:started_at]) * 1000).to_i if merged[:completed_at]
  merged[:total_tokens] = (merged[:input_tokens] || 0) + (merged[:output_tokens] || 0)

  # Calculate costs (approximate)
  input_price = case merged[:model_id]
                when /gpt-4o-mini/ then 0.15
                when /gpt-4o/ then 5.0
                when /claude/ then 3.0
                when /gemini/ then 0.075
                else 1.0
                end
  output_price = input_price * 4

  merged[:input_cost] = ((merged[:input_tokens] || 0) / 1_000_000.0 * input_price).round(6)
  merged[:output_cost] = ((merged[:output_tokens] || 0) / 1_000_000.0 * output_price).round(6)
  merged[:total_cost] = merged[:input_cost] + merged[:output_cost]

  RubyLLM::Agents::Execution.create!(merged)
end

# Clear existing data
puts "Clearing existing data..."
RubyLLM::Agents::Execution.destroy_all
RubyLLM::Agents::TenantBudget.destroy_all if RubyLLM::Agents::TenantBudget.table_exists?
Organization.destroy_all if defined?(Organization) && Organization.table_exists?

# =============================================================================
# ORGANIZATIONS (with LLMTenant DSL)
# =============================================================================
puts "\n" + "=" * 60
puts "Creating Organizations with LLMTenant..."
puts "=" * 60

# Organization 1: Acme Corp - Enterprise customer with high limits
# Demonstrates: Full configuration, hard enforcement, multiple API keys
acme = Organization.create!(
  slug: "acme-corp",
  name: "Acme Corporation",
  plan: "enterprise",
  industry: "Technology",
  employee_count: 500,
  openai_api_key: "sk-demo-acme-openai-key",
  anthropic_api_key: "sk-ant-demo-acme-key",
  gemini_api_key: nil,
  active: true
)

# Manually configure budget to demonstrate llm_configure_budget block
acme.llm_configure_budget do |budget|
  budget.daily_limit = 200.0
  budget.monthly_limit = 4000.0
  budget.daily_token_limit = 2_000_000
  budget.monthly_token_limit = 40_000_000
  budget.daily_execution_limit = 1000
  budget.monthly_execution_limit = 20_000
  budget.enforcement = "hard"
  budget.inherit_global_defaults = true
  budget.per_agent_daily = {
    "FullFeaturedAgent" => 50.0,
    "ToolsAgent" => 30.0
  }
end
puts "  Created: #{acme.name} (#{acme.slug}) - Enterprise, hard enforcement"

# Organization 2: Startup Inc - Budget-conscious with soft enforcement
# Demonstrates: Soft enforcement, lower limits
startup = Organization.create!(
  slug: "startup-inc",
  name: "Startup Inc",
  plan: "starter",
  industry: "SaaS",
  employee_count: 25,
  openai_api_key: "sk-demo-startup-openai",
  active: true
)

startup.llm_configure_budget do |budget|
  budget.daily_limit = 25.0
  budget.monthly_limit = 500.0
  budget.daily_token_limit = 500_000
  budget.monthly_token_limit = 10_000_000
  budget.daily_execution_limit = 100
  budget.monthly_execution_limit = 2000
  budget.enforcement = "soft"
end
puts "  Created: #{startup.name} (#{startup.slug}) - Starter, soft enforcement"

# Organization 3: Enterprise Plus - Premium unlimited
# Demonstrates: No enforcement, high limits
enterprise = Organization.create!(
  slug: "enterprise-plus",
  name: "Enterprise Plus Global",
  plan: "enterprise",
  industry: "Finance",
  employee_count: 5000,
  openai_api_key: "sk-demo-enterprise-openai",
  anthropic_api_key: "sk-ant-demo-enterprise",
  gemini_api_key: "gemini-demo-enterprise",
  active: true
)

enterprise.llm_configure_budget do |budget|
  budget.daily_limit = 10000.0
  budget.monthly_limit = 200000.0
  budget.enforcement = "none"
  budget.inherit_global_defaults = false
end
puts "  Created: #{enterprise.name} (#{enterprise.slug}) - Enterprise, no enforcement"

# Organization 4: Demo Account - Strict limits for demos
# Demonstrates: Hard enforcement with very low limits
demo = Organization.create!(
  slug: "demo-account",
  name: "Demo Account",
  plan: "free",
  industry: "Demo",
  employee_count: 1,
  active: true
)

demo.llm_configure_budget do |budget|
  budget.daily_limit = 5.0
  budget.monthly_limit = 50.0
  budget.daily_token_limit = 50_000
  budget.monthly_token_limit = 500_000
  budget.daily_execution_limit = 20
  budget.monthly_execution_limit = 200
  budget.enforcement = "hard"
end
puts "  Created: #{demo.name} (#{demo.slug}) - Free, hard enforcement (demo limits)"

# Organization 5: Token Focused - Only token-based limits
# Demonstrates: Token limits without cost limits
token_focused = Organization.create!(
  slug: "token-focused",
  name: "Token Focused Corp",
  plan: "business",
  industry: "Healthcare",
  employee_count: 100,
  openai_api_key: "sk-demo-token-focused",
  active: true
)

token_focused.llm_configure_budget do |budget|
  budget.daily_limit = nil
  budget.monthly_limit = nil
  budget.daily_token_limit = 1_000_000
  budget.monthly_token_limit = 20_000_000
  budget.daily_execution_limit = nil
  budget.monthly_execution_limit = nil
  budget.enforcement = "soft"
end
puts "  Created: #{token_focused.name} (#{token_focused.slug}) - Business, token-only limits"

# =============================================================================
# Display LLMTenant DSL Methods
# =============================================================================
puts "\n" + "=" * 60
puts "Demonstrating LLMTenant DSL Methods..."
puts "=" * 60

puts "\nAcme Corp LLMTenant info:"
puts "  llm_tenant_id: #{acme.llm_tenant_id}"
puts "  llm_api_keys: #{acme.llm_api_keys.keys.inspect}"
puts "  llm_budget.enforcement: #{acme.llm_budget.enforcement}"

# =============================================================================
# EXECUTIONS FOR ORGANIZATIONS
# =============================================================================

# Helper to create executions for an organization
def create_org_executions(org, count:, agents:, models: ["gpt-4o-mini"], statuses: ["success"])
  count.times do |i|
    create_execution(
      tenant_id: org.llm_tenant_id,
      agent_type: agents.sample,
      model_id: models.sample,
      status: statuses.sample,
      parameters: { query: "Test query #{i + 1}" },
      response: { content: "Response content" },
      metadata: { request_id: SecureRandom.uuid },
      created_at: Time.current - (i * rand(10..60)).minutes
    )
  end
end

# =============================================================================
# ACME CORP EXECUTIONS - High volume
# =============================================================================
puts "\n" + "=" * 60
puts "Creating executions for: #{acme.name}"
puts "=" * 60

# Successful showcase agent executions
showcase_agents = %w[
  ReliabilityAgent
  CachingAgent
  StreamingAgent
  ToolsAgent
  SchemaAgent
  ConversationAgent
  FullFeaturedAgent
]

showcase_agents.each do |agent|
  2.times do |i|
    create_execution(
      tenant_id: acme.llm_tenant_id,
      agent_type: agent,
      model_id: "gpt-4o",
      parameters: { query: "Showcase test #{i + 1}" },
      response: { content: "Showcase response" },
      metadata: { showcase: true },
      created_at: Time.current - (i * 30).minutes
    )
  end
end
puts "  Created #{showcase_agents.length * 2} showcase agent executions"

# Standard agents
create_org_executions(acme, count: 8, agents: %w[SearchAgent SummaryAgent], models: %w[gpt-4o gpt-4o-mini])
puts "  Created 8 standard agent executions"

# Tool calls execution
create_execution(
  tenant_id: acme.llm_tenant_id,
  agent_type: "ToolsAgent",
  model_id: "gpt-4o",
  finish_reason: "tool_calls",
  tool_calls: [
    { id: "call_calc_001", name: "calculator", arguments: { operation: "multiply", a: 25, b: 4 } },
    { id: "call_weather_001", name: "weather", arguments: { location: "Tokyo" } }
  ],
  tool_calls_count: 2,
  parameters: { query: "What's 25*4 and the weather in Tokyo?" },
  response: { content: "25 times 4 is 100, and Tokyo is sunny at 22C." },
  created_at: Time.current - 45.minutes
)
puts "  Created 1 tool calls execution"

# =============================================================================
# STARTUP INC EXECUTIONS - Budget conscious
# =============================================================================
puts "\n" + "=" * 60
puts "Creating executions for: #{startup.name}"
puts "=" * 60

create_org_executions(startup, count: 5, agents: %w[SummaryAgent SearchAgent], models: ["gpt-4o-mini"])
puts "  Created 5 budget-conscious executions"

# Cached response
create_execution(
  tenant_id: startup.llm_tenant_id,
  agent_type: "CachingAgent",
  cache_hit: true,
  response_cache_key: "showcase_caching:v1:startup",
  cached_at: Time.current - 1.hour,
  duration_ms: 5,
  parameters: { query: "What is caching?" },
  response: { content: "Caching is storing data for quick retrieval..." },
  created_at: Time.current - 10.minutes
)
puts "  Created 1 cached response"

# Budget warning (soft enforcement)
create_execution(
  tenant_id: startup.llm_tenant_id,
  agent_type: "SummaryAgent",
  status: "success",
  parameters: { text: "Long document..." },
  response: { summary: "Summary of document..." },
  metadata: { budget_warning: true, budget_percentage: 85 },
  created_at: Time.current - 30.minutes
)
puts "  Created 1 budget warning execution"

# =============================================================================
# ENTERPRISE PLUS EXECUTIONS - Premium usage
# =============================================================================
puts "\n" + "=" * 60
puts "Creating executions for: #{enterprise.name}"
puts "=" * 60

# Premium model usage
create_org_executions(enterprise, count: 15, agents: showcase_agents + %w[SearchAgent SummaryAgent], models: %w[gpt-4o claude-3-opus])
puts "  Created 15 premium model executions"

# Streaming execution
create_execution(
  tenant_id: enterprise.llm_tenant_id,
  agent_type: "StreamingAgent",
  model_id: "gpt-4o",
  streaming: true,
  parameters: { query: "Tell me a story about AI" },
  response: { content: "Once upon a time..." },
  metadata: { time_to_first_token_ms: 234 },
  created_at: Time.current - 15.minutes
)
puts "  Created 1 streaming execution"

# =============================================================================
# DEMO ACCOUNT EXECUTIONS - Various states
# =============================================================================
puts "\n" + "=" * 60
puts "Creating executions for: #{demo.name}"
puts "=" * 60

# Successful execution
create_execution(
  tenant_id: demo.llm_tenant_id,
  agent_type: "CachingAgent",
  parameters: { query: "What is Ruby?" },
  response: { content: "Ruby is a programming language..." },
  created_at: Time.current - 5.minutes
)
puts "  Created 1 successful execution"

# Budget exceeded error (hard enforcement)
create_execution(
  tenant_id: demo.llm_tenant_id,
  agent_type: "FullFeaturedAgent",
  status: "error",
  error_class: "RubyLLM::Agents::BudgetExceededError",
  error_message: "Daily budget limit of $5.00 exceeded for tenant demo-account",
  parameters: { query: "Complex analysis request" },
  created_at: Time.current - 2.hours
)
puts "  Created 1 budget exceeded error"

# Rate limited
create_execution(
  tenant_id: demo.llm_tenant_id,
  agent_type: "ReliabilityAgent",
  status: "error",
  error_class: "RubyLLM::RateLimitError",
  error_message: "Rate limit exceeded. Please retry after 60 seconds.",
  rate_limited: true,
  retryable: true,
  parameters: { query: "Quick question" },
  created_at: Time.current - 1.hour
)
puts "  Created 1 rate limited error"

# Running execution
create_execution(
  tenant_id: demo.llm_tenant_id,
  agent_type: "StreamingAgent",
  status: "running",
  parameters: { query: "Long story request" },
  completed_at: nil,
  duration_ms: nil,
  output_tokens: nil,
  created_at: Time.current - 30.seconds
)
puts "  Created 1 running execution"

# =============================================================================
# TOKEN FOCUSED EXECUTIONS
# =============================================================================
puts "\n" + "=" * 60
puts "Creating executions for: #{token_focused.name}"
puts "=" * 60

# High token usage executions
5.times do |i|
  create_execution(
    tenant_id: token_focused.llm_tenant_id,
    agent_type: "ConversationAgent",
    model_id: "gpt-4o-mini",
    input_tokens: rand(5000..15000),
    output_tokens: rand(3000..8000),
    parameters: { message: "Conversation message #{i + 1}", conversation_history: [] },
    response: { content: "Response #{i + 1}" },
    created_at: Time.current - (i * 20).minutes
  )
end
puts "  Created 5 high-token executions"

# =============================================================================
# LEGACY EXECUTIONS (no tenant - backward compatibility)
# =============================================================================
puts "\n" + "=" * 60
puts "Creating executions without tenant (legacy)"
puts "=" * 60

3.times do |i|
  create_execution(
    tenant_id: nil,
    agent_type: "LegacyAgent",
    parameters: { action: "process_#{i}" },
    response: { status: "completed" },
    created_at: Time.current - (i * 4).hours
  )
end
puts "  Created 3 legacy agent executions (no tenant)"

# =============================================================================
# DISPLAY USAGE SUMMARIES
# =============================================================================
puts "\n" + "=" * 60
puts "Usage Summaries (LLMTenant DSL Methods)"
puts "=" * 60

[acme, startup, enterprise, demo, token_focused].each do |org|
  org.reload
  puts "\n#{org.name} (#{org.slug}):"
  puts "  llm_cost_today: $#{org.llm_cost_today.round(4)}"
  puts "  llm_tokens_today: #{org.llm_tokens_today}"
  puts "  llm_executions_today: #{org.llm_executions_today}"
  puts "  llm_within_budget?(daily_cost): #{org.llm_within_budget?(type: :daily_cost)}"

  summary = org.llm_usage_summary(period: :today)
  puts "  llm_usage_summary: cost=$#{summary[:cost].round(4)}, tokens=#{summary[:tokens]}, executions=#{summary[:executions]}"
end

# =============================================================================
# Summary
# =============================================================================
puts "\n" + "=" * 60
puts "Seeding complete!"
puts "=" * 60

puts "\nOrganizations:"
Organization.all.each do |org|
  puts "  #{org.slug}: plan=#{org.plan}, enforcement=#{org.llm_budget&.enforcement || 'none'}"
end

puts "\nExecutions by Tenant:"
tenant_counts = RubyLLM::Agents::Execution.group(:tenant_id).count
tenant_counts.each do |tenant_id, count|
  tenant_name = tenant_id.nil? ? "(no tenant)" : tenant_id
  puts "  #{tenant_name}: #{count} executions"
end

puts "\nShowcase Agent Executions:"
showcase_agents.each do |agent|
  count = RubyLLM::Agents::Execution.where(agent_type: agent).count
  puts "  #{agent}: #{count}" if count > 0
end

puts "\nTotal: #{Organization.count} organizations, #{RubyLLM::Agents::Execution.count} executions"
puts "\nStart the server with: bin/rails server"
puts "Then visit: http://localhost:3000/agents"
puts "\nTo test tenant filtering, append ?tenant_id=acme-corp to the URL"
