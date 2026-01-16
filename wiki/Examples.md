# Examples

Real-world agent patterns and use cases.

## Search & Classification

### Search Intent Extraction

```ruby
class SearchIntentAgent < ApplicationAgent
  model "gpt-4o-mini"
  temperature 0.0
  cache 30.minutes

  param :query, required: true

  def user_prompt
    "Extract search intent from: #{query}"
  end

  def schema
    @schema ||= RubyLLM::Schema.create do
      string :refined_query, description: "Cleaned search query"
      array :filters, of: :string, description: "Filters as type:value"
      integer :category_id, nullable: true
      number :confidence
    end
  end
end

# Usage
result = SearchIntentAgent.call(query: "red dress under $50")
# => { refined_query: "red dress", filters: ["color:red", "price:<50"], ... }
```

### Email Classifier

```ruby
class EmailClassifierAgent < ApplicationAgent
  model "gpt-4o-mini"
  temperature 0.0

  param :subject, required: true
  param :body, required: true
  param :sender

  def system_prompt
    <<~PROMPT
      You are an email classification system. Categorize emails
      based on content, urgency, and required action.
    PROMPT
  end

  def user_prompt
    <<~PROMPT
      Subject: #{subject}
      From: #{sender}
      Body: #{body}
    PROMPT
  end

  def schema
    @schema ||= RubyLLM::Schema.create do
      string :category, enum: %w[urgent important routine spam]
      string :department, enum: %w[sales support billing general]
      boolean :requires_response
      integer :priority, description: "1-5, 5 being highest"
      array :tags, of: :string
    end
  end
end
```

## Content Generation

### Blog Post Generator

```ruby
class BlogPostAgent < ApplicationAgent
  model "gpt-4o"
  temperature 0.7
  timeout 120

  param :topic, required: true
  param :tone, default: "professional"
  param :word_count, default: 800

  def system_prompt
    <<~PROMPT
      You are an expert content writer. Write engaging, well-structured
      blog posts that are SEO-friendly and informative.
    PROMPT
  end

  def user_prompt
    <<~PROMPT
      Write a #{word_count}-word blog post about: #{topic}

      Tone: #{tone}

      Requirements:
      - Engaging introduction
      - 3-5 main sections with headers
      - Practical examples or tips
      - Strong conclusion with call-to-action
    PROMPT
  end

  def schema
    @schema ||= RubyLLM::Schema.create do
      string :title
      string :meta_description, description: "SEO meta description, 150 chars"
      string :content, description: "Full blog post in Markdown"
      array :tags, of: :string
    end
  end
end
```

### Product Description Writer

```ruby
class ProductDescriptionAgent < ApplicationAgent
  model "gpt-4o"
  temperature 0.6

  param :product_name, required: true
  param :features, required: true
  param :target_audience, default: "general consumers"

  def user_prompt
    <<~PROMPT
      Create a compelling product description for:

      Product: #{product_name}
      Features: #{features.join(", ")}
      Target Audience: #{target_audience}
    PROMPT
  end

  def schema
    @schema ||= RubyLLM::Schema.create do
      string :headline, description: "Attention-grabbing headline"
      string :short_description, description: "50-word summary"
      string :full_description, description: "Detailed description"
      array :bullet_points, of: :string, description: "Key selling points"
    end
  end
end
```

## Data Extraction

### Invoice Parser

```ruby
class InvoiceParserAgent < ApplicationAgent
  model "gpt-4o"  # Vision capable

  param :invoice_path, required: true

  def user_prompt
    "Extract all invoice details from this document."
  end

  def schema
    @schema ||= RubyLLM::Schema.create do
      string :invoice_number
      string :date
      string :due_date, nullable: true
      object :vendor do
        string :name
        string :address, nullable: true
      end
      object :customer do
        string :name
        string :address, nullable: true
      end
      array :line_items, of: :object do
        string :description
        integer :quantity
        number :unit_price
        number :total
      end
      number :subtotal
      number :tax, nullable: true
      number :total
      string :currency, default: "USD"
    end
  end
end

# Usage with attachment
result = InvoiceParserAgent.call(
  invoice_path: "path",
  with: "invoice.pdf"
)
```

### Resume Parser

```ruby
class ResumeParserAgent < ApplicationAgent
  model "gpt-4o"

  param :resume_text, required: true

  def user_prompt
    <<~PROMPT
      Parse this resume and extract structured information:

      #{resume_text}
    PROMPT
  end

  def schema
    @schema ||= RubyLLM::Schema.create do
      object :contact do
        string :name
        string :email, nullable: true
        string :phone, nullable: true
        string :location, nullable: true
      end
      string :summary, nullable: true
      array :experience, of: :object do
        string :company
        string :title
        string :dates
        array :responsibilities, of: :string
      end
      array :education, of: :object do
        string :institution
        string :degree
        string :year, nullable: true
      end
      array :skills, of: :string
    end
  end
end
```

## Conversational Agents

### Customer Support Bot

```ruby
class SupportAgent < ApplicationAgent
  model "gpt-4o"
  temperature 0.3

  param :message, required: true
  param :conversation_history, default: []
  param :customer_info, default: {}

  def system_prompt
    <<~PROMPT
      You are a helpful customer support agent for TechStore.

      Key information:
      - Return policy: 30 days, unopened items
      - Shipping: Free over $50
      - Support hours: 9 AM - 9 PM EST

      Customer info: #{customer_info.to_json}

      Be helpful, professional, and concise. If you can't help,
      offer to escalate to a human agent.
    PROMPT
  end

  def user_prompt
    history = conversation_history.map do |msg|
      "#{msg[:role].capitalize}: #{msg[:content]}"
    end.join("\n")

    "#{history}\nCustomer: #{message}"
  end

  def schema
    @schema ||= RubyLLM::Schema.create do
      string :response
      boolean :needs_escalation
      string :escalation_reason, nullable: true
      array :suggested_actions, of: :string
    end
  end
end
```

## Multi-Agent Workflows

### Content Pipeline

```ruby
# Step 1: Research
class ResearchAgent < ApplicationAgent
  model "gpt-4o"
  param :topic, required: true

  def user_prompt
    "Research key points about: #{topic}"
  end

  def schema
    @schema ||= RubyLLM::Schema.create do
      array :key_points, of: :string
      array :sources, of: :string
    end
  end
end

# Step 2: Outline
class OutlineAgent < ApplicationAgent
  model "gpt-4o-mini"
  param :key_points, required: true

  def user_prompt
    "Create an outline from: #{key_points.join(', ')}"
  end

  def schema
    @schema ||= RubyLLM::Schema.create do
      array :sections, of: :object do
        string :title
        array :points, of: :string
      end
    end
  end
end

# Step 3: Write
class WriterAgent < ApplicationAgent
  model "gpt-4o"
  param :outline, required: true

  def user_prompt
    "Write content following this outline: #{outline.to_json}"
  end
end

# Pipeline
content_pipeline = RubyLLM::Agents::Workflow.pipeline(
  ResearchAgent,
  OutlineAgent,
  WriterAgent,
  before_step: {
    OutlineAgent => ->(prev, _) { { key_points: prev[:key_points] } },
    WriterAgent => ->(prev, _) { { outline: prev[:sections] } }
  }
)

result = content_pipeline.call(topic: "AI in Healthcare")
```

### Parallel Analysis

```ruby
analysis_workflow = RubyLLM::Agents::Workflow.parallel(
  sentiment: SentimentAgent,
  entities: EntityExtractorAgent,
  summary: SummarizerAgent,
  categories: CategoryClassifierAgent
)

result = analysis_workflow.call(text: document_content)
# => {
#   sentiment: { score: 0.8, label: "positive" },
#   entities: { people: [...], places: [...] },
#   summary: { text: "..." },
#   categories: { primary: "tech", tags: [...] }
# }
```

### Intent Router

```ruby
class IntentClassifier < ApplicationAgent
  model "gpt-4o-mini"
  temperature 0.0
  param :message, required: true

  def user_prompt
    "Classify intent: #{message}"
  end

  def schema
    @schema ||= RubyLLM::Schema.create do
      string :intent, enum: %w[support sales billing general]
      number :confidence
    end
  end
end

support_router = RubyLLM::Agents::Workflow.router(
  classifier: IntentClassifier,
  routes: {
    "support" => TechnicalSupportAgent,
    "sales" => SalesAgent,
    "billing" => BillingAgent
  },
  default: GeneralHelpAgent,
  confidence_threshold: 0.7
)

result = support_router.call(message: "How do I reset my password?")
```

## Testing Agents

### RSpec Example

```ruby
RSpec.describe SearchIntentAgent do
  describe ".call" do
    it "extracts search intent" do
      result = described_class.call(
        query: "red dress under $50",
        dry_run: true
      )

      expect(result[:dry_run]).to be true
      expect(result[:agent]).to eq("SearchIntentAgent")
    end

    context "with mocked response" do
      before do
        allow_any_instance_of(RubyLLM::Chat).to receive(:ask)
          .and_return(double(content: {
            refined_query: "red dress",
            filters: ["color:red"],
            category_id: 42
          }.to_json))
      end

      it "processes the response" do
        result = described_class.call(query: "red dress")

        expect(result[:refined_query]).to eq("red dress")
        expect(result[:filters]).to include("color:red")
      end
    end
  end
end
```

## Rails Integration

### Controller Integration

```ruby
# app/controllers/api/v1/search_controller.rb
class Api::V1::SearchController < ApplicationController
  def search
    result = SearchIntentAgent.call(
      query: params[:q],
      user_id: current_user.id
    )

    if result.success?
      render json: {
        data: result.content,
        meta: {
          model: result.chosen_model_id,
          tokens: result.total_tokens,
          cost: result.total_cost,
          duration_ms: result.duration_ms
        }
      }
    else
      render json: {
        error: result.error,
        retryable: result.retryable?
      }, status: :unprocessable_entity
    end
  rescue RubyLLM::Agents::BudgetExceededError
    render json: { error: "Service limit reached" }, status: :service_unavailable
  rescue RubyLLM::Agents::CircuitBreakerOpenError => e
    response.headers["Retry-After"] = (e.remaining_ms / 1000).to_s
    render json: { error: "Service temporarily unavailable" }, status: :service_unavailable
  end
end
```

### Background Job Pattern

```ruby
# app/jobs/content_generation_job.rb
class ContentGenerationJob < ApplicationJob
  queue_as :default

  # Retry on transient errors
  retry_on RubyLLM::Agents::CircuitBreakerOpenError, wait: :polynomially_longer, attempts: 3

  # Don't retry budget errors
  discard_on RubyLLM::Agents::BudgetExceededError

  def perform(article_id)
    article = Article.find(article_id)

    result = ContentGeneratorAgent.call(
      topic: article.topic,
      tone: article.tone,
      word_count: article.target_word_count
    )

    if result.success?
      article.update!(
        content: result.content[:content],
        title: result.content[:title],
        status: :completed,
        generation_cost: result.total_cost
      )
    else
      article.update!(
        status: :failed,
        error_message: result.error
      )
    end
  end
end

# Enqueue the job
ContentGenerationJob.perform_later(article.id)
```

### Streaming with Action Cable

```ruby
# app/agents/streaming_chat_agent.rb
class StreamingChatAgent < ApplicationAgent
  model "gpt-4o"
  streaming true

  param :message, required: true
  param :channel, required: true

  def user_prompt
    message
  end

  def on_chunk(chunk)
    channel.broadcast_chunk(chunk)
  end
end

# app/channels/chat_channel.rb
class ChatChannel < ApplicationCable::Channel
  def subscribed
    stream_from "chat_#{params[:room_id]}"
  end

  def receive(data)
    StreamingChatAgent.call(
      message: data["message"],
      channel: self
    )
  end

  def broadcast_chunk(chunk)
    ActionCable.server.broadcast(
      "chat_#{params[:room_id]}",
      { type: "chunk", content: chunk }
    )
  end
end
```

### Multi-Tenant Agent with Execution Metadata

```ruby
# app/agents/tenant_aware_agent.rb
class TenantAwareAgent < ApplicationAgent
  model "gpt-4o"
  description "Processes queries with tenant isolation"

  reliability do
    retries max: 3, backoff: :exponential
    fallback_models "gpt-4o-mini"
    circuit_breaker errors: 5, within: 60, cooldown: 180
  end

  param :query, required: true

  def user_prompt
    query
  end

  def execution_metadata
    {
      tenant_id: Current.tenant_id,
      tenant_name: Current.tenant&.name,
      user_id: Current.user&.id,
      request_id: Current.request_id,
      source: "web"
    }
  end
end

# Usage in controller
class QueriesController < ApplicationController
  def create
    result = TenantAwareAgent.call(query: params[:query])

    respond_to do |format|
      format.json { render json: result.content }
    end
  end
end
```

### Rake Task Usage

```ruby
# lib/tasks/agents.rake
namespace :agents do
  desc "Generate content for pending articles"
  task generate_content: :environment do
    Article.pending.find_each do |article|
      print "Processing article #{article.id}..."

      result = ContentGeneratorAgent.call(
        topic: article.topic,
        dry_run: ENV["DRY_RUN"].present?
      )

      if result.success?
        article.update!(content: result.content[:content], status: :completed)
        puts " done (#{result.total_tokens} tokens, $#{result.total_cost})"
      else
        puts " failed: #{result.error}"
      end
    rescue RubyLLM::Agents::BudgetExceededError
      puts "\nBudget exceeded, stopping."
      break
    end
  end

  desc "Show agent statistics"
  task stats: :environment do
    puts "Agent Statistics (Last 7 Days)"
    puts "=" * 50

    RubyLLM::Agents::Execution
      .last_7_days
      .group(:agent_type)
      .select(
        :agent_type,
        "COUNT(*) as total",
        "SUM(total_cost) as cost",
        "AVG(duration_ms) as avg_duration"
      )
      .each do |stat|
        puts "#{stat.agent_type}:"
        puts "  Executions: #{stat.total}"
        puts "  Total Cost: $#{stat.cost.round(4)}"
        puts "  Avg Duration: #{stat.avg_duration.round}ms"
        puts
      end
  end
end
```

### Error Handling and Recovery

```ruby
# app/services/resilient_agent_service.rb
class ResilientAgentService
  def initialize(agent_class)
    @agent_class = agent_class
  end

  def call(**params)
    result = @agent_class.call(**params)

    if result.success?
      Success.new(result.content)
    else
      handle_failure(result)
    end
  rescue RubyLLM::Agents::BudgetExceededError => e
    Failure.new(:budget_exceeded, e.message)
  rescue RubyLLM::Agents::CircuitBreakerOpenError => e
    Failure.new(:circuit_open, e.message, retry_after: e.remaining_ms)
  rescue RubyLLM::Agents::TimeoutError => e
    Failure.new(:timeout, e.message)
  end

  private

  def handle_failure(result)
    if result.retryable?
      Failure.new(:retryable, result.error)
    else
      Failure.new(:permanent, result.error)
    end
  end

  Success = Struct.new(:data) do
    def success? = true
    def failure? = false
  end

  Failure = Struct.new(:type, :message, :retry_after) do
    def success? = false
    def failure? = true
  end
end

# Usage
service = ResilientAgentService.new(SearchAgent)
result = service.call(query: "test")

case result
in Success(data:)
  render json: data
in Failure(type: :budget_exceeded)
  render json: { error: "Limit reached" }, status: 503
in Failure(type: :circuit_open, retry_after:)
  response.headers["Retry-After"] = (retry_after / 1000).to_s
  render json: { error: "Try again later" }, status: 503
in Failure(type: :retryable, message:)
  AgentRetryJob.perform_later(params)
  render json: { status: "queued" }, status: 202
in Failure(type: :permanent, message:)
  render json: { error: message }, status: 422
end
```

### Service Object Pattern

```ruby
# app/services/document_analyzer.rb
class DocumentAnalyzer
  def initialize(document)
    @document = document
  end

  def analyze
    # Run multiple analyses in parallel using workflow
    result = AnalysisWorkflow.call(text: @document.content)

    {
      sentiment: result.branches[:sentiment].content,
      entities: result.branches[:entities].content,
      summary: result.branches[:summary].content,
      total_cost: result.total_cost
    }
  end
end

# app/workflows/analysis_workflow.rb
class AnalysisWorkflow < RubyLLM::Agents::Workflow::Parallel
  fail_fast false

  branch :sentiment, agent: SentimentAgent
  branch :entities, agent: EntityExtractorAgent
  branch :summary, agent: SummarizerAgent
end
```

## Related Pages

- [Agent DSL](Agent-DSL) - Configuration reference
- [Workflows](Workflows) - Workflow patterns
- [Prompts and Schemas](Prompts-and-Schemas) - Structuring outputs
- [Error Handling](Error-Handling) - Error types and recovery
- [Testing Agents](Testing-Agents) - Testing patterns
- [Multi-Tenancy](Multi-Tenancy) - Multi-tenant configuration
