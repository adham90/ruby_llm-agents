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
    extractor_agent.rb      # Pipeline: extraction step
    classifier_agent.rb     # Pipeline: classification step
    formatter_agent.rb      # Pipeline: formatting step
    sentiment_agent.rb      # Parallel: sentiment analysis
    keyword_agent.rb        # Parallel: keyword extraction
    summary_agent.rb        # Parallel: summarization
    billing_agent.rb        # Router: billing support
    technical_agent.rb      # Router: technical support
    general_agent.rb        # Router: general support

  workflows/        # Example workflow implementations
    content_pipeline.rb     # Sequential pipeline workflow
    content_analyzer.rb     # Parallel execution workflow
    support_router.rb       # Conditional routing workflow

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
# Process content through extract -> classify -> format steps
result = ContentPipeline.call(text: "Your content here")
result.steps[:extract].content   # Extracted data
result.steps[:classify].content  # Classification result
result.total_cost                # Total cost of all steps
```

### Parallel Workflow (Concurrent Execution)

```ruby
# Analyze content from multiple perspectives concurrently
result = ContentAnalyzer.call(text: "Your content here")
result.branches[:sentiment].content  # Sentiment analysis
result.branches[:keywords].content   # Keyword extraction
result.branches[:summary].content    # Summary
result.total_cost                    # Combined cost
```

### Router Workflow (Conditional Dispatch)

```ruby
# Route customer messages to specialized agents based on intent
result = SupportRouter.call(message: "I was charged twice")
result.routed_to         # :billing, :technical, or :default
result.classification    # Classification details
result.content           # Response from routed agent
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

## Relationship to Parent Gem

This example app references the parent gem via `gem "ruby_llm-agents", path: ".."` in the Gemfile.
Any changes you make to the gem will be reflected here after restarting the Rails server.

## Notes

- This app uses SQLite for simplicity
- The `spec/dummy` app in the parent gem is separate and used for RSpec tests
- Configuration is in `config/initializers/ruby_llm_agents.rb`
