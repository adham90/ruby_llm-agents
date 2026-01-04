# frozen_string_literal: true

# Seeds for testing ruby_llm-agents dashboard and workflow visualizations
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

# =============================================================================
# TENANT BUDGETS
# =============================================================================
puts "\n" + "=" * 60
puts "Creating Tenant Budgets..."
puts "=" * 60

if RubyLLM::Agents::TenantBudget.table_exists?
  # Tenant 1: Acme Corp - High usage enterprise customer
  acme = RubyLLM::Agents::TenantBudget.create!(
    tenant_id: "acme_corp",
    daily_limit: 100.0,
    monthly_limit: 2000.0,
    per_agent_daily: {
      "ContentPipeline" => 30.0,
      "SearchAgent" => 20.0,
      "SummaryAgent" => 15.0
    },
    per_agent_monthly: {
      "ContentPipeline" => 600.0,
      "SearchAgent" => 400.0
    },
    enforcement: "soft",
    inherit_global_defaults: true
  )
  puts "  Created: acme_corp (daily: $#{acme.daily_limit}, monthly: $#{acme.monthly_limit}, enforcement: #{acme.enforcement})"

  # Tenant 2: Startup Inc - Budget-conscious startup
  startup = RubyLLM::Agents::TenantBudget.create!(
    tenant_id: "startup_inc",
    daily_limit: 25.0,
    monthly_limit: 500.0,
    per_agent_daily: {
      "ContentPipeline" => 10.0,
      "SearchAgent" => 5.0
    },
    enforcement: "hard",
    inherit_global_defaults: true
  )
  puts "  Created: startup_inc (daily: $#{startup.daily_limit}, monthly: $#{startup.monthly_limit}, enforcement: #{startup.enforcement})"

  # Tenant 3: Enterprise Plus - Premium unlimited customer
  enterprise = RubyLLM::Agents::TenantBudget.create!(
    tenant_id: "enterprise_plus",
    daily_limit: 500.0,
    monthly_limit: 10000.0,
    per_agent_daily: {},
    per_agent_monthly: {},
    enforcement: "none",
    inherit_global_defaults: false
  )
  puts "  Created: enterprise_plus (daily: $#{enterprise.daily_limit}, monthly: $#{enterprise.monthly_limit}, enforcement: #{enterprise.enforcement})"

  # Tenant 4: Demo Account - For demos and testing
  demo = RubyLLM::Agents::TenantBudget.create!(
    tenant_id: "demo_account",
    daily_limit: 10.0,
    monthly_limit: 100.0,
    per_agent_daily: {
      "SearchAgent" => 3.0,
      "SummaryAgent" => 2.0,
      "TranslationAgent" => 2.0
    },
    enforcement: "soft",
    inherit_global_defaults: true
  )
  puts "  Created: demo_account (daily: $#{demo.daily_limit}, monthly: $#{demo.monthly_limit}, enforcement: #{demo.enforcement})"
else
  puts "  Skipping TenantBudget creation - table does not exist"
end

# =============================================================================
# TENANT: ACME CORP - High volume, various executions
# =============================================================================
puts "\n" + "=" * 60
puts "Creating executions for: acme_corp"
puts "=" * 60

# Successful searches
8.times do |i|
  create_execution(
    tenant_id: "acme_corp",
    agent_type: "SearchAgent",
    parameters: { query: "How to implement #{%w[authentication caching routing validation pagination].sample}?" },
    response: { content: "Here's how to implement it..." },
    metadata: { request_id: SecureRandom.uuid },
    created_at: Time.current - (i * 2).hours
  )
end
puts "  Created 8 SearchAgent executions"

# Summary executions
5.times do |i|
  create_execution(
    tenant_id: "acme_corp",
    agent_type: "SummaryAgent",
    model_id: "gpt-4o",
    parameters: { text: "Long document content #{i + 1}..." },
    response: { summary: "This document discusses..." },
    created_at: Time.current - (i * 3).hours
  )
end
puts "  Created 5 SummaryAgent executions"

# Pipeline workflow for acme
workflow_id = SecureRandom.uuid
pipeline_started = Time.current - 1.hour

pipeline_root = create_execution(
  tenant_id: "acme_corp",
  agent_type: "ContentPipeline",
  workflow_type: "pipeline",
  workflow_id: workflow_id,
  parameters: { text: "Analyze this content about machine learning and AI trends..." },
  response: {
    extracted: { entities: ["AI", "ML", "trends"], key_points: 3 },
    classified: "technology",
    formatted: "# Analysis Report\n\nKey findings..."
  },
  started_at: pipeline_started,
  completed_at: pipeline_started + 4.5.seconds,
  duration_ms: 4500,
  created_at: pipeline_started
)

# Pipeline steps
create_execution(
  tenant_id: "acme_corp",
  agent_type: "ExtractorAgent",
  workflow_type: "pipeline",
  workflow_id: workflow_id,
  workflow_step: "extract",
  parent_execution_id: pipeline_root.id,
  root_execution_id: pipeline_root.id,
  model_id: "gpt-4o-mini",
  parameters: { text: "Analyze this content about machine learning..." },
  response: { entities: ["AI", "ML", "trends"], key_points: 3 },
  started_at: pipeline_started,
  completed_at: pipeline_started + 1.2.seconds,
  duration_ms: 1200,
  input_tokens: 450,
  output_tokens: 120,
  created_at: pipeline_started
)

create_execution(
  tenant_id: "acme_corp",
  agent_type: "ClassifierAgent",
  workflow_type: "pipeline",
  workflow_id: workflow_id,
  workflow_step: "classify",
  parent_execution_id: pipeline_root.id,
  root_execution_id: pipeline_root.id,
  model_id: "gpt-4o-mini",
  parameters: { text: "Entities: AI, ML, trends" },
  response: { category: "technology", confidence: 0.95 },
  started_at: pipeline_started + 1.3.seconds,
  completed_at: pipeline_started + 2.1.seconds,
  duration_ms: 800,
  input_tokens: 200,
  output_tokens: 50,
  created_at: pipeline_started + 1.3.seconds
)

create_execution(
  tenant_id: "acme_corp",
  agent_type: "FormatterAgent",
  workflow_type: "pipeline",
  workflow_id: workflow_id,
  workflow_step: "format",
  parent_execution_id: pipeline_root.id,
  root_execution_id: pipeline_root.id,
  model_id: "gpt-4o-mini",
  parameters: { text: "Entities and classification data...", category: "technology" },
  response: { formatted: "# Analysis Report\n\nKey findings..." },
  started_at: pipeline_started + 2.2.seconds,
  completed_at: pipeline_started + 4.4.seconds,
  duration_ms: 2200,
  input_tokens: 350,
  output_tokens: 400,
  created_at: pipeline_started + 2.2.seconds
)
puts "  Created ContentPipeline workflow with 3 steps"

# =============================================================================
# TENANT: STARTUP INC - Budget-conscious, fewer executions
# =============================================================================
puts "\n" + "=" * 60
puts "Creating executions for: startup_inc"
puts "=" * 60

# Fewer searches (budget conscious)
3.times do |i|
  create_execution(
    tenant_id: "startup_inc",
    agent_type: "SearchAgent",
    model_id: "gpt-4o-mini", # Cost-effective model
    parameters: { query: "Best practices for #{%w[MVP deployment scaling].sample}" },
    response: { content: "Here are the best practices..." },
    created_at: Time.current - (i * 5).hours
  )
end
puts "  Created 3 SearchAgent executions"

# One failed execution (hit budget limit)
create_execution(
  tenant_id: "startup_inc",
  agent_type: "SummaryAgent",
  status: "error",
  error_class: "RubyLLM::Agents::BudgetExceededError",
  error_message: "Daily budget limit of $25.00 exceeded for tenant startup_inc",
  parameters: { text: "Summarize this report..." },
  created_at: Time.current - 2.hours
)
puts "  Created 1 budget-exceeded error"

# One successful summary
create_execution(
  tenant_id: "startup_inc",
  agent_type: "SummaryAgent",
  model_id: "gpt-4o-mini",
  parameters: { text: "Quarterly report..." },
  response: { summary: "Q4 showed 20% growth..." },
  created_at: Time.current - 6.hours
)
puts "  Created 1 SummaryAgent execution"

# =============================================================================
# TENANT: ENTERPRISE PLUS - Heavy usage, premium models
# =============================================================================
puts "\n" + "=" * 60
puts "Creating executions for: enterprise_plus"
puts "=" * 60

# Heavy search usage with premium models
10.times do |i|
  model = ["gpt-4o", "claude-3-opus", "gpt-4o"].sample
  create_execution(
    tenant_id: "enterprise_plus",
    agent_type: "SearchAgent",
    model_id: model,
    parameters: { query: "Enterprise #{%w[security compliance analytics governance].sample} strategy" },
    response: { content: "Comprehensive analysis..." },
    metadata: { request_id: SecureRandom.uuid, department: %w[engineering legal finance hr].sample },
    created_at: Time.current - (i * 1.5).hours
  )
end
puts "  Created 10 SearchAgent executions"

# Summary executions
6.times do |i|
  create_execution(
    tenant_id: "enterprise_plus",
    agent_type: "SummaryAgent",
    model_id: "gpt-4o",
    parameters: { text: "Board meeting notes #{i + 1}..." },
    response: { summary: "Key decisions from the meeting..." },
    created_at: Time.current - (i * 2).hours
  )
end
puts "  Created 6 SummaryAgent executions"

# Parallel workflow
parallel_workflow_id = SecureRandom.uuid
parallel_started = Time.current - 45.minutes

parallel_root = create_execution(
  tenant_id: "enterprise_plus",
  agent_type: "ContentAnalyzer",
  workflow_type: "parallel",
  workflow_id: parallel_workflow_id,
  parameters: { text: "The new product launch exceeded expectations with 50% growth..." },
  response: {
    sentiment: "positive",
    keywords: ["product", "launch", "growth", "expectations"],
    summary: "Successful product launch with significant growth."
  },
  started_at: parallel_started,
  completed_at: parallel_started + 2.8.seconds,
  duration_ms: 2800,
  created_at: parallel_started
)

# Parallel branches
create_execution(
  tenant_id: "enterprise_plus",
  agent_type: "SentimentAgent",
  workflow_type: "parallel",
  workflow_id: parallel_workflow_id,
  workflow_step: "sentiment",
  parent_execution_id: parallel_root.id,
  root_execution_id: parallel_root.id,
  model_id: "gpt-4o",
  parameters: { text: "The new product launch exceeded expectations..." },
  response: { sentiment: "positive", score: 0.89 },
  started_at: parallel_started,
  completed_at: parallel_started + 0.9.seconds,
  duration_ms: 900,
  input_tokens: 180,
  output_tokens: 30,
  created_at: parallel_started
)

create_execution(
  tenant_id: "enterprise_plus",
  agent_type: "KeywordAgent",
  workflow_type: "parallel",
  workflow_id: parallel_workflow_id,
  workflow_step: "keywords",
  parent_execution_id: parallel_root.id,
  root_execution_id: parallel_root.id,
  model_id: "gpt-4o",
  parameters: { text: "The new product launch exceeded expectations..." },
  response: { keywords: ["product", "launch", "growth"] },
  started_at: parallel_started,
  completed_at: parallel_started + 1.5.seconds,
  duration_ms: 1500,
  input_tokens: 180,
  output_tokens: 60,
  created_at: parallel_started
)

create_execution(
  tenant_id: "enterprise_plus",
  agent_type: "SummaryAgent",
  workflow_type: "parallel",
  workflow_id: parallel_workflow_id,
  workflow_step: "summary",
  parent_execution_id: parallel_root.id,
  root_execution_id: parallel_root.id,
  model_id: "gpt-4o",
  parameters: { text: "The new product launch exceeded expectations..." },
  response: { summary: "Successful product launch with 50% growth." },
  started_at: parallel_started,
  completed_at: parallel_started + 2.7.seconds,
  duration_ms: 2700,
  input_tokens: 180,
  output_tokens: 80,
  created_at: parallel_started
)
puts "  Created ContentAnalyzer parallel workflow with 3 branches"

# Router workflow
router_workflow_id = SecureRandom.uuid
router_started = Time.current - 30.minutes

router_root = create_execution(
  tenant_id: "enterprise_plus",
  agent_type: "SupportRouter",
  workflow_type: "router",
  workflow_id: router_workflow_id,
  routed_to: "technical",
  classification_result: {
    method: "llm",
    classifier_model: "gpt-4o",
    classification_time_ms: 450,
    confidence: 0.95
  },
  parameters: { message: "Our API integration is returning 500 errors" },
  response: { content: "Let me help you debug the API integration issue..." },
  started_at: router_started,
  completed_at: router_started + 3.2.seconds,
  duration_ms: 3200,
  created_at: router_started
)

create_execution(
  tenant_id: "enterprise_plus",
  agent_type: "TechnicalSupportAgent",
  workflow_type: "router",
  workflow_id: router_workflow_id,
  workflow_step: "technical",
  parent_execution_id: router_root.id,
  root_execution_id: router_root.id,
  model_id: "gpt-4o",
  parameters: { message: "Our API integration is returning 500 errors" },
  response: { content: "Based on the error logs, I recommend checking..." },
  started_at: router_started + 0.5.seconds,
  completed_at: router_started + 3.1.seconds,
  duration_ms: 2600,
  input_tokens: 380,
  output_tokens: 250,
  created_at: router_started + 0.5.seconds
)
puts "  Created SupportRouter workflow"

# =============================================================================
# TENANT: DEMO ACCOUNT - Variety of states for demos
# =============================================================================
puts "\n" + "=" * 60
puts "Creating executions for: demo_account"
puts "=" * 60

# Success
create_execution(
  tenant_id: "demo_account",
  agent_type: "SearchAgent",
  parameters: { query: "What is Ruby on Rails?" },
  response: { content: "Ruby on Rails is a web framework..." },
  created_at: Time.current - 10.minutes
)
puts "  Created 1 successful SearchAgent"

# Cached response
create_execution(
  tenant_id: "demo_account",
  agent_type: "SearchAgent",
  cache_hit: true,
  response_cache_key: "search_agent:v1:demo123",
  cached_at: Time.current - 1.hour,
  duration_ms: 5,
  parameters: { query: "What is Ruby on Rails?" },
  response: { content: "Ruby on Rails is a web framework..." },
  created_at: Time.current - 5.minutes
)
puts "  Created 1 cached SearchAgent"

# Rate limited
create_execution(
  tenant_id: "demo_account",
  agent_type: "TranslationAgent",
  status: "error",
  error_class: "RubyLLM::RateLimitError",
  error_message: "Rate limit exceeded. Please retry after 60 seconds.",
  rate_limited: true,
  retryable: true,
  parameters: { text: "Hello world", target_language: "es" },
  created_at: Time.current - 15.minutes
)
puts "  Created 1 rate-limited error"

# Timeout
create_execution(
  tenant_id: "demo_account",
  agent_type: "AnalysisAgent",
  status: "timeout",
  error_class: "Timeout::Error",
  error_message: "Execution exceeded 30 second timeout",
  parameters: { data: "Large dataset..." },
  duration_ms: 30000,
  created_at: Time.current - 20.minutes
)
puts "  Created 1 timeout error"

# Running
create_execution(
  tenant_id: "demo_account",
  agent_type: "ReportAgent",
  status: "running",
  parameters: { report_type: "demo", format: "pdf" },
  completed_at: nil,
  duration_ms: nil,
  output_tokens: nil,
  created_at: Time.current - 1.minute
)
puts "  Created 1 running execution"

# With tool calls
create_execution(
  tenant_id: "demo_account",
  agent_type: "AssistantAgent",
  model_id: "gpt-4o",
  finish_reason: "tool_calls",
  tool_calls: [
    { id: "call_abc123", name: "search_web", arguments: { query: "latest news" } },
    { id: "call_def456", name: "calculate", arguments: { expression: "2 + 2" } }
  ],
  tool_calls_count: 2,
  parameters: { message: "Search for news and calculate 2+2" },
  response: { content: "I found the news and the answer is 4." },
  created_at: Time.current - 25.minutes
)
puts "  Created 1 execution with tool calls"

# =============================================================================
# NO TENANT (legacy/global executions)
# =============================================================================
puts "\n" + "=" * 60
puts "Creating executions without tenant (global)"
puts "=" * 60

# Some executions without tenant_id (backward compatibility)
3.times do |i|
  create_execution(
    tenant_id: nil,
    agent_type: "LegacyAgent",
    parameters: { action: "process_#{i}" },
    response: { status: "completed" },
    created_at: Time.current - (i * 4).hours
  )
end
puts "  Created 3 LegacyAgent executions (no tenant)"

# =============================================================================
# Summary
# =============================================================================
puts "\n" + "=" * 60
puts "Seeding complete!"
puts "=" * 60

if RubyLLM::Agents::TenantBudget.table_exists?
  puts "\nTenant Budgets:"
  RubyLLM::Agents::TenantBudget.all.each do |budget|
    puts "  #{budget.tenant_id}: daily=$#{budget.daily_limit}, monthly=$#{budget.monthly_limit}, enforcement=#{budget.enforcement}"
  end
end

puts "\nExecutions by Tenant:"
tenant_counts = RubyLLM::Agents::Execution.group(:tenant_id).count
tenant_counts.each do |tenant_id, count|
  tenant_name = tenant_id.nil? ? "(no tenant)" : tenant_id
  puts "  #{tenant_name}: #{count} executions"
end

puts "\nWorkflows:"
puts "  - #{RubyLLM::Agents::Execution.where(workflow_type: 'pipeline', parent_execution_id: nil).count} pipeline workflows"
puts "  - #{RubyLLM::Agents::Execution.where(workflow_type: 'parallel', parent_execution_id: nil).count} parallel workflows"
puts "  - #{RubyLLM::Agents::Execution.where(workflow_type: 'router', parent_execution_id: nil).count} router workflows"

puts "\nTotal: #{RubyLLM::Agents::Execution.count} executions"
puts "\nStart the server with: bin/rails server"
puts "Then visit: http://localhost:3000/agents"
puts "\nTo test tenant filtering, append ?tenant_id=acme_corp to the URL"
