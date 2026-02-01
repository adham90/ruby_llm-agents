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

puts 'Seeding test data for ruby_llm-agents...'

# Helper to generate realistic execution data
def create_execution(attrs = {})
  defaults = {
    agent_version: '1.0',
    model_id: 'gpt-4o-mini',
    model_provider: 'openai',
    temperature: 0.7,
    status: 'success',
    started_at: Time.current - rand(1..60).minutes,
    input_tokens: rand(100..2000),
    output_tokens: rand(50..1000),
    streaming: [true, false].sample
  }

  merged = defaults.merge(attrs)

  # Calculate derived fields
  merged[:completed_at] ||= merged[:started_at] + rand(500..5000) / 1000.0 if merged[:status] != 'running'
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
puts 'Clearing existing data...'
RubyLLM::Agents::Execution.destroy_all
RubyLLM::Agents::TenantBudget.destroy_all if RubyLLM::Agents::TenantBudget.table_exists?
Organization.destroy_all if defined?(Organization) && Organization.table_exists?

# =============================================================================
# ORGANIZATIONS (with LLMTenant DSL)
# =============================================================================
puts "\n#{'=' * 60}"
puts 'Creating Organizations with LLMTenant...'
puts '=' * 60

# Organization 1: Acme Corp - Enterprise customer with high limits
# Demonstrates: Full configuration, hard enforcement, multiple API keys
acme = Organization.create!(
  slug: 'acme-corp',
  name: 'Acme Corporation',
  plan: 'enterprise',
  industry: 'Technology',
  employee_count: 500,
  openai_api_key: 'sk-demo-acme-openai-key',
  anthropic_api_key: 'sk-ant-demo-acme-key',
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
  budget.enforcement = 'hard'
  budget.inherit_global_defaults = true
  budget.per_agent_daily = {
    'FullFeaturedAgent' => 50.0,
    'ToolsAgent' => 30.0
  }
end
puts "  Created: #{acme.name} (#{acme.slug}) - Enterprise, hard enforcement"

# Organization 2: Startup Inc - Budget-conscious with soft enforcement
# Demonstrates: Soft enforcement, lower limits
startup = Organization.create!(
  slug: 'startup-inc',
  name: 'Startup Inc',
  plan: 'starter',
  industry: 'SaaS',
  employee_count: 25,
  openai_api_key: 'sk-demo-startup-openai',
  active: true
)

startup.llm_configure_budget do |budget|
  budget.daily_limit = 25.0
  budget.monthly_limit = 500.0
  budget.daily_token_limit = 500_000
  budget.monthly_token_limit = 10_000_000
  budget.daily_execution_limit = 100
  budget.monthly_execution_limit = 2000
  budget.enforcement = 'soft'
end
puts "  Created: #{startup.name} (#{startup.slug}) - Starter, soft enforcement"

# Organization 3: Enterprise Plus - Premium unlimited
# Demonstrates: No enforcement, high limits
enterprise = Organization.create!(
  slug: 'enterprise-plus',
  name: 'Enterprise Plus Global',
  plan: 'enterprise',
  industry: 'Finance',
  employee_count: 5000,
  openai_api_key: 'sk-demo-enterprise-openai',
  anthropic_api_key: 'sk-ant-demo-enterprise',
  gemini_api_key: 'gemini-demo-enterprise',
  active: true
)

enterprise.llm_configure_budget do |budget|
  budget.daily_limit = 10_000.0
  budget.monthly_limit = 200_000.0
  budget.enforcement = 'none'
  budget.inherit_global_defaults = false
end
puts "  Created: #{enterprise.name} (#{enterprise.slug}) - Enterprise, no enforcement"

# Organization 4: Demo Account - Strict limits for demos
# Demonstrates: Hard enforcement with very low limits
demo = Organization.create!(
  slug: 'demo-account',
  name: 'Demo Account',
  plan: 'free',
  industry: 'Demo',
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
  budget.enforcement = 'hard'
end
puts "  Created: #{demo.name} (#{demo.slug}) - Free, hard enforcement (demo limits)"

# Organization 5: Token Focused - Only token-based limits
# Demonstrates: Token limits without cost limits
token_focused = Organization.create!(
  slug: 'token-focused',
  name: 'Token Focused Corp',
  plan: 'business',
  industry: 'Healthcare',
  employee_count: 100,
  openai_api_key: 'sk-demo-token-focused',
  active: true
)

token_focused.llm_configure_budget do |budget|
  budget.daily_limit = nil
  budget.monthly_limit = nil
  budget.daily_token_limit = 1_000_000
  budget.monthly_token_limit = 20_000_000
  budget.daily_execution_limit = nil
  budget.monthly_execution_limit = nil
  budget.enforcement = 'soft'
end
puts "  Created: #{token_focused.name} (#{token_focused.slug}) - Business, token-only limits"

# =============================================================================
# Display LLMTenant DSL Methods
# =============================================================================
puts "\n#{'=' * 60}"
puts 'Demonstrating LLMTenant DSL Methods...'
puts '=' * 60

puts "\nAcme Corp LLMTenant info:"
puts "  llm_tenant_id: #{acme.llm_tenant_id}"
puts "  llm_api_keys: #{acme.llm_api_keys.keys.inspect}"
puts "  llm_budget.enforcement: #{acme.llm_budget.enforcement}"

# =============================================================================
# EXECUTIONS FOR ORGANIZATIONS
# =============================================================================

# Helper to create executions for an organization
def create_org_executions(org, count:, agents:, models: ['gpt-4o-mini'], statuses: ['success'])
  count.times do |i|
    create_execution(
      tenant_id: org.llm_tenant_id,
      agent_type: agents.sample,
      model_id: models.sample,
      status: statuses.sample,
      parameters: { query: "Test query #{i + 1}" },
      response: { content: 'Response content' },
      metadata: { request_id: SecureRandom.uuid },
      created_at: Time.current - (i * rand(10..60)).minutes
    )
  end
end

# =============================================================================
# ACME CORP EXECUTIONS - High volume
# =============================================================================
puts "\n#{'=' * 60}"
puts "Creating executions for: #{acme.name}"
puts '=' * 60

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

# Moderation showcase agents
moderation_agents = %w[
  ModeratedAgent
  OutputModeratedAgent
  FullyModeratedAgent
  BlockBasedModerationAgent
  CustomHandlerModerationAgent
  ModerationActionsAgent
]

showcase_agents.each do |agent|
  2.times do |i|
    create_execution(
      tenant_id: acme.llm_tenant_id,
      agent_type: agent,
      model_id: 'gpt-4o',
      parameters: { query: "Showcase test #{i + 1}" },
      response: { content: 'Showcase response' },
      metadata: { showcase: true },
      created_at: Time.current - (i * 30).minutes
    )
  end
end
puts "  Created #{showcase_agents.length * 2} showcase agent executions"

# Moderation agent executions
moderation_agents.each do |agent|
  create_execution(
    tenant_id: acme.llm_tenant_id,
    agent_type: agent,
    model_id: 'gpt-4o',
    parameters: { message: 'Moderation test' },
    response: { content: 'Moderated response' },
    metadata: {
      showcase: true,
      moderation: {
        phase: agent.include?('Output') ? 'output' : 'input',
        passed: true
      }
    },
    created_at: Time.current - rand(10..120).minutes
  )
end
puts "  Created #{moderation_agents.length} moderation agent executions"

# Moderation flagged execution example (uses :raise action, so it's an error)
create_execution(
  tenant_id: acme.llm_tenant_id,
  agent_type: 'FullyModeratedAgent',
  model_id: 'gpt-4o',
  status: 'error',
  error_class: 'RubyLLM::Agents::ModerationError',
  error_message: 'Content flagged by moderation: harassment (score: 0.85)',
  parameters: { message: '[simulated harmful content]' },
  response: nil,
  metadata: {
    showcase: true,
    moderation: {
      phase: 'input',
      passed: false,
      flagged_categories: ['harassment'],
      max_score: 0.85
    }
  },
  created_at: Time.current - 25.minutes
)
puts '  Created 1 moderation flagged execution'

# Moderation with custom handler (allowed with warning)
create_execution(
  tenant_id: acme.llm_tenant_id,
  agent_type: 'CustomHandlerModerationAgent',
  model_id: 'gpt-4o',
  status: 'success',
  parameters: { message: 'Borderline content test' },
  response: { content: 'Processed with warning' },
  metadata: {
    showcase: true,
    moderation: {
      phase: 'input',
      passed: true,
      handler_result: 'continue',
      warning: true,
      max_score: 0.65
    }
  },
  created_at: Time.current - 35.minutes
)
puts '  Created 1 custom moderation handler execution'

# Standard agents
create_org_executions(acme, count: 8, agents: %w[SearchAgent SummaryAgent], models: %w[gpt-4o gpt-4o-mini])
puts '  Created 8 standard agent executions'

# =============================================================================
# TOOL CALLS EXECUTIONS (Enhanced with results, status, duration, timestamps)
# =============================================================================
puts "\n#{'-' * 40}"
puts 'Creating enhanced tool calls executions...'
puts '-' * 40

# Helper to generate timestamps for tool calls
def tool_call_times(base_time, duration_ms)
  called_at = base_time
  completed_at = called_at + (duration_ms / 1000.0)
  {
    called_at: called_at.iso8601(3),
    completed_at: completed_at.iso8601(3),
    duration_ms: duration_ms
  }
end

# Tool calls execution - Calculator and Weather (SUCCESS with results)
base_time = Time.current - 45.minutes
create_execution(
  tenant_id: acme.llm_tenant_id,
  agent_type: 'ToolsAgent',
  model_id: 'gpt-4o',
  finish_reason: 'tool_calls',
  tool_calls: [
    {
      id: 'call_calc_001',
      name: 'calculator',
      arguments: { operation: 'multiply', a: 25, b: 4 },
      result: '100',
      status: 'success',
      error_message: nil,
      **tool_call_times(base_time, 45)
    },
    {
      id: 'call_weather_001',
      name: 'weather',
      arguments: { location: 'Tokyo' },
      result: '{"temperature": "22°C", "condition": "sunny", "humidity": "45%", "wind": "10 km/h"}',
      status: 'success',
      error_message: nil,
      **tool_call_times(base_time + 0.1, 312)
    }
  ],
  tool_calls_count: 2,
  parameters: { query: "What's 25*4 and the weather in Tokyo?" },
  response: { content: '25 times 4 is 100, and Tokyo is sunny at 22°C.' },
  created_at: base_time
)

# Tool calls execution - Database query (SUCCESS with JSON result)
base_time = Time.current - 50.minutes
create_execution(
  tenant_id: acme.llm_tenant_id,
  agent_type: 'ToolsAgent',
  model_id: 'gpt-4o',
  finish_reason: 'tool_calls',
  tool_calls: [
    {
      id: 'call_db_001',
      name: 'database_query',
      arguments: { table: 'users', filter: { status: 'active' }, limit: 10 },
      result: '[{"id": 1, "name": "Alice", "email": "alice@example.com"}, {"id": 2, "name": "Bob", "email": "bob@example.com"}, {"id": 3, "name": "Charlie", "email": "charlie@example.com"}, {"id": 4, "name": "Diana", "email": "diana@example.com"}, {"id": 5, "name": "Eve", "email": "eve@example.com"}]',
      status: 'success',
      error_message: nil,
      **tool_call_times(base_time, 89)
    }
  ],
  tool_calls_count: 1,
  parameters: { query: 'List 10 active users from the database' },
  response: { content: 'Found 10 active users: Alice, Bob, Charlie...' },
  metadata: { db_rows_returned: 10 },
  created_at: base_time
)

# Tool calls execution - File operations (SUCCESS with file content)
base_time = Time.current - 55.minutes
create_execution(
  tenant_id: acme.llm_tenant_id,
  agent_type: 'FullFeaturedAgent',
  model_id: 'gpt-4o',
  finish_reason: 'tool_calls',
  tool_calls: [
    {
      id: 'call_read_001',
      name: 'read_file',
      arguments: { path: '/docs/readme.md' },
      result: "# Project README\n\nThis is a Ruby on Rails application that provides...\n\n## Features\n- User authentication\n- API endpoints\n- Background jobs",
      status: 'success',
      error_message: nil,
      **tool_call_times(base_time, 23)
    },
    {
      id: 'call_write_001',
      name: 'write_file',
      arguments: { path: '/docs/summary.md', content: "# Summary\n\nThis document..." },
      result: '{"written": true, "bytes": 1245, "path": "/docs/summary.md"}',
      status: 'success',
      error_message: nil,
      **tool_call_times(base_time + 0.05, 156)
    }
  ],
  tool_calls_count: 2,
  parameters: { query: 'Read the readme and create a summary file' },
  response: { content: "I've read the readme and created a summary at /docs/summary.md" },
  metadata: { files_read: 1, files_written: 1 },
  created_at: base_time
)

# Tool calls execution - Web search and scraping (SUCCESS with search results)
base_time = Time.current - 30.minutes
create_execution(
  tenant_id: enterprise.llm_tenant_id,
  agent_type: 'SearchAgent',
  model_id: 'gpt-4o',
  finish_reason: 'tool_calls',
  tool_calls: [
    {
      id: 'call_search_001',
      name: 'web_search',
      arguments: { query: 'Ruby on Rails best practices 2024', num_results: 5 },
      result: '[{"title": "Rails Guide - Best Practices", "url": "https://guides.rubyonrails.org/best_practices.html", "snippet": "Learn the best practices for Rails development..."}, {"title": "12 Factor Rails", "url": "https://12factor.net", "snippet": "Build scalable Rails apps..."}]',
      status: 'success',
      error_message: nil,
      **tool_call_times(base_time, 1245)
    },
    {
      id: 'call_scrape_001',
      name: 'scrape_url',
      arguments: { url: 'https://guides.rubyonrails.org', extract: 'headings' },
      result: '["Getting Started", "Active Record Basics", "Routing", "Controllers", "Views", "Layouts", "Active Storage", "Action Cable"]',
      status: 'success',
      error_message: nil,
      **tool_call_times(base_time + 1.3, 876)
    }
  ],
  tool_calls_count: 2,
  parameters: { query: 'Find best practices for Rails development' },
  response: { content: 'Here are the top Rails best practices from authoritative sources...' },
  metadata: { search_results: 5, urls_scraped: 1 },
  created_at: base_time
)

# Tool calls execution - API calls (SUCCESS with GitHub API responses)
base_time = Time.current - 35.minutes
create_execution(
  tenant_id: enterprise.llm_tenant_id,
  agent_type: 'ToolsAgent',
  model_id: 'gpt-4o',
  finish_reason: 'tool_calls',
  tool_calls: [
    {
      id: 'call_api_001',
      name: 'http_request',
      arguments: { method: 'GET', url: 'https://api.github.com/repos/ruby/ruby',
                   headers: { 'Accept' => 'application/json' } },
      result: '{"name": "ruby", "full_name": "ruby/ruby", "stargazers_count": 21500, "forks_count": 5200, "language": "Ruby", "description": "The Ruby Programming Language"}',
      status: 'success',
      error_message: nil,
      **tool_call_times(base_time, 234)
    },
    {
      id: 'call_api_002',
      name: 'http_request',
      arguments: { method: 'GET', url: 'https://api.github.com/repos/rails/rails',
                   headers: { 'Accept' => 'application/json' } },
      result: '{"name": "rails", "full_name": "rails/rails", "stargazers_count": 54800, "forks_count": 21100, "language": "Ruby", "description": "Ruby on Rails"}',
      status: 'success',
      error_message: nil,
      **tool_call_times(base_time + 0.25, 189)
    }
  ],
  tool_calls_count: 2,
  parameters: { query: 'Get info about Ruby and Rails repositories on GitHub' },
  response: { content: 'Ruby has 21k stars and Rails has 54k stars on GitHub.' },
  metadata: { api_calls: 2, response_time_ms: 450 },
  created_at: base_time
)

# Tool calls execution - Code execution (SUCCESS with output)
base_time = Time.current - 25.minutes
create_execution(
  tenant_id: startup.llm_tenant_id,
  agent_type: 'ToolsAgent',
  model_id: 'gpt-4o-mini',
  finish_reason: 'tool_calls',
  tool_calls: [
    {
      id: 'call_code_001',
      name: 'execute_ruby',
      arguments: { code: 'puts (1..10).map { |n| n * 2 }.inspect' },
      result: '[2, 4, 6, 8, 10, 12, 14, 16, 18, 20]',
      status: 'success',
      error_message: nil,
      **tool_call_times(base_time, 12)
    }
  ],
  tool_calls_count: 1,
  parameters: { query: 'Double each number from 1 to 10' },
  response: { content: 'The doubled numbers are: [2, 4, 6, 8, 10, 12, 14, 16, 18, 20]' },
  metadata: { execution_time_ms: 12 },
  created_at: base_time
)

# Tool calls execution - Email sending (SUCCESS)
base_time = Time.current - 20.minutes
create_execution(
  tenant_id: startup.llm_tenant_id,
  agent_type: 'FullFeaturedAgent',
  model_id: 'gpt-4o-mini',
  finish_reason: 'tool_calls',
  tool_calls: [
    {
      id: 'call_email_001',
      name: 'send_email',
      arguments: { to: 'team@example.com', subject: 'Weekly Report', body: "Here is this week's summary..." },
      result: '{"sent": true, "message_id": "msg_abc123xyz", "recipients": 1, "queued_at": "2025-01-27T10:15:00Z"}',
      status: 'success',
      error_message: nil,
      **tool_call_times(base_time, 567)
    }
  ],
  tool_calls_count: 1,
  parameters: { query: 'Send the weekly report to the team' },
  response: { content: "I've sent the weekly report email to team@example.com" },
  metadata: { email_sent: true, recipients: 1 },
  created_at: base_time
)

# Tool calls execution - Multiple sequential tools (SUCCESS with analytics data)
base_time = Time.current - 15.minutes
create_execution(
  tenant_id: acme.llm_tenant_id,
  agent_type: 'FullFeaturedAgent',
  model_id: 'gpt-4o',
  finish_reason: 'tool_calls',
  tool_calls: [
    {
      id: 'call_fetch_001',
      name: 'fetch_data',
      arguments: { source: 'analytics', date_range: 'last_7_days' },
      result: '{"daily_visits": [120, 145, 132, 158, 167, 143, 155], "total_visits": 1020, "unique_visitors": 845}',
      status: 'success',
      error_message: nil,
      **tool_call_times(base_time, 234)
    },
    {
      id: 'call_calc_002',
      name: 'calculator',
      arguments: { operation: 'average', values: [120, 145, 132, 158, 167, 143, 155] },
      result: '145.71',
      status: 'success',
      error_message: nil,
      **tool_call_times(base_time + 0.3, 8)
    },
    {
      id: 'call_chart_001',
      name: 'generate_chart',
      arguments: { type: 'line', data: [120, 145, 132, 158, 167, 143, 155], title: 'Weekly Traffic' },
      result: '{"chart_url": "https://charts.example.com/c/abc123", "format": "png", "width": 800, "height": 400}',
      status: 'success',
      error_message: nil,
      **tool_call_times(base_time + 0.35, 456)
    }
  ],
  tool_calls_count: 3,
  parameters: { query: 'Show me the weekly traffic analytics with a chart' },
  response: { content: "Here's your weekly traffic report. Average: 145.7 visits/day. Chart generated." },
  metadata: { data_points: 7, chart_generated: true },
  created_at: base_time
)

# Tool calls execution - ERROR during tool execution (with error details)
base_time = Time.current - 60.minutes
create_execution(
  tenant_id: demo.llm_tenant_id,
  agent_type: 'ToolsAgent',
  model_id: 'gpt-4o-mini',
  status: 'error',
  finish_reason: 'tool_calls',
  error_class: 'ToolExecutionError',
  error_message: "Tool 'database_query' failed: Connection timeout after 30s",
  tool_calls: [
    {
      id: 'call_db_002',
      name: 'database_query',
      arguments: { table: 'orders', filter: { year: 2024 } },
      result: nil,
      status: 'error',
      error_message: 'ConnectionError: Connection timeout after 30000ms - host: db.example.com:5432',
      **tool_call_times(base_time, 30_023)
    }
  ],
  tool_calls_count: 1,
  parameters: { query: 'Get all orders from 2024' },
  metadata: { tool_error: true, retry_count: 3 },
  created_at: base_time
)

# Tool calls execution - Conversation with context retrieval (SUCCESS)
base_time = Time.current - 10.minutes
create_execution(
  tenant_id: acme.llm_tenant_id,
  agent_type: 'ConversationAgent',
  model_id: 'gpt-4o',
  finish_reason: 'tool_calls',
  tool_calls: [
    {
      id: 'call_memory_001',
      name: 'retrieve_context',
      arguments: { query: 'previous discussion about project timeline', limit: 3 },
      result: '[{"message": "We discussed a 3-month timeline", "timestamp": "2025-01-20"}, {"message": "Milestones at weeks 4, 8, 12", "timestamp": "2025-01-21"}]',
      status: 'success',
      error_message: nil,
      **tool_call_times(base_time, 123)
    },
    {
      id: 'call_search_002',
      name: 'search_documents',
      arguments: { query: 'project milestones Q1 2024', collection: 'project_docs' },
      result: '[{"title": "Q1 Roadmap", "content": "Phase 1: Foundation...", "relevance": 0.92}, {"title": "Sprint Planning", "content": "Sprint 1 goals...", "relevance": 0.85}]',
      status: 'success',
      error_message: nil,
      **tool_call_times(base_time + 0.15, 245)
    }
  ],
  tool_calls_count: 2,
  parameters: { message: 'What did we decide about the project timeline?', conversation_id: 'conv_123' },
  response: { content: 'Based on our previous discussion, we agreed on a 3-month timeline with milestones at weeks 4, 8, and 12.' },
  metadata: { context_retrieved: true, documents_found: 2 },
  created_at: base_time
)

# Tool calls execution - Image analysis (SUCCESS with extracted data)
base_time = Time.current - 40.minutes
create_execution(
  tenant_id: enterprise.llm_tenant_id,
  agent_type: 'ToolsAgent',
  model_id: 'gpt-4o',
  finish_reason: 'tool_calls',
  tool_calls: [
    {
      id: 'call_vision_001',
      name: 'analyze_image',
      arguments: { image_url: 'https://example.com/chart.png', analysis_type: 'data_extraction' },
      result: '{"chart_type": "bar", "title": "Quarterly Revenue", "data_points": [{"label": "Q1", "value": 1200000}, {"label": "Q2", "value": 1500000}, {"label": "Q3", "value": 1800000}, {"label": "Q4", "value": 2100000}], "trend": "increasing"}',
      status: 'success',
      error_message: nil,
      **tool_call_times(base_time, 1567)
    },
    {
      id: 'call_ocr_001',
      name: 'extract_text',
      arguments: { image_url: 'https://example.com/chart.png' },
      result: '{"text": "Quarterly Revenue 2024\nQ1: $1.2M\nQ2: $1.5M\nQ3: $1.8M\nQ4: $2.1M\nTotal: $6.6M", "confidence": 0.97}',
      status: 'success',
      error_message: nil,
      **tool_call_times(base_time + 1.6, 892)
    }
  ],
  tool_calls_count: 2,
  parameters: { query: 'Extract data from this chart image' },
  response: { content: 'The chart shows quarterly revenue: Q1 $1.2M, Q2 $1.5M, Q3 $1.8M, Q4 $2.1M' },
  metadata: { image_analyzed: true, text_extracted: true },
  created_at: base_time
)

# Tool calls execution - Mixed success/error (partial failure)
base_time = Time.current - 8.minutes
create_execution(
  tenant_id: acme.llm_tenant_id,
  agent_type: 'ToolsAgent',
  model_id: 'gpt-4o',
  finish_reason: 'tool_calls',
  tool_calls: [
    {
      id: 'call_stock_001',
      name: 'get_stock_price',
      arguments: { symbol: 'AAPL' },
      result: '{"symbol": "AAPL", "price": 185.42, "change": "+2.15", "change_percent": "+1.17%"}',
      status: 'success',
      error_message: nil,
      **tool_call_times(base_time, 156)
    },
    {
      id: 'call_stock_002',
      name: 'get_stock_price',
      arguments: { symbol: 'INVALID_TICKER' },
      result: nil,
      status: 'error',
      error_message: "SymbolNotFound: No stock found with symbol 'INVALID_TICKER'",
      **tool_call_times(base_time + 0.2, 89)
    },
    {
      id: 'call_stock_003',
      name: 'get_stock_price',
      arguments: { symbol: 'GOOGL' },
      result: '{"symbol": "GOOGL", "price": 142.87, "change": "-0.53", "change_percent": "-0.37%"}',
      status: 'success',
      error_message: nil,
      **tool_call_times(base_time + 0.3, 143)
    }
  ],
  tool_calls_count: 3,
  parameters: { query: 'Get stock prices for AAPL, INVALID_TICKER, and GOOGL' },
  response: { content: "AAPL is at $185.42 (+1.17%). I couldn't find INVALID_TICKER. GOOGL is at $142.87 (-0.37%)." },
  metadata: { stocks_found: 2, stocks_not_found: 1 },
  created_at: base_time
)

# Tool calls with very long result (truncated in display)
base_time = Time.current - 5.minutes
long_result = (1..100).map { |i| { id: i, name: "Item #{i}", description: "Description for item #{i}" * 5 } }.to_json
create_execution(
  tenant_id: enterprise.llm_tenant_id,
  agent_type: 'ToolsAgent',
  model_id: 'gpt-4o',
  finish_reason: 'tool_calls',
  tool_calls: [
    {
      id: 'call_bulk_001',
      name: 'bulk_fetch',
      arguments: { collection: 'products', limit: 100 },
      result: "#{long_result[0..5000]}... [truncated]", # Simulating truncated result
      status: 'success',
      error_message: nil,
      **tool_call_times(base_time, 2345)
    }
  ],
  tool_calls_count: 1,
  parameters: { query: 'Fetch all products from the database' },
  response: { content: 'Retrieved 100 products from the database.' },
  metadata: { records_fetched: 100, result_truncated: true },
  created_at: base_time
)

puts '  Created 13 enhanced tool calls executions'

# =============================================================================
# STARTUP INC EXECUTIONS - Budget conscious
# =============================================================================
puts "\n#{'=' * 60}"
puts "Creating executions for: #{startup.name}"
puts '=' * 60

create_org_executions(startup, count: 5, agents: %w[SummaryAgent SearchAgent], models: ['gpt-4o-mini'])
puts '  Created 5 budget-conscious executions'

# Cached response
create_execution(
  tenant_id: startup.llm_tenant_id,
  agent_type: 'CachingAgent',
  cache_hit: true,
  response_cache_key: 'showcase_caching:v1:startup',
  cached_at: Time.current - 1.hour,
  duration_ms: 5,
  parameters: { query: 'What is caching?' },
  response: { content: 'Caching is storing data for quick retrieval...' },
  created_at: Time.current - 10.minutes
)
puts '  Created 1 cached response'

# Budget warning (soft enforcement)
create_execution(
  tenant_id: startup.llm_tenant_id,
  agent_type: 'SummaryAgent',
  status: 'success',
  parameters: { text: 'Long document...' },
  response: { summary: 'Summary of document...' },
  metadata: { budget_warning: true, budget_percentage: 85 },
  created_at: Time.current - 30.minutes
)
puts '  Created 1 budget warning execution'

# Moderation execution (input blocked - uses default :block action)
# When on_flagged: :block, execution completes but with moderation_flagged metadata
create_execution(
  tenant_id: startup.llm_tenant_id,
  agent_type: 'ModeratedAgent',
  model_id: 'gpt-4o-mini',
  status: 'success',
  parameters: { message: '[content flagged for moderation]' },
  response: { content: nil, moderation_blocked: true },
  metadata: {
    moderation: {
      phase: 'input',
      passed: false,
      action: 'block',
      flagged_categories: ['hate'],
      threshold: 0.7,
      max_score: 0.82
    }
  },
  created_at: Time.current - 45.minutes
)
puts '  Created 1 moderation blocked execution'

# =============================================================================
# ENTERPRISE PLUS EXECUTIONS - Premium usage
# =============================================================================
puts "\n#{'=' * 60}"
puts "Creating executions for: #{enterprise.name}"
puts '=' * 60

# Premium model usage
create_org_executions(enterprise, count: 15, agents: showcase_agents + %w[SearchAgent SummaryAgent],
                                  models: %w[gpt-4o claude-3-opus])
puts '  Created 15 premium model executions'

# Streaming execution
create_execution(
  tenant_id: enterprise.llm_tenant_id,
  agent_type: 'StreamingAgent',
  model_id: 'gpt-4o',
  streaming: true,
  parameters: { query: 'Tell me a story about AI' },
  response: { content: 'Once upon a time...' },
  metadata: { time_to_first_token_ms: 234 },
  created_at: Time.current - 15.minutes
)
puts '  Created 1 streaming execution'

# Output moderation execution
create_execution(
  tenant_id: enterprise.llm_tenant_id,
  agent_type: 'OutputModeratedAgent',
  model_id: 'gpt-4o',
  status: 'success',
  parameters: { topic: 'teamwork and collaboration' },
  response: { content: 'A story about working together...' },
  metadata: {
    moderation: {
      phase: 'output',
      passed: true,
      threshold: 0.6,
      max_score: 0.12
    }
  },
  created_at: Time.current - 20.minutes
)
puts '  Created 1 output moderation execution'

# Block-based moderation execution (different thresholds for input/output)
create_execution(
  tenant_id: enterprise.llm_tenant_id,
  agent_type: 'BlockBasedModerationAgent',
  model_id: 'gpt-4o',
  status: 'success',
  parameters: { message: 'Help me write a creative story' },
  response: { content: 'Once upon a time...' },
  metadata: {
    moderation: {
      input_threshold: 0.5,
      output_threshold: 0.8,
      input_passed: true,
      output_passed: true,
      input_max_score: 0.08,
      output_max_score: 0.15
    }
  },
  created_at: Time.current - 12.minutes
)
puts '  Created 1 block-based moderation execution'

# =============================================================================
# DEMO ACCOUNT EXECUTIONS - Various states
# =============================================================================
puts "\n#{'=' * 60}"
puts "Creating executions for: #{demo.name}"
puts '=' * 60

# Successful execution
create_execution(
  tenant_id: demo.llm_tenant_id,
  agent_type: 'CachingAgent',
  parameters: { query: 'What is Ruby?' },
  response: { content: 'Ruby is a programming language...' },
  created_at: Time.current - 5.minutes
)
puts '  Created 1 successful execution'

# Budget exceeded error (hard enforcement)
create_execution(
  tenant_id: demo.llm_tenant_id,
  agent_type: 'FullFeaturedAgent',
  status: 'error',
  error_class: 'RubyLLM::Agents::BudgetExceededError',
  error_message: 'Daily budget limit of $5.00 exceeded for tenant demo-account',
  parameters: { query: 'Complex analysis request' },
  created_at: Time.current - 2.hours
)
puts '  Created 1 budget exceeded error'

# Rate limited
create_execution(
  tenant_id: demo.llm_tenant_id,
  agent_type: 'ReliabilityAgent',
  status: 'error',
  error_class: 'RubyLLM::RateLimitError',
  error_message: 'Rate limit exceeded. Please retry after 60 seconds.',
  rate_limited: true,
  retryable: true,
  parameters: { query: 'Quick question' },
  created_at: Time.current - 1.hour
)
puts '  Created 1 rate limited error'

# Running execution
create_execution(
  tenant_id: demo.llm_tenant_id,
  agent_type: 'StreamingAgent',
  status: 'running',
  parameters: { query: 'Long story request' },
  completed_at: nil,
  duration_ms: nil,
  output_tokens: nil,
  created_at: Time.current - 30.seconds
)
puts '  Created 1 running execution'

# =============================================================================
# TOKEN FOCUSED EXECUTIONS
# =============================================================================
puts "\n#{'=' * 60}"
puts "Creating executions for: #{token_focused.name}"
puts '=' * 60

# High token usage executions
5.times do |i|
  create_execution(
    tenant_id: token_focused.llm_tenant_id,
    agent_type: 'ConversationAgent',
    model_id: 'gpt-4o-mini',
    input_tokens: rand(5000..15_000),
    output_tokens: rand(3000..8000),
    parameters: { message: "Conversation message #{i + 1}", conversation_history: [] },
    response: { content: "Response #{i + 1}" },
    created_at: Time.current - (i * 20).minutes
  )
end
puts '  Created 5 high-token executions'

# =============================================================================
# EMBEDDER EXECUTIONS
# =============================================================================
puts "\n#{'=' * 60}"
puts 'Creating Embedder Executions...'
puts '=' * 60

# Helper for embedder executions
def create_embedder_execution(attrs = {})
  defaults = {
    agent_version: '1.0',
    model_id: 'text-embedding-3-small',
    model_provider: 'openai',
    status: 'success',
    started_at: Time.current - rand(1..60).minutes,
    input_tokens: rand(50..500),
    output_tokens: 0, # Embeddings don't have output tokens
    streaming: false,
    temperature: nil # Embeddings don't use temperature
  }

  merged = defaults.merge(attrs)
  merged[:completed_at] ||= merged[:started_at] + rand(100..500) / 1000.0 if merged[:status] != 'running'
  merged[:duration_ms] ||= ((merged[:completed_at] - merged[:started_at]) * 1000).to_i if merged[:completed_at]
  merged[:total_tokens] = merged[:input_tokens] || 0

  # Embedding costs are much lower than chat models
  input_price = case merged[:model_id]
                when /text-embedding-3-small/ then 0.02
                when /text-embedding-3-large/ then 0.13
                when /text-embedding-ada/ then 0.10
                else 0.05
                end

  merged[:input_cost] = ((merged[:input_tokens] || 0) / 1_000_000.0 * input_price).round(8)
  merged[:output_cost] = 0
  merged[:total_cost] = merged[:input_cost]

  RubyLLM::Agents::Execution.create!(merged)
end

# Helper for speaker executions (TTS)
def create_speaker_execution(attrs = {})
  defaults = {
    agent_version: '1.0',
    model_id: 'tts-1',
    model_provider: 'openai',
    status: 'success',
    started_at: Time.current - rand(1..60).minutes,
    input_tokens: 0, # TTS doesn't use input tokens
    output_tokens: 0, # TTS doesn't use output tokens
    streaming: false,
    temperature: nil # TTS doesn't use temperature
  }

  merged = defaults.merge(attrs)
  merged[:completed_at] ||= merged[:started_at] + rand(500..3000) / 1000.0 if merged[:status] != 'running'
  merged[:duration_ms] ||= ((merged[:completed_at] - merged[:started_at]) * 1000).to_i if merged[:completed_at]
  merged[:total_tokens] = 0

  # TTS costs are based on character count
  # Pricing: tts-1 = $15/1M chars, tts-1-hd = $30/1M chars
  char_count = merged.dig(:metadata, :character_count) || rand(100..2000)
  price_per_char = merged[:model_id].include?('hd') ? 0.00003 : 0.000015

  merged[:input_cost] = (char_count * price_per_char).round(6)
  merged[:output_cost] = 0
  merged[:total_cost] = merged[:input_cost]

  RubyLLM::Agents::Execution.create!(merged)
end

# Helper for transcriber executions (STT)
def create_transcriber_execution(attrs = {})
  defaults = {
    agent_version: '1.0',
    model_id: 'whisper-1',
    model_provider: 'openai',
    status: 'success',
    started_at: Time.current - rand(1..60).minutes,
    input_tokens: 0, # Transcription doesn't use standard tokens
    output_tokens: 0,
    streaming: false,
    temperature: nil
  }

  merged = defaults.merge(attrs)
  merged[:completed_at] ||= merged[:started_at] + rand(2000..10_000) / 1000.0 if merged[:status] != 'running'
  merged[:duration_ms] ||= ((merged[:completed_at] - merged[:started_at]) * 1000).to_i if merged[:completed_at]
  merged[:total_tokens] = 0

  # Transcription costs are based on audio duration
  # Pricing: whisper-1 = $0.006/min, gpt-4o-transcribe = $0.006/min
  audio_duration = merged.dig(:metadata, :audio_duration_seconds) || rand(60..1800)
  minutes = audio_duration / 60.0
  price_per_minute = 0.006

  merged[:input_cost] = (minutes * price_per_minute).round(6)
  merged[:output_cost] = 0
  merged[:total_cost] = merged[:input_cost]

  RubyLLM::Agents::Execution.create!(merged)
end

# Helper for image generator executions
def create_image_generator_execution(attrs = {})
  defaults = {
    agent_version: '1.0',
    model_id: 'gpt-image-1',
    model_provider: 'openai',
    status: 'success',
    started_at: Time.current - rand(1..60).minutes,
    input_tokens: 0,
    output_tokens: 0,
    streaming: false,
    temperature: nil
  }

  merged = defaults.merge(attrs)
  merged[:completed_at] ||= merged[:started_at] + rand(5000..15_000) / 1000.0 if merged[:status] != 'running'
  merged[:duration_ms] ||= ((merged[:completed_at] - merged[:started_at]) * 1000).to_i if merged[:completed_at]
  merged[:total_tokens] = 0

  # Image generation costs based on size and quality
  # DALL-E 3: 1024x1024 standard=$0.040, HD=$0.080
  #           1792x1024 standard=$0.080, HD=$0.120
  size = merged.dig(:metadata, :size) || '1024x1024'
  quality = merged.dig(:metadata, :quality) || 'standard'

  price = case [size, quality]
          when %w[1024x1024 standard] then 0.040
          when %w[1024x1024 hd] then 0.080
          when %w[1792x1024 standard], %w[1024x1792 standard] then 0.080
          when %w[1792x1024 hd], %w[1024x1792 hd] then 0.120
          else 0.040
          end

  merged[:input_cost] = price.round(6)
  merged[:output_cost] = 0
  merged[:total_cost] = merged[:input_cost]

  RubyLLM::Agents::Execution.create!(merged)
end

# Helper for workflow executions
def create_workflow_execution(attrs = {})
  defaults = {
    agent_version: '1.0',
    model_id: 'gpt-4o-mini',
    model_provider: 'openai',
    temperature: 0.7,
    status: 'success',
    started_at: Time.current - rand(1..60).minutes,
    input_tokens: rand(500..3000),
    output_tokens: rand(200..1500),
    streaming: false
  }

  merged = defaults.merge(attrs)
  merged[:completed_at] ||= merged[:started_at] + rand(2000..8000) / 1000.0 if merged[:status] != 'running'
  merged[:duration_ms] ||= ((merged[:completed_at] - merged[:started_at]) * 1000).to_i if merged[:completed_at]
  merged[:total_tokens] = (merged[:input_tokens] || 0) + (merged[:output_tokens] || 0)

  # Calculate costs
  input_price = case merged[:model_id]
                when /gpt-4o-mini/ then 0.15
                when /gpt-4o/ then 5.0
                else 1.0
                end
  output_price = input_price * 4

  merged[:input_cost] = ((merged[:input_tokens] || 0) / 1_000_000.0 * input_price).round(6)
  merged[:output_cost] = ((merged[:output_tokens] || 0) / 1_000_000.0 * output_price).round(6)
  merged[:total_cost] = merged[:input_cost] + merged[:output_cost]

  RubyLLM::Agents::Execution.create!(merged)
end

# DocumentEmbedder - Single document embedding
10.times do |i|
  create_embedder_execution(
    tenant_id: acme.llm_tenant_id,
    agent_type: 'DocumentEmbedder',
    model_id: 'text-embedding-3-small',
    input_tokens: rand(100..800),
    parameters: { text: "Document content #{i + 1}..." },
    response: { vector_dimensions: 512, vector_preview: '[0.123, -0.456, ...]' },
    metadata: {
      dimensions: 512,
      text_length: rand(500..5000),
      preprocessing: false
    },
    created_at: Time.current - (i * 15).minutes
  )
end
puts '  Created 10 DocumentEmbedder executions'

# SearchEmbedder - Search query embeddings (smaller texts)
15.times do |i|
  create_embedder_execution(
    tenant_id: acme.llm_tenant_id,
    agent_type: 'SearchEmbedder',
    model_id: 'text-embedding-3-large',
    input_tokens: rand(10..100),
    parameters: { text: "search query #{i + 1}" },
    response: { vector_dimensions: 3072, vector_preview: '[0.234, -0.567, ...]' },
    metadata: {
      dimensions: 3072,
      text_length: rand(10..200),
      cache_hit: [true, false, false].sample
    },
    created_at: Time.current - (i * 8).minutes
  )
end
puts '  Created 15 SearchEmbedder executions'

# BatchEmbedder - Batch embedding operations
5.times do |i|
  batch_size = rand(20..100)
  create_embedder_execution(
    tenant_id: enterprise.llm_tenant_id,
    agent_type: 'BatchEmbedder',
    model_id: 'text-embedding-3-small',
    input_tokens: rand(2000..10_000),
    parameters: { texts_count: batch_size },
    response: { vectors_count: batch_size, vector_dimensions: 1024 },
    metadata: {
      dimensions: 1024,
      batch_size: batch_size,
      texts_processed: batch_size,
      batches_used: (batch_size / 100.0).ceil
    },
    created_at: Time.current - (i * 30).minutes
  )
end
puts '  Created 5 BatchEmbedder executions'

# CleanTextEmbedder - With preprocessing
8.times do |i|
  create_embedder_execution(
    tenant_id: startup.llm_tenant_id,
    agent_type: 'CleanTextEmbedder',
    model_id: 'text-embedding-3-small',
    input_tokens: rand(80..400),
    parameters: { text: "Raw text with   extra   spaces #{i + 1}" },
    response: { vector_dimensions: 512, vector_preview: '[0.345, -0.678, ...]' },
    metadata: {
      dimensions: 512,
      original_length: rand(600..3000),
      cleaned_length: rand(400..2000),
      preprocessing_applied: %w[strip lowercase normalize_whitespace]
    },
    created_at: Time.current - (i * 12).minutes
  )
end
puts '  Created 8 CleanTextEmbedder executions'

# CodeEmbedder - Code embedding
6.times do |i|
  languages = %w[ruby python javascript typescript go rust]
  create_embedder_execution(
    tenant_id: enterprise.llm_tenant_id,
    agent_type: 'CodeEmbedder',
    model_id: 'text-embedding-3-large',
    input_tokens: rand(200..2000),
    parameters: { code: "def example_#{i}; end", language: languages.sample },
    response: { vector_dimensions: 1536, vector_preview: '[0.456, -0.789, ...]' },
    metadata: {
      dimensions: 1536,
      code_language: languages.sample,
      lines_of_code: rand(10..500),
      preprocessing_applied: %w[remove_comments normalize_indentation]
    },
    created_at: Time.current - (i * 25).minutes
  )
end
puts '  Created 6 CodeEmbedder executions'

# Embedder with cache hit
3.times do |i|
  create_embedder_execution(
    tenant_id: acme.llm_tenant_id,
    agent_type: 'DocumentEmbedder',
    model_id: 'text-embedding-3-small',
    input_tokens: 0, # No tokens used for cache hit
    cache_hit: true,
    response_cache_key: "embedder:doc:#{SecureRandom.hex(8)}",
    cached_at: Time.current - rand(1..24).hours,
    duration_ms: rand(1..5),
    parameters: { text: "Cached document content #{i + 1}" },
    response: { vector_dimensions: 512, from_cache: true },
    metadata: { cache_hit: true, original_cached_at: Time.current - rand(1..7).days },
    created_at: Time.current - (i * 45).minutes
  )
end
puts '  Created 3 cached embedder executions'

# Embedder error (invalid input)
create_embedder_execution(
  tenant_id: demo.llm_tenant_id,
  agent_type: 'DocumentEmbedder',
  status: 'error',
  error_class: 'ArgumentError',
  error_message: 'Text cannot be empty',
  parameters: { text: '' },
  response: nil,
  created_at: Time.current - 2.hours
)
puts '  Created 1 embedder error execution'

# =============================================================================
# MODERATOR EXECUTIONS
# =============================================================================
puts "\n#{'=' * 60}"
puts 'Creating Standalone Moderator Executions...'
puts '=' * 60

# Helper for moderator executions
def create_moderator_execution(attrs = {})
  defaults = {
    agent_version: '1.0',
    model_id: 'omni-moderation-latest',
    model_provider: 'openai',
    status: 'success',
    started_at: Time.current - rand(1..60).minutes,
    input_tokens: rand(10..200),
    output_tokens: 0, # Moderation doesn't have output tokens
    streaming: false,
    temperature: nil # Moderation doesn't use temperature
  }

  merged = defaults.merge(attrs)
  merged[:completed_at] ||= merged[:started_at] + rand(50..200) / 1000.0 if merged[:status] != 'running'
  merged[:duration_ms] ||= ((merged[:completed_at] - merged[:started_at]) * 1000).to_i if merged[:completed_at]
  merged[:total_tokens] = merged[:input_tokens] || 0

  # Moderation API has very low cost
  merged[:input_cost] = ((merged[:input_tokens] || 0) / 1_000_000.0 * 0.01).round(8)
  merged[:output_cost] = 0
  merged[:total_cost] = merged[:input_cost]

  RubyLLM::Agents::Execution.create!(merged)
end

# ContentModerator - General content moderation (mostly passing)
12.times do |i|
  flagged = i == 5 # One flagged example
  max_score = flagged ? rand(0.72..0.95) : rand(0.01..0.35)
  create_moderator_execution(
    tenant_id: acme.llm_tenant_id,
    agent_type: 'ContentModerator',
    parameters: { text: "User generated content #{i + 1}" },
    response: { flagged: flagged, max_score: max_score.round(3) },
    metadata: {
      threshold: 0.7,
      categories_checked: %i[hate violence harassment sexual],
      flagged: flagged,
      category_scores: {
        hate: rand(0.001..0.1).round(4),
        violence: rand(0.001..0.15).round(4),
        harassment: flagged ? max_score.round(4) : rand(0.001..0.2).round(4),
        sexual: rand(0.001..0.05).round(4)
      },
      max_score: max_score.round(4),
      flagged_categories: flagged ? ['harassment'] : []
    },
    created_at: Time.current - (i * 10).minutes
  )
end
puts '  Created 12 ContentModerator executions (1 flagged)'

# ChildSafeModerator - Stricter threshold for child safety
8.times do |i|
  flagged = [false, false, false, true, false, false, false, false][i]
  max_score = flagged ? rand(0.35..0.65) : rand(0.001..0.25)
  create_moderator_execution(
    tenant_id: enterprise.llm_tenant_id,
    agent_type: 'ChildSafeModerator',
    parameters: { text: "Content for children's platform #{i + 1}" },
    response: { flagged: flagged, max_score: max_score.round(3) },
    metadata: {
      threshold: 0.3, # Lower threshold for child safety
      categories_checked: %i[sexual violence self_harm hate harassment],
      flagged: flagged,
      category_scores: {
        sexual: rand(0.001..0.05).round(4),
        violence: flagged ? max_score.round(4) : rand(0.001..0.1).round(4),
        self_harm: rand(0.001..0.02).round(4),
        hate: rand(0.001..0.08).round(4),
        harassment: rand(0.001..0.1).round(4)
      },
      max_score: max_score.round(4),
      flagged_categories: flagged ? ['violence'] : []
    },
    created_at: Time.current - (i * 18).minutes
  )
end
puts '  Created 8 ChildSafeModerator executions (1 flagged)'

# ForumModerator - Forum-specific moderation (hate/harassment only)
10.times do |i|
  flagged = (i % 4).zero? # Every 4th is flagged
  max_score = flagged ? rand(0.82..0.98) : rand(0.01..0.5)
  flagged_cat = %w[hate harassment].sample
  create_moderator_execution(
    tenant_id: startup.llm_tenant_id,
    agent_type: 'ForumModerator',
    parameters: { text: "Forum post content #{i + 1}" },
    response: { flagged: flagged, max_score: max_score.round(3) },
    metadata: {
      threshold: 0.8, # Higher threshold for forums
      categories_checked: %i[hate harassment],
      flagged: flagged,
      category_scores: {
        hate: flagged && flagged_cat == 'hate' ? max_score.round(4) : rand(0.01..0.3).round(4),
        harassment: flagged && flagged_cat == 'harassment' ? max_score.round(4) : rand(0.01..0.35).round(4)
      },
      max_score: max_score.round(4),
      flagged_categories: flagged ? [flagged_cat] : [],
      action_taken: flagged ? 'blocked' : 'allowed'
    },
    created_at: Time.current - (i * 12).minutes
  )
end
puts '  Created 10 ForumModerator executions (3 flagged)'

# Moderation with multiple flagged categories
create_moderator_execution(
  tenant_id: acme.llm_tenant_id,
  agent_type: 'ContentModerator',
  parameters: { text: '[Severely problematic content simulation]' },
  response: { flagged: true, max_score: 0.95 },
  metadata: {
    threshold: 0.7,
    categories_checked: %i[hate violence harassment sexual],
    flagged: true,
    category_scores: {
      hate: 0.92,
      violence: 0.88,
      harassment: 0.95,
      sexual: 0.15
    },
    max_score: 0.95,
    flagged_categories: %w[hate violence harassment],
    severity: 'high',
    action_taken: 'blocked_and_reported'
  },
  created_at: Time.current - 3.hours
)
puts '  Created 1 multi-category flagged moderation'

# Moderation error
create_moderator_execution(
  tenant_id: demo.llm_tenant_id,
  agent_type: 'ContentModerator',
  status: 'error',
  error_class: 'RubyLLM::APIError',
  error_message: 'Moderation API temporarily unavailable',
  parameters: { text: 'Content to moderate' },
  response: nil,
  metadata: { retry_attempted: true, retries: 3 },
  created_at: Time.current - 4.hours
)
puts '  Created 1 moderator error execution'

# =============================================================================
# SPEAKER EXECUTIONS (Text-to-Speech)
# =============================================================================
puts "\n#{'=' * 60}"
puts 'Creating Speaker Executions...'
puts '=' * 60

# ArticleNarrator - Acme Corp articles
8.times do |i|
  create_speaker_execution(
    tenant_id: acme.llm_tenant_id,
    agent_type: 'ArticleNarrator',
    model_id: 'tts-1-hd',
    parameters: { text: "Article content about technology trends #{i + 1}..." },
    response: { audio_url: "https://storage.example.com/audio/article_#{i + 1}.mp3" },
    metadata: {
      voice: 'nova',
      character_count: rand(2000..8000),
      audio_duration_seconds: rand(120..480),
      output_format: 'mp3'
    },
    created_at: Time.current - (i * 20).minutes
  )
end
puts '  Created 8 ArticleNarrator executions'

# PodcastSpeaker - Enterprise long-form content
6.times do |i|
  create_speaker_execution(
    tenant_id: enterprise.llm_tenant_id,
    agent_type: 'PodcastSpeaker',
    model_id: 'tts-1',
    streaming: true,
    parameters: { text: "Podcast episode script #{i + 1}..." },
    response: { audio_url: "https://storage.example.com/podcasts/episode_#{i + 1}.aac" },
    metadata: {
      voice: 'onyx',
      character_count: rand(15_000..50_000),
      audio_duration_seconds: rand(900..3600),
      output_format: 'aac',
      streaming: true
    },
    created_at: Time.current - (i * 45).minutes
  )
end
puts '  Created 6 PodcastSpeaker executions'

# NotificationSpeaker - Startup quick alerts
10.times do |i|
  create_speaker_execution(
    tenant_id: startup.llm_tenant_id,
    agent_type: 'NotificationSpeaker',
    model_id: 'tts-1',
    parameters: { text: 'Alert: Your task has been completed!' },
    response: { audio_url: "https://storage.example.com/notifications/alert_#{i + 1}.mp3" },
    metadata: {
      voice: 'alloy',
      character_count: rand(20..100),
      audio_duration_seconds: rand(2..8),
      output_format: 'mp3'
    },
    created_at: Time.current - (i * 8).minutes
  )
end
puts '  Created 10 NotificationSpeaker executions'

# MultilangSpeaker - Enterprise multilingual content
languages = %w[French Spanish German Japanese Portuguese]
4.times do |i|
  lang = languages[i % languages.length]
  create_speaker_execution(
    tenant_id: enterprise.llm_tenant_id,
    agent_type: 'MultilangSpeaker',
    model_id: 'eleven_multilingual_v2',
    model_provider: 'elevenlabs',
    parameters: { text: "Multilingual content in #{lang}..." },
    response: { audio_url: "https://storage.example.com/multilang/#{lang.downcase}_#{i + 1}.mp3" },
    metadata: {
      voice: 'Rachel',
      character_count: rand(1000..5000),
      audio_duration_seconds: rand(60..300),
      output_format: 'mp3',
      detected_language: lang.downcase[0..1]
    },
    created_at: Time.current - (i * 35).minutes
  )
end
puts '  Created 4 MultilangSpeaker executions'

# TechnicalNarrator - Acme technical docs
4.times do |i|
  create_speaker_execution(
    tenant_id: acme.llm_tenant_id,
    agent_type: 'TechnicalNarrator',
    model_id: 'tts-1-hd',
    parameters: { text: 'Technical documentation about RubyLLM and PostgreSQL integration...' },
    response: { audio_url: "https://storage.example.com/docs/tech_doc_#{i + 1}.mp3" },
    metadata: {
      voice: 'fable',
      character_count: rand(3000..10_000),
      audio_duration_seconds: rand(180..600),
      output_format: 'mp3',
      lexicon_applied: true,
      terms_corrected: %w[RubyLLM PostgreSQL OAuth JWT]
    },
    created_at: Time.current - (i * 25).minutes
  )
end
puts '  Created 4 TechnicalNarrator executions'

# Speaker cache hits - Acme
2.times do |i|
  create_speaker_execution(
    tenant_id: acme.llm_tenant_id,
    agent_type: 'ArticleNarrator',
    model_id: 'tts-1-hd',
    cache_hit: true,
    response_cache_key: "speaker:article:#{SecureRandom.hex(8)}",
    cached_at: Time.current - rand(1..24).hours,
    duration_ms: rand(5..20),
    parameters: { text: "Cached article content #{i + 1}" },
    response: { audio_url: "https://storage.example.com/cached/article_#{i + 1}.mp3", from_cache: true },
    metadata: { cache_hit: true, original_cached_at: Time.current - rand(1..7).days },
    created_at: Time.current - (i * 50).minutes
  )
end
puts '  Created 2 speaker cache hit executions'

# Speaker error - Demo account
create_speaker_execution(
  tenant_id: demo.llm_tenant_id,
  agent_type: 'ArticleNarrator',
  status: 'error',
  error_class: 'ArgumentError',
  error_message: 'Text cannot be empty',
  parameters: { text: '' },
  response: nil,
  metadata: { voice: 'nova' },
  created_at: Time.current - 3.hours
)
puts '  Created 1 speaker error execution'

# =============================================================================
# TRANSCRIBER EXECUTIONS (Speech-to-Text)
# =============================================================================
puts "\n#{'=' * 60}"
puts 'Creating Transcriber Executions...'
puts '=' * 60

# MeetingTranscriber - Acme meetings
10.times do |i|
  create_transcriber_execution(
    tenant_id: acme.llm_tenant_id,
    agent_type: 'MeetingTranscriber',
    model_id: 'whisper-1',
    parameters: { audio: "meeting_recording_#{i + 1}.mp3" },
    response: { text: "Meeting transcript for standup #{i + 1}...", word_count: rand(500..3000) },
    metadata: {
      audio_duration_seconds: rand(600..3600),
      language: 'en',
      output_format: 'text',
      word_count: rand(500..3000)
    },
    created_at: Time.current - (i * 15).minutes
  )
end
puts '  Created 10 MeetingTranscriber executions'

# SubtitleGenerator - Enterprise video subtitles
8.times do |i|
  create_transcriber_execution(
    tenant_id: enterprise.llm_tenant_id,
    agent_type: 'SubtitleGenerator',
    model_id: 'whisper-1',
    parameters: { audio: "training_video_#{i + 1}.mp4" },
    response: { srt: "1\n00:00:00,000 --> 00:00:02,500\nWelcome...", segments_count: rand(50..200) },
    metadata: {
      audio_duration_seconds: rand(300..1800),
      output_format: 'srt',
      segments_count: rand(50..200),
      timestamps: 'word'
    },
    created_at: Time.current - (i * 22).minutes
  )
end
puts '  Created 8 SubtitleGenerator executions'

# PodcastTranscriber - Enterprise podcasts
6.times do |i|
  create_transcriber_execution(
    tenant_id: enterprise.llm_tenant_id,
    agent_type: 'PodcastTranscriber',
    model_id: 'gpt-4o-transcribe',
    parameters: { audio: "podcast_episode_#{i + 1}.mp3" },
    response: { text: 'Full podcast transcript...', word_count: rand(5000..15_000), segments: [] },
    metadata: {
      audio_duration_seconds: rand(1800..3600),
      output_format: 'verbose_json',
      word_count: rand(5000..15_000),
      timestamps: 'word'
    },
    created_at: Time.current - (i * 40).minutes
  )
end
puts '  Created 6 PodcastTranscriber executions'

# MultilingualTranscriber - Startup global calls
languages = %w[es fr de ja pt]
5.times do |i|
  detected_lang = languages[i % languages.length]
  create_transcriber_execution(
    tenant_id: startup.llm_tenant_id,
    agent_type: 'MultilingualTranscriber',
    model_id: 'whisper-1',
    parameters: { audio: "international_call_#{i + 1}.mp3" },
    response: { text: 'Transcribed content in detected language...', language: detected_lang },
    metadata: {
      audio_duration_seconds: rand(120..600),
      detected_language: detected_lang,
      language_confidence: rand(0.85..0.99).round(3),
      output_format: 'json'
    },
    created_at: Time.current - (i * 18).minutes
  )
end
puts '  Created 5 MultilingualTranscriber executions'

# TechnicalTranscriber - Acme tech talks
5.times do |i|
  create_transcriber_execution(
    tenant_id: acme.llm_tenant_id,
    agent_type: 'TechnicalTranscriber',
    model_id: 'gpt-4o-transcribe',
    parameters: { audio: "tech_talk_#{i + 1}.mp3" },
    response: { text: 'Technical discussion about RubyLLM integration...', word_count: rand(2000..8000) },
    metadata: {
      audio_duration_seconds: rand(600..2400),
      language: 'en',
      output_format: 'text',
      postprocessing_applied: true,
      terms_corrected: %w[RubyLLM PostgreSQL OpenAI GraphQL]
    },
    created_at: Time.current - (i * 30).minutes
  )
end
puts '  Created 5 TechnicalTranscriber executions'

# Transcriber cache hits - Acme
3.times do |i|
  create_transcriber_execution(
    tenant_id: acme.llm_tenant_id,
    agent_type: 'MeetingTranscriber',
    model_id: 'whisper-1',
    cache_hit: true,
    response_cache_key: "transcriber:meeting:#{SecureRandom.hex(8)}",
    cached_at: Time.current - rand(1..24).hours,
    duration_ms: rand(10..50),
    parameters: { audio: "cached_meeting_#{i + 1}.mp3" },
    response: { text: 'Cached transcript...', from_cache: true },
    metadata: { cache_hit: true, original_cached_at: Time.current - rand(1..14).days },
    created_at: Time.current - (i * 55).minutes
  )
end
puts '  Created 3 transcriber cache hit executions'

# Chunked large file - Enterprise
2.times do |i|
  create_transcriber_execution(
    tenant_id: enterprise.llm_tenant_id,
    agent_type: 'PodcastTranscriber',
    model_id: 'gpt-4o-transcribe',
    parameters: { audio: "long_recording_#{i + 1}.mp3" },
    response: { text: 'Very long transcription combining multiple chunks...', word_count: rand(20_000..50_000) },
    metadata: {
      audio_duration_seconds: rand(5400..10_800), # 1.5-3 hours
      chunked: true,
      chunks_processed: rand(6..12),
      parallel_processing: true,
      output_format: 'verbose_json'
    },
    created_at: Time.current - (i * 90).minutes
  )
end
puts '  Created 2 chunked transcriber executions'

# Transcriber error - Demo account
create_transcriber_execution(
  tenant_id: demo.llm_tenant_id,
  agent_type: 'MeetingTranscriber',
  status: 'error',
  error_class: 'RubyLLM::APIError',
  error_message: 'Audio file format not supported',
  parameters: { audio: 'invalid_file.txt' },
  response: nil,
  metadata: { error_type: 'invalid_format' },
  created_at: Time.current - 4.hours
)
puts '  Created 1 transcriber error execution'

# =============================================================================
# IMAGE GENERATOR EXECUTIONS
# =============================================================================
puts "\n#{'=' * 60}"
puts 'Creating Image Generator Executions...'
puts '=' * 60

# ProductImageGenerator - Acme e-commerce
8.times do |i|
  products = ['wireless headphones', 'laptop stand', 'mechanical keyboard', 'USB hub', 'webcam', 'desk lamp',
              'monitor', 'mouse']
  create_image_generator_execution(
    tenant_id: acme.llm_tenant_id,
    agent_type: 'ProductImageGenerator',
    model_id: 'gpt-image-1',
    parameters: { prompt: "Professional product photo of #{products[i]}" },
    response: { url: "https://openai.com/generated/product_#{i + 1}.png",
                revised_prompt: 'Studio product photography...' },
    metadata: {
      size: '1024x1024',
      quality: 'hd',
      style: 'natural',
      content_policy: 'strict'
    },
    created_at: Time.current - (i * 12).minutes
  )
end
puts '  Created 8 ProductImageGenerator executions'

# LogoGenerator - Enterprise branding
5.times do |i|
  companies = %w[TechNova DataFlow CloudPeak InnovateLabs QuantumEdge]
  create_image_generator_execution(
    tenant_id: enterprise.llm_tenant_id,
    agent_type: 'LogoGenerator',
    model_id: 'gpt-image-1',
    parameters: { prompt: "Minimalist logo for tech company '#{companies[i]}'" },
    response: { url: "https://openai.com/generated/logo_#{i + 1}.png", revised_prompt: 'Professional logo design...' },
    metadata: {
      size: '1024x1024',
      quality: 'hd',
      style: 'vivid',
      content_policy: 'strict'
    },
    created_at: Time.current - (i * 28).minutes
  )
end
puts '  Created 5 LogoGenerator executions'

# ThumbnailGenerator - Startup video thumbnails
6.times do |i|
  topics = ['AI Revolution', 'Web3 Explained', 'Startup Tips', 'Remote Work', 'Productivity Hacks', 'Tech News']
  create_image_generator_execution(
    tenant_id: startup.llm_tenant_id,
    agent_type: 'ThumbnailGenerator',
    model_id: 'gpt-image-1',
    parameters: { prompt: "YouTube thumbnail for video about #{topics[i]}" },
    response: { url: "https://openai.com/generated/thumb_#{i + 1}.png", revised_prompt: 'Eye-catching thumbnail...' },
    metadata: {
      size: '1792x1024',
      quality: 'standard',
      style: 'vivid',
      content_policy: 'standard'
    },
    created_at: Time.current - (i * 16).minutes
  )
end
puts '  Created 6 ThumbnailGenerator executions'

# AvatarGenerator - Startup user avatars
8.times do |i|
  styles = ['cartoon cat', 'geometric pattern', 'abstract art', 'pixel art character', 'watercolor portrait',
            'minimal icon', 'cyberpunk character', 'fantasy elf']
  create_image_generator_execution(
    tenant_id: startup.llm_tenant_id,
    agent_type: 'AvatarGenerator',
    model_id: 'gpt-image-1',
    parameters: { prompt: "Profile avatar: #{styles[i]}" },
    response: { url: "https://openai.com/generated/avatar_#{i + 1}.png", revised_prompt: 'Unique avatar design...' },
    metadata: {
      size: '1024x1024',
      quality: 'standard',
      style: 'vivid',
      content_policy: 'strict'
    },
    created_at: Time.current - (i * 10).minutes
  )
end
puts '  Created 8 AvatarGenerator executions'

# IllustrationGenerator - Enterprise blog illustrations
4.times do |i|
  topics = ['machine learning concept', 'team collaboration', 'cloud computing', 'data security']
  create_image_generator_execution(
    tenant_id: enterprise.llm_tenant_id,
    agent_type: 'IllustrationGenerator',
    model_id: 'gpt-image-1',
    parameters: { prompt: "Editorial illustration for article about #{topics[i]}" },
    response: { url: "https://openai.com/generated/illustration_#{i + 1}.png",
                revised_prompt: 'Artistic editorial illustration...' },
    metadata: {
      size: '1024x1792',
      quality: 'hd',
      style: 'vivid',
      content_policy: 'standard'
    },
    created_at: Time.current - (i * 32).minutes
  )
end
puts '  Created 4 IllustrationGenerator executions'

# Image generator cache hits - Acme
2.times do |i|
  create_image_generator_execution(
    tenant_id: acme.llm_tenant_id,
    agent_type: 'ProductImageGenerator',
    model_id: 'gpt-image-1',
    cache_hit: true,
    response_cache_key: "image:product:#{SecureRandom.hex(8)}",
    cached_at: Time.current - rand(1..12).hours,
    duration_ms: rand(10..30),
    parameters: { prompt: "Cached product image request #{i + 1}" },
    response: { url: "https://openai.com/cached/product_#{i + 1}.png", from_cache: true },
    metadata: { cache_hit: true, size: '1024x1024', quality: 'hd' },
    created_at: Time.current - (i * 45).minutes
  )
end
puts '  Created 2 image generator cache hit executions'

# Content policy block - Demo account
create_image_generator_execution(
  tenant_id: demo.llm_tenant_id,
  agent_type: 'AvatarGenerator',
  status: 'error',
  error_class: 'RubyLLM::ContentPolicyError',
  error_message: 'Request blocked by content policy',
  parameters: { prompt: '[content blocked by policy]' },
  response: nil,
  metadata: {
    content_policy: 'strict',
    policy_violation: true,
    flagged_categories: ['inappropriate_content']
  },
  created_at: Time.current - 2.hours
)
puts '  Created 1 content policy block execution'

# Image generator API error - Demo account
create_image_generator_execution(
  tenant_id: demo.llm_tenant_id,
  agent_type: 'LogoGenerator',
  status: 'error',
  error_class: 'RubyLLM::APIError',
  error_message: 'Rate limit exceeded for image generation',
  parameters: { prompt: 'Logo design request' },
  response: nil,
  metadata: { rate_limited: true, retry_after: 60 },
  created_at: Time.current - 3.hours
)
puts '  Created 1 image generator error execution'

# =============================================================================
# WORKFLOW EXECUTIONS
# =============================================================================
puts "\n#{'=' * 60}"
puts 'Creating Workflow Executions...'
puts '=' * 60

# ContentAnalyzerWorkflow (Parallel) - Acme content analysis
5.times do |i|
  create_workflow_execution(
    tenant_id: acme.llm_tenant_id,
    agent_type: 'ContentAnalyzerWorkflow',
    model_id: 'gpt-4o-mini',
    parameters: { text: "Content to analyze for sentiment, keywords, and summary #{i + 1}..." },
    response: {
      aggregated: {
        sentiment: 'positive',
        keywords: %w[technology innovation growth],
        summary: 'Key points summarized...'
      }
    },
    metadata: {
      workflow_type: 'parallel',
      branches: {
        sentiment: { status: 'success', duration_ms: rand(500..1500) },
        keywords: { status: 'success', duration_ms: rand(400..1200) },
        summary: { status: 'success', duration_ms: rand(600..1800) }
      },
      fail_fast: false,
      total_branches: 3,
      completed_branches: 3
    },
    created_at: Time.current - (i * 25).minutes
  )
end
puts '  Created 5 ContentAnalyzerWorkflow (parallel) executions'

# ContentPipelineWorkflow (Pipeline) - Enterprise content processing
5.times do |i|
  create_workflow_execution(
    tenant_id: enterprise.llm_tenant_id,
    agent_type: 'ContentPipelineWorkflow',
    model_id: 'gpt-4o',
    parameters: { text: "Raw content to extract, classify, and format #{i + 1}..." },
    response: {
      final_output: {
        extracted_data: { entities: ['Company A', 'Product B'], dates: ['2024-01-15'] },
        classification: 'business_report',
        formatted: "# Business Report\n\n..."
      }
    },
    metadata: {
      workflow_type: 'pipeline',
      steps: {
        extract: { status: 'success', duration_ms: rand(800..2000), agent: 'ExtractorAgent' },
        classify: { status: 'success', duration_ms: rand(400..1000), agent: 'ClassifierAgent' },
        format: { status: 'success', duration_ms: rand(600..1500), agent: 'FormatterAgent' }
      },
      total_steps: 3,
      completed_steps: 3,
      timeout: 60
    },
    created_at: Time.current - (i * 35).minutes
  )
end
puts '  Created 5 ContentPipelineWorkflow (pipeline) executions'

# SupportRouterWorkflow (Router) - Startup customer support
routes = %i[billing technical default billing technical]
5.times do |i|
  chosen_route = routes[i]
  agent = case chosen_route
          when :billing then 'BillingAgent'
          when :technical then 'TechnicalAgent'
          else 'GeneralAgent'
          end
  create_workflow_execution(
    tenant_id: startup.llm_tenant_id,
    agent_type: 'SupportRouterWorkflow',
    model_id: 'gpt-4o-mini',
    temperature: 0.0,
    parameters: { message: "Customer support message #{i + 1}..." },
    response: {
      routed_to: chosen_route,
      classification: {
        chosen_route: chosen_route,
        confidence: rand(0.85..0.99).round(3),
        reasoning: "Message contains #{chosen_route}-related keywords"
      },
      agent_response: "Response from #{agent}..."
    },
    metadata: {
      workflow_type: 'router',
      available_routes: %i[billing technical default],
      chosen_route: chosen_route,
      routed_agent: agent,
      classification_model: 'gpt-4o-mini'
    },
    created_at: Time.current - (i * 20).minutes
  )
end
puts '  Created 5 SupportRouterWorkflow (router) executions'

# =============================================================================
# EMBEDDER DEMONSTRATIONS
# =============================================================================
puts "\n#{'=' * 60}"
puts 'Demonstrating Embedders...'
puts '=' * 60

begin
  embedder_configs = [
    { name: 'Embedders::ApplicationEmbedder', display: 'ApplicationEmbedder' },
    { name: 'Embedders::DocumentEmbedder', display: 'DocumentEmbedder' },
    { name: 'Embedders::SearchEmbedder', display: 'SearchEmbedder' },
    { name: 'Embedders::BatchEmbedder', display: 'BatchEmbedder' },
    { name: 'Embedders::CleanTextEmbedder', display: 'CleanTextEmbedder' },
    { name: 'Embedders::CodeEmbedder', display: 'CodeEmbedder' }
  ]

  embedder_configs.each do |config|
    klass = config[:name].constantize
    puts "  #{config[:display]}:"
    puts "    Model: #{klass.model}"
    puts "    Dimensions: #{klass.dimensions || 'default'}"
    puts "    Cache: #{klass.cache_enabled? ? klass.cache_ttl.inspect : 'disabled'}"
  end
rescue NameError
  puts '  (Embedder classes not loaded - skipping demonstration)'
end

# =============================================================================
# STANDALONE MODERATOR DEMONSTRATIONS
# =============================================================================
puts "\n#{'=' * 60}"
puts 'Demonstrating Standalone Moderators...'
puts '=' * 60

begin
  moderator_configs = [
    { name: 'Moderators::ContentModerator', display: 'ContentModerator' },
    { name: 'Moderators::ChildSafeModerator', display: 'ChildSafeModerator' },
    { name: 'Moderators::ForumModerator', display: 'ForumModerator' }
  ]

  moderator_configs.each do |config|
    klass = config[:name].constantize
    puts "  #{config[:display]}:"
    puts "    Model: #{klass.model}"
    puts "    Threshold: #{klass.threshold}"
    puts "    Categories: #{klass.categories.inspect}"
  end
rescue NameError
  puts '  (Moderator classes not loaded - skipping demonstration)'
end

# =============================================================================
# LEGACY EXECUTIONS (no tenant - backward compatibility)
# =============================================================================
puts "\n#{'=' * 60}"
puts 'Creating executions without tenant (legacy)'
puts '=' * 60

3.times do |i|
  create_execution(
    tenant_id: nil,
    agent_type: 'LegacyAgent',
    parameters: { action: "process_#{i}" },
    response: { status: 'completed' },
    created_at: Time.current - (i * 4).hours
  )
end
puts '  Created 3 legacy agent executions (no tenant)'

# =============================================================================
# DISPLAY USAGE SUMMARIES
# =============================================================================
puts "\n#{'=' * 60}"
puts 'Usage Summaries (LLMTenant DSL Methods)'
puts '=' * 60

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
puts "\n#{'=' * 60}"
puts 'Seeding complete!'
puts '=' * 60

puts "\nOrganizations:"
Organization.all.each do |org|
  puts "  #{org.slug}: plan=#{org.plan}, enforcement=#{org.llm_budget&.enforcement || 'none'}"
end

puts "\nExecutions by Tenant:"
tenant_counts = RubyLLM::Agents::Execution.group(:tenant_id).count
tenant_counts.each do |tenant_id, count|
  tenant_name = tenant_id.nil? ? '(no tenant)' : tenant_id
  puts "  #{tenant_name}: #{count} executions"
end

puts "\nShowcase Agent Executions:"
showcase_agents.each do |agent|
  count = RubyLLM::Agents::Execution.where(agent_type: agent).count
  puts "  #{agent}: #{count}" if count.positive?
end

puts "\nModeration Agent Executions:"
moderation_agents.each do |agent|
  count = RubyLLM::Agents::Execution.where(agent_type: agent).count
  puts "  #{agent}: #{count}" if count.positive?
end

puts "\nEmbedder Executions:"
%w[DocumentEmbedder SearchEmbedder BatchEmbedder CleanTextEmbedder CodeEmbedder].each do |embedder|
  count = RubyLLM::Agents::Execution.where(agent_type: embedder).count
  next unless count.positive?

  klass = "Embedders::#{embedder}".safe_constantize
  if klass
    puts "  #{embedder}: #{count} executions (model=#{klass.model}, dims=#{klass.dimensions || 'default'})"
  else
    puts "  #{embedder}: #{count} executions"
  end
end

puts "\nStandalone Moderator Executions:"
%w[ContentModerator ChildSafeModerator ForumModerator].each do |moderator|
  count = RubyLLM::Agents::Execution.where(agent_type: moderator).count
  next unless count.positive?

  klass = "Moderators::#{moderator}".safe_constantize
  if klass
    puts "  #{moderator}: #{count} executions (threshold=#{klass.threshold})"
  else
    puts "  #{moderator}: #{count} executions"
  end
end

puts "\nSpeaker Executions:"
%w[ArticleNarrator PodcastSpeaker NotificationSpeaker MultilangSpeaker TechnicalNarrator].each do |speaker|
  count = RubyLLM::Agents::Execution.where(agent_type: speaker).count
  next unless count.positive?

  klass = "Audio::#{speaker}".safe_constantize
  if klass
    puts "  #{speaker}: #{count} executions (model=#{klass.model}, voice=#{klass.voice})"
  else
    puts "  #{speaker}: #{count} executions"
  end
end

puts "\nTranscriber Executions:"
%w[MeetingTranscriber SubtitleGenerator PodcastTranscriber MultilingualTranscriber
   TechnicalTranscriber].each do |transcriber|
  count = RubyLLM::Agents::Execution.where(agent_type: transcriber).count
  next unless count.positive?

  klass = "Audio::#{transcriber}".safe_constantize
  if klass
    puts "  #{transcriber}: #{count} executions (model=#{klass.model})"
  else
    puts "  #{transcriber}: #{count} executions"
  end
end

puts "\nImage Generator Executions:"
%w[ProductImageGenerator LogoGenerator ThumbnailGenerator AvatarGenerator IllustrationGenerator].each do |generator|
  count = RubyLLM::Agents::Execution.where(agent_type: generator).count
  next unless count.positive?

  klass = "Images::#{generator}".safe_constantize
  if klass
    puts "  #{generator}: #{count} executions (size=#{klass.size}, quality=#{klass.quality})"
  else
    puts "  #{generator}: #{count} executions"
  end
end

puts "\nWorkflow Executions:"
%w[ContentAnalyzerWorkflow ContentPipelineWorkflow SupportRouterWorkflow].each do |workflow|
  count = RubyLLM::Agents::Execution.where(agent_type: workflow).count
  puts "  #{workflow}: #{count} executions" if count.positive?
end

puts "\nEmbedders Available:"
%w[ApplicationEmbedder DocumentEmbedder SearchEmbedder BatchEmbedder CleanTextEmbedder CodeEmbedder].each do |embedder|
  klass = "Embedders::#{embedder}".safe_constantize
  puts "  #{embedder}: model=#{klass.model}, dimensions=#{klass.dimensions || 'default'}" if klass
end

puts "\nStandalone Moderators Available:"
%w[ContentModerator ChildSafeModerator ForumModerator].each do |moderator|
  klass = "Moderators::#{moderator}".safe_constantize
  puts "  #{moderator}: threshold=#{klass.threshold}, categories=#{klass.categories.length}" if klass
end

puts "\nSpeakers Available:"
%w[ApplicationSpeaker ArticleNarrator PodcastSpeaker NotificationSpeaker MultilangSpeaker
   TechnicalNarrator].each do |speaker|
  klass = "Audio::#{speaker}".safe_constantize
  puts "  #{speaker}: model=#{klass.model}, voice=#{klass.voice}" if klass
end

puts "\nTranscribers Available:"
%w[ApplicationTranscriber MeetingTranscriber SubtitleGenerator PodcastTranscriber MultilingualTranscriber
   TechnicalTranscriber].each do |transcriber|
  klass = "Audio::#{transcriber}".safe_constantize
  puts "  #{transcriber}: model=#{klass.model}, format=#{klass.output_format}" if klass
end

puts "\nImage Generators Available:"
%w[ApplicationImageGenerator ProductImageGenerator LogoGenerator ThumbnailGenerator AvatarGenerator
   IllustrationGenerator].each do |generator|
  klass = "Images::#{generator}".safe_constantize
  puts "  #{generator}: model=#{klass.model}, size=#{klass.size}, quality=#{klass.quality}" if klass
end

puts "\nWorkflows Available:"
%w[ContentAnalyzerWorkflow ContentPipelineWorkflow SupportRouterWorkflow].each do |workflow|
  klass = workflow.safe_constantize
  puts "  #{workflow}: #{klass.description}" if klass
end

puts "\nTotal: #{Organization.count} organizations, #{RubyLLM::Agents::Execution.count} executions"
puts "\nStart the server with: bin/rails server"
puts 'Then visit: http://localhost:3000/agents'
puts "\nTo test tenant filtering, append ?tenant_id=acme-corp to the URL"
