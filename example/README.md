# Ruby LLM Agents - Example Application

This is a reference Rails application demonstrating the `ruby_llm-agents` gem.
Use it to explore the dashboard, test generators, and as a reference for example code.

## Quick Start

```bash
cd example
bundle install
bin/rails db:setup
bin/rails server
```

Then visit http://localhost:3000/agents to see the dashboard.

## Directory Structure

```
app/
  agents/           # Example agent implementations
    application_agent.rb    # Base agent class
    ...

    workflows/      # Multi-agent orchestration examples
      application_workflow.rb   # Base workflow class with DSL reference
      content_pipeline.rb       # Sequential pipeline: extract >> classify >> format
      content_analyzer.rb       # Parallel execution: sentiment + keywords + summary
      support_workflow.rb       # Dispatch routing: classify then route to specialist
      extractor_agent.rb        # Pipeline step: data extraction
      classifier_agent.rb       # Pipeline step: content classification
      formatter_agent.rb        # Pipeline step: report formatting
      sentiment_agent.rb        # Parallel step: sentiment analysis
      keyword_agent.rb          # Parallel step: keyword extraction
      summary_agent.rb          # Parallel step: summarization
      support_classifier.rb     # Router step: message classification
      billing_agent.rb          # Dispatch target: billing support
      technical_agent.rb        # Dispatch target: technical support
      general_agent.rb          # Dispatch target: general support

  image_analyzers/  # Example image analyzer implementations
    application_image_analyzer.rb   # Base analyzer with DSL reference
    product_analyzer.rb             # E-commerce product analysis
    content_analyzer.rb             # Content moderation analysis
    scene_analyzer.rb               # Scene understanding

  background_removers/  # Example background remover implementations
    application_background_remover.rb   # Base remover with DSL reference
    product_background_remover.rb       # E-commerce product cutouts
    portrait_background_remover.rb      # Portrait extraction
    simple_background_remover.rb        # Fast simple removal

  image_pipelines/  # Example image pipeline implementations
    application_image_pipeline.rb   # Base pipeline with DSL reference
    product_image_pipeline.rb       # E-commerce product workflow
    content_moderation_pipeline.rb  # Content safety analysis
    marketing_asset_pipeline.rb     # Marketing image generation

  evals/            # Example agent evaluation suites
    support_router_eval.rb          # Quality checks for the support router
    schema_agent_eval.rb            # Quality checks for the schema agent

spec/
  evals/            # RSpec wrappers for eval suites
    support_router_eval_spec.rb     # Gated with RUN_EVAL=1
    datasets/
      support_router.yml            # YAML test dataset

config/
  initializers/
    ruby_llm_agents.rb      # Gem configuration
```

## Testing Generators

```bash
# Generate a new agent
bin/rails generate ruby_llm_agents:agent MyAgent query:required limit:10

# Generate an agent with options
bin/rails generate ruby_llm_agents:agent SearchIntent query:required --model=gpt-4o --temperature=0.7 --cache=1.hour

# Generate an image analyzer
bin/rails generate ruby_llm_agents:image_analyzer ProductAnalyzer --model=gpt-4o

# Generate a background remover
bin/rails generate ruby_llm_agents:background_remover ProductRemover --model=segment-anything

# Generate an image pipeline
bin/rails generate ruby_llm_agents:image_pipeline ProductWorkflow --steps generate,upscale,analyze

# Generate a workflow
bin/rails generate ruby_llm_agents:workflow Content --steps=research,draft,edit

# Run the upgrade generator (adds new columns to existing installations)
bin/rails generate ruby_llm_agents:upgrade

# Add multi-tenancy support
bin/rails generate ruby_llm_agents:multi_tenancy
```

## Example Usage (Rails Console)

```bash
bin/rails console
```

### Pipeline Workflow (Sequential Steps)

```ruby
# Process content through extract >> classify >> format steps
result = Workflows::ContentPipeline.call(text: "Your content here")
result.step(:extract).content    # { entities: [...], facts: [...], themes: [...] }
result.step(:classify).content   # { category: "...", confidence: 0.95, tags: [...] }
result.step(:format).content     # Formatted report
result.total_cost                # Total cost of all steps
result.duration_ms               # Wall-clock time
```

### Parallel Workflow (Concurrent Execution)

```ruby
# Analyze content from multiple perspectives concurrently
result = Workflows::ContentAnalyzer.call(text: "Your content here")
result.step(:sentiment).content  # { sentiment: "positive", score: 0.8 }
result.step(:keywords).content   # { keywords: [...], phrases: [...] }
result.step(:summary).content    # Summary text
result.total_cost                # Combined cost
result.duration_ms               # Wall-clock time (parallel steps overlap)
```

### Dispatch Workflow (Routing to Specialists)

```ruby
# Route customer messages to specialized agents based on classification
result = Workflows::SupportWorkflow.call(message: "I was charged twice")
result.step(:classify).route     # => :billing
result.step(:handler).content    # => BillingAgent's response
result.total_cost                # Cost of classify + handler
```

### Image Analyzers (Vision AI)

```ruby
# Analyze product images for e-commerce
result = ProductAnalyzer.call(image: "product.jpg")
result.caption       # "Blue leather handbag with gold hardware"
result.description   # Detailed product description
result.tags          # ["handbag", "leather", "blue", "luxury"]
result.colors        # [{ name: "navy blue", hex: "#1a237e", percentage: 45.2 }]

# Content moderation analysis
result = ContentAnalyzer.call(image: "user_upload.jpg")
result.safe?         # true if no moderation issues
result.caption       # Brief content description
result.tags          # Content tags for filtering

# Scene understanding
result = SceneAnalyzer.call(image: "vacation_photo.jpg")
result.caption       # "Beach scene at sunset"
result.description   # Location, time of day, mood, etc.
```

### Background Removers (Image Processing)

```ruby
# Remove background from product photos
result = ProductBackgroundRemover.call(image: "product.jpg")
result.url           # URL to transparent PNG
result.has_alpha?    # true
result.save("product_transparent.png")

# Portrait extraction with fine detail
result = PortraitBackgroundRemover.call(image: "headshot.jpg")
result.save("portrait_transparent.png")
if result.mask?
  result.save_mask("portrait_mask.png")
end

# Fast simple removal with caching
result = SimpleBackgroundRemover.call(image: "logo.png")
result.to_blob       # Binary PNG data

# Attach to ActiveStorage
product.transparent_image.attach(
  io: StringIO.new(result.to_blob),
  filename: "transparent.png",
  content_type: "image/png"
)
```

### Image Pipelines (Multi-Step Workflows)

```ruby
# Complete product image workflow
result = ProductImagePipeline.call(
  prompt: "Professional photo of wireless headphones",
  high_quality: true,
  transparent: true
)
result.success?         # true if all steps succeeded
result.final_image      # Final processed image URL
result.total_cost       # Combined cost of all steps
result.step_count       # Number of steps executed

# Access individual step results
result.step(:generate)  # ImageGenerationResult
result.step(:upscale)   # ImageUpscaleResult (if high_quality: true)
result.step(:analyze)   # ImageAnalysisResult
result.analysis         # Shortcut to analyzer result

# Content moderation pipeline
result = ContentModerationPipeline.call(image: uploaded_file.path)
if result.analysis.safe?
  save_to_storage(result.final_image)
else
  queue_for_moderation(result)
end

# Marketing asset pipeline with caching
result = MarketingAssetPipeline.call(
  prompt: "Modern tech startup team collaboration",
  tenant: current_organization  # Track costs per organization
)
result.save("marketing_hero.png")

# Save all intermediate images
result.save_all("./output", prefix: "product")
```

### Agent Evaluation

Score agent quality with test datasets. Eval suites live in `app/agents/evals/`.

```ruby
# Run the full SupportRouter eval
run = Evals::SupportRouterEval.run!
puts run.summary
# Routers::SupportRouter eval: 12/12 passed (score: 1.0)

# Run a subset of cases
run = Evals::SupportRouterEval.run!(only: ["billing: double charge", "billing: refund request"])

# Run SchemaAgent eval with custom scorers
run = Evals::SchemaAgentEval.run!
```

Use the YAML dataset for a data-driven approach:

```ruby
# Load test cases from spec/evals/datasets/support_router.yml
class YamlEval < RubyLLM::Agents::Eval::EvalSuite
  agent Routers::SupportRouter
  dataset "spec/evals/datasets/support_router.yml"
end

run = YamlEval.run!
```

Gate evals in CI with an environment variable:

```bash
RUN_EVAL=1 bundle exec rspec spec/evals/
```

## Relationship to Parent Gem

This example app references the parent gem via `gem "ruby_llm-agents", path: ".."` in the Gemfile.
Any changes you make to the gem will be reflected here after restarting the Rails server.

## Notes

- This app uses SQLite for simplicity
- The `spec/dummy` app in the parent gem is separate and used for RSpec tests
- Configuration is in `config/initializers/ruby_llm_agents.rb`
