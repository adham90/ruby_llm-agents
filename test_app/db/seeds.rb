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
puts "Clearing existing executions..."
RubyLLM::Agents::Execution.destroy_all

# =============================================================================
# 1. Regular Agent Executions (various statuses)
# =============================================================================
puts "Creating regular agent executions..."

# Successful executions
5.times do |i|
  create_execution(
    agent_type: "SearchAgent",
    parameters: { query: "How to implement #{%w[authentication caching routing validation].sample}?" },
    response: { content: "Here's how to implement it..." },
    metadata: { request_id: SecureRandom.uuid },
    created_at: Time.current - (i * 2).hours
  )
end

3.times do |i|
  create_execution(
    agent_type: "SummaryAgent",
    model_id: "gpt-4o",
    parameters: { text: "Long document content..." },
    response: { summary: "This document discusses..." },
    created_at: Time.current - (i * 3).hours
  )
end

# Failed execution
create_execution(
  agent_type: "TranslationAgent",
  status: "error",
  error_class: "RubyLLM::RateLimitError",
  error_message: "Rate limit exceeded. Please retry after 60 seconds.",
  rate_limited: true,
  retryable: true,
  parameters: { text: "Hello world", target_language: "es" },
  created_at: Time.current - 30.minutes
)

# Timeout execution
create_execution(
  agent_type: "AnalysisAgent",
  status: "timeout",
  error_class: "Timeout::Error",
  error_message: "Execution exceeded 30 second timeout",
  parameters: { data: "Large dataset..." },
  duration_ms: 30000,
  created_at: Time.current - 45.minutes
)

# Running execution
create_execution(
  agent_type: "ReportAgent",
  status: "running",
  parameters: { report_type: "monthly", format: "pdf" },
  completed_at: nil,
  duration_ms: nil,
  output_tokens: nil,
  created_at: Time.current - 2.minutes
)

# Cached execution
create_execution(
  agent_type: "SearchAgent",
  cache_hit: true,
  response_cache_key: "search_agent:v1:abc123",
  cached_at: Time.current - 1.hour,
  duration_ms: 5,
  parameters: { query: "What is Ruby on Rails?" },
  response: { content: "Ruby on Rails is a web framework..." },
  created_at: Time.current - 10.minutes
)

# Execution with tool calls
create_execution(
  agent_type: "AssistantAgent",
  model_id: "gpt-4o",
  finish_reason: "tool_calls",
  tool_calls: [
    { id: "call_abc123", name: "search_web", arguments: { query: "latest news" } },
    { id: "call_def456", name: "calculate", arguments: { expression: "2 + 2" } }
  ],
  tool_calls_count: 2,
  parameters: { message: "Search for latest news and calculate 2+2" },
  response: { content: "I found the news and the answer is 4." },
  created_at: Time.current - 15.minutes
)

# Execution with retries/fallback
create_execution(
  agent_type: "ReliableAgent",
  model_id: "gpt-4o",
  chosen_model_id: "gpt-4o-mini",
  fallback_reason: "rate_limit",
  fallback_chain: ["gpt-4o", "gpt-4o-mini", "gemini-2.0-flash"],
  attempts: [
    { model_id: "gpt-4o", error_class: "RubyLLM::RateLimitError", error_message: "Rate limited", duration_ms: 150 },
    { model_id: "gpt-4o-mini", input_tokens: 500, output_tokens: 200, duration_ms: 1200 }
  ],
  attempts_count: 2,
  parameters: { prompt: "Generate a story" },
  response: { content: "Once upon a time..." },
  created_at: Time.current - 20.minutes
)

# =============================================================================
# 2. Pipeline Workflow
# =============================================================================
puts "Creating pipeline workflow..."

workflow_id = SecureRandom.uuid
pipeline_started = Time.current - 1.hour

# Create the root pipeline execution
pipeline_root = create_execution(
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

# Pipeline Step 1: Extract
step1 = create_execution(
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

# Pipeline Step 2: Classify
step2 = create_execution(
  agent_type: "ClassifierAgent",
  workflow_type: "pipeline",
  workflow_id: workflow_id,
  workflow_step: "classify",
  parent_execution_id: pipeline_root.id,
  root_execution_id: pipeline_root.id,
  model_id: "gpt-4o-mini",
  temperature: 0.0,
  parameters: { text: "Entities: AI, ML, trends. Key points: 3" },
  response: { category: "technology", confidence: 0.95 },
  started_at: pipeline_started + 1.3.seconds,
  completed_at: pipeline_started + 2.1.seconds,
  duration_ms: 800,
  input_tokens: 200,
  output_tokens: 50,
  created_at: pipeline_started + 1.3.seconds
)

# Pipeline Step 3: Format
step3 = create_execution(
  agent_type: "FormatterAgent",
  workflow_type: "pipeline",
  workflow_id: workflow_id,
  workflow_step: "format",
  parent_execution_id: pipeline_root.id,
  root_execution_id: pipeline_root.id,
  model_id: "gpt-4o-mini",
  temperature: 0.3,
  parameters: { text: "Entities and classification data...", category: "technology" },
  response: { formatted: "# Analysis Report\n\nKey findings..." },
  started_at: pipeline_started + 2.2.seconds,
  completed_at: pipeline_started + 4.4.seconds,
  duration_ms: 2200,
  input_tokens: 350,
  output_tokens: 400,
  created_at: pipeline_started + 2.2.seconds
)

puts "  Created pipeline with #{pipeline_root.child_executions.count} steps"

# =============================================================================
# 3. Parallel Workflow
# =============================================================================
puts "Creating parallel workflow..."

parallel_workflow_id = SecureRandom.uuid
parallel_started = Time.current - 45.minutes

# Create the root parallel execution
parallel_root = create_execution(
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

# Parallel Branch 1: Sentiment (fastest)
branch1 = create_execution(
  agent_type: "SentimentAgent",
  workflow_type: "parallel",
  workflow_id: parallel_workflow_id,
  workflow_step: "sentiment",
  parent_execution_id: parallel_root.id,
  root_execution_id: parallel_root.id,
  model_id: "gpt-4o-mini",
  temperature: 0.0,
  parameters: { text: "The new product launch exceeded expectations..." },
  response: { sentiment: "positive", score: 0.89 },
  started_at: parallel_started,
  completed_at: parallel_started + 0.9.seconds,
  duration_ms: 900,
  input_tokens: 180,
  output_tokens: 30,
  created_at: parallel_started
)

# Parallel Branch 2: Keywords
branch2 = create_execution(
  agent_type: "KeywordAgent",
  workflow_type: "parallel",
  workflow_id: parallel_workflow_id,
  workflow_step: "keywords",
  parent_execution_id: parallel_root.id,
  root_execution_id: parallel_root.id,
  model_id: "gpt-4o-mini",
  temperature: 0.0,
  parameters: { text: "The new product launch exceeded expectations..." },
  response: { keywords: ["product", "launch", "growth", "expectations", "exceeded"] },
  started_at: parallel_started,
  completed_at: parallel_started + 1.5.seconds,
  duration_ms: 1500,
  input_tokens: 180,
  output_tokens: 60,
  created_at: parallel_started
)

# Parallel Branch 3: Summary (slowest)
branch3 = create_execution(
  agent_type: "SummaryAgent",
  workflow_type: "parallel",
  workflow_id: parallel_workflow_id,
  workflow_step: "summary",
  parent_execution_id: parallel_root.id,
  root_execution_id: parallel_root.id,
  model_id: "gpt-4o-mini",
  temperature: 0.3,
  parameters: { text: "The new product launch exceeded expectations..." },
  response: { summary: "Successful product launch with 50% growth, exceeding all expectations." },
  started_at: parallel_started,
  completed_at: parallel_started + 2.7.seconds,
  duration_ms: 2700,
  input_tokens: 180,
  output_tokens: 80,
  created_at: parallel_started
)

puts "  Created parallel workflow with #{parallel_root.child_executions.count} branches"

# =============================================================================
# 4. Router Workflow
# =============================================================================
puts "Creating router workflow..."

router_workflow_id = SecureRandom.uuid
router_started = Time.current - 30.minutes

# Create the root router execution
router_root = create_execution(
  agent_type: "SupportRouter",
  workflow_type: "router",
  workflow_id: router_workflow_id,
  routed_to: "billing",
  classification_result: {
    method: "llm",
    classifier_model: "gpt-4o-mini",
    classification_time_ms: 450,
    confidence: 0.92,
    alternatives: [
      { route: "billing", score: 0.92 },
      { route: "technical", score: 0.05 },
      { route: "general", score: 0.03 }
    ]
  },
  parameters: { message: "I was charged twice for my subscription last month" },
  response: { content: "I understand you've been double charged. Let me help resolve this billing issue..." },
  started_at: router_started,
  completed_at: router_started + 3.2.seconds,
  duration_ms: 3200,
  created_at: router_started
)

# Routed execution: BillingAgent
routed_execution = create_execution(
  agent_type: "BillingAgent",
  workflow_type: "router",
  workflow_id: router_workflow_id,
  workflow_step: "billing",
  parent_execution_id: router_root.id,
  root_execution_id: router_root.id,
  model_id: "gpt-4o",
  temperature: 0.3,
  parameters: {
    message: "I was charged twice for my subscription last month",
    routed_at: router_started + 0.5.seconds,
    route_context: "billing"
  },
  response: {
    content: "I apologize for the inconvenience. I can see the duplicate charge in your account. I've initiated a refund which should appear in 3-5 business days.",
    actions_taken: ["identified_duplicate", "initiated_refund"]
  },
  started_at: router_started + 0.5.seconds,
  completed_at: router_started + 3.1.seconds,
  duration_ms: 2600,
  input_tokens: 380,
  output_tokens: 150,
  created_at: router_started + 0.5.seconds
)

puts "  Created router workflow routed to: #{router_root.routed_to}"

# =============================================================================
# 5. Failed Pipeline Workflow (for error state testing)
# =============================================================================
puts "Creating failed pipeline workflow..."

failed_workflow_id = SecureRandom.uuid
failed_started = Time.current - 2.hours

failed_pipeline = create_execution(
  agent_type: "ContentPipeline",
  workflow_type: "pipeline",
  workflow_id: failed_workflow_id,
  status: "error",
  error_class: "RubyLLM::ContentFilterError",
  error_message: "Content was blocked by safety filters",
  parameters: { text: "Some problematic content..." },
  started_at: failed_started,
  completed_at: failed_started + 1.8.seconds,
  duration_ms: 1800,
  created_at: failed_started
)

# First step succeeded
failed_step1 = create_execution(
  agent_type: "ExtractorAgent",
  workflow_type: "pipeline",
  workflow_id: failed_workflow_id,
  workflow_step: "extract",
  parent_execution_id: failed_pipeline.id,
  root_execution_id: failed_pipeline.id,
  parameters: { text: "Some problematic content..." },
  response: { entities: ["content"] },
  started_at: failed_started,
  completed_at: failed_started + 0.8.seconds,
  duration_ms: 800,
  created_at: failed_started
)

# Second step failed
failed_step2 = create_execution(
  agent_type: "ClassifierAgent",
  workflow_type: "pipeline",
  workflow_id: failed_workflow_id,
  workflow_step: "classify",
  parent_execution_id: failed_pipeline.id,
  root_execution_id: failed_pipeline.id,
  status: "error",
  error_class: "RubyLLM::ContentFilterError",
  error_message: "Content was blocked by safety filters",
  finish_reason: "content_filter",
  parameters: { text: "Extracted entities..." },
  started_at: failed_started + 0.9.seconds,
  completed_at: failed_started + 1.7.seconds,
  duration_ms: 800,
  created_at: failed_started + 0.9.seconds
)

puts "  Created failed pipeline (error at step 2)"

# =============================================================================
# 6. Parallel Workflow with Mixed Results
# =============================================================================
puts "Creating parallel workflow with mixed results..."

mixed_workflow_id = SecureRandom.uuid
mixed_started = Time.current - 1.5.hours

mixed_parallel = create_execution(
  agent_type: "ContentAnalyzer",
  workflow_type: "parallel",
  workflow_id: mixed_workflow_id,
  status: "success", # Overall success despite one failure
  parameters: { text: "Complex analysis request..." },
  response: { partial_results: true },
  started_at: mixed_started,
  completed_at: mixed_started + 3.5.seconds,
  duration_ms: 3500,
  created_at: mixed_started
)

# Branch 1: Success
create_execution(
  agent_type: "SentimentAgent",
  workflow_type: "parallel",
  workflow_id: mixed_workflow_id,
  workflow_step: "sentiment",
  parent_execution_id: mixed_parallel.id,
  root_execution_id: mixed_parallel.id,
  parameters: { text: "Complex analysis..." },
  response: { sentiment: "neutral" },
  started_at: mixed_started,
  completed_at: mixed_started + 1.2.seconds,
  duration_ms: 1200,
  created_at: mixed_started
)

# Branch 2: Timeout
create_execution(
  agent_type: "KeywordAgent",
  workflow_type: "parallel",
  workflow_id: mixed_workflow_id,
  workflow_step: "keywords",
  parent_execution_id: mixed_parallel.id,
  root_execution_id: mixed_parallel.id,
  status: "timeout",
  error_class: "Timeout::Error",
  error_message: "Execution exceeded timeout",
  parameters: { text: "Complex analysis..." },
  started_at: mixed_started,
  completed_at: mixed_started + 3.4.seconds,
  duration_ms: 3400,
  created_at: mixed_started
)

# Branch 3: Success
create_execution(
  agent_type: "SummaryAgent",
  workflow_type: "parallel",
  workflow_id: mixed_workflow_id,
  workflow_step: "summary",
  parent_execution_id: mixed_parallel.id,
  root_execution_id: mixed_parallel.id,
  parameters: { text: "Complex analysis..." },
  response: { summary: "Partial analysis completed." },
  started_at: mixed_started,
  completed_at: mixed_started + 2.1.seconds,
  duration_ms: 2100,
  created_at: mixed_started
)

puts "  Created parallel workflow with mixed results (1 timeout)"

# =============================================================================
# Summary
# =============================================================================
puts ""
puts "=" * 60
puts "Seeding complete!"
puts "=" * 60
puts ""
puts "Created:"
puts "  - #{RubyLLM::Agents::Execution.where(workflow_type: nil).count} regular agent executions"
puts "  - #{RubyLLM::Agents::Execution.where(workflow_type: 'pipeline', parent_execution_id: nil).count} pipeline workflows"
puts "  - #{RubyLLM::Agents::Execution.where(workflow_type: 'parallel', parent_execution_id: nil).count} parallel workflows"
puts "  - #{RubyLLM::Agents::Execution.where(workflow_type: 'router', parent_execution_id: nil).count} router workflows"
puts ""
puts "Total executions: #{RubyLLM::Agents::Execution.count}"
puts ""
puts "Start the server with: bin/rails server"
puts "Then visit: http://localhost:3000/agents"
