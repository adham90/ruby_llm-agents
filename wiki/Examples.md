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

## Related Pages

- [Agent DSL](Agent-DSL) - Configuration reference
- [Workflows](Workflows) - Workflow patterns
- [Prompts and Schemas](Prompts-and-Schemas) - Structuring outputs
