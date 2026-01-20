# Image Generation

Generate images from text prompts with templates, content policy, and cost tracking.

## Overview

The `ImageGenerator` base class provides a DSL for creating image generators with:
- Built-in execution tracking and cost monitoring
- Budget controls (image generation counts toward limits)
- Multi-tenancy support
- Content policy enforcement
- Prompt templates for consistent styling
- Caching for repeated prompts

## Quick Start

### Generate an ImageGenerator

```bash
rails generate ruby_llm_agents:image_generator Logo
```

This creates `app/image_generators/logo_generator.rb`:

```ruby
class LogoGenerator < ApplicationImageGenerator
  model "gpt-image-1"
  size "1024x1024"
  quality "standard"
  style "vivid"
end
```

### Basic Usage

```ruby
# Generate a single image
result = LogoGenerator.call(prompt: "Minimalist tech company logo")
result.url          # "https://..."
result.total_cost   # 0.04
result.success?     # true

# Save to file
result.save("logo.png")

# Generate multiple images
result = LogoGenerator.call(prompt: "App icon variations", count: 4)
result.urls         # ["https://...", ...]
result.count        # 4
result.save_all("./icons")
```

## Configuration DSL

### Model Selection

```ruby
class ProductImageGenerator < ApplicationImageGenerator
  model "gpt-image-1"    # OpenAI GPT Image 1
  # or
  model "dall-e-3"       # OpenAI DALL-E 3
  # or
  model "flux-pro"       # Flux Pro
end
```

### Size and Quality

```ruby
class HeroImageGenerator < ApplicationImageGenerator
  model "gpt-image-1"
  size "1792x1024"       # Wide format
  quality "hd"           # High definition
  style "vivid"          # Vivid or natural
end
```

Available sizes depend on the model:
- `"1024x1024"` - Square (default)
- `"1792x1024"` - Wide landscape
- `"1024x1792"` - Tall portrait
- `"512x512"` - Small

### Caching

Same prompt with same settings always produces similar results, so caching can be effective:

```ruby
class CachedGenerator < ApplicationImageGenerator
  model "gpt-image-1"
  cache_for 1.day
end
```

### Version Control

Bump version to invalidate cache when changing templates:

```ruby
class StyledGenerator < ApplicationImageGenerator
  model "gpt-image-1"
  version "2.0"
  cache_for 1.week
end
```

### Description

Add a description for documentation and dashboard display:

```ruby
class ProductPhotoGenerator < ApplicationImageGenerator
  model "gpt-image-1"
  description "Generates professional product photography"
end
```

## ImageGenerationResult

The result object provides access to images and metadata:

```ruby
result = MyGenerator.call(prompt: "A sunset over mountains")

# Images
result.image            # First image object
result.images           # Array of all images
result.url              # First image URL
result.urls             # All image URLs
result.data             # First image base64 data (if available)
result.datas            # All base64 data

# Status
result.success?         # true if generation succeeded
result.error?           # true if failed
result.single?          # true if single image
result.batch?           # true if multiple images
result.count            # Number of images

# Metadata
result.model_id         # Model used
result.size             # Image size
result.quality          # Quality setting
result.style            # Style setting
result.revised_prompt   # Model-modified prompt (if any)
result.revised_prompts  # All revised prompts

# Cost and Timing
result.total_cost       # Cost in USD
result.duration_ms      # Generation time
result.started_at       # Start time
result.completed_at     # End time
result.input_tokens     # Approximate prompt tokens

# Errors
result.error_class      # Error class name (if failed)
result.error_message    # Error message (if failed)
```

### Saving Images

```ruby
# Save single image
result.save("output.png")

# Save all images to directory
result.save_all("./outputs", prefix: "generated")
# Creates: generated_1.png, generated_2.png, etc.

# Get binary data
blob = result.to_blob
blobs = result.blobs
```

## Content Policy

Validate prompts before generation to prevent inappropriate content.

### Policy Levels

```ruby
class SafeGenerator < ApplicationImageGenerator
  model "gpt-image-1"
  content_policy :strict    # Blocks violence, nudity, hate, weapons, drugs
end

class ModerateGenerator < ApplicationImageGenerator
  model "gpt-image-1"
  content_policy :moderate  # Blocks explicit content, gore, hate speech
end

class StandardGenerator < ApplicationImageGenerator
  model "gpt-image-1"
  content_policy :standard  # Relies on model's built-in filters (default)
end

class UnfilteredGenerator < ApplicationImageGenerator
  model "gpt-image-1"
  content_policy :none      # No validation
end
```

### Policy Level Details

| Level | Blocks |
|-------|--------|
| `:strict` | Violence, nudity, hate, weapons, drugs |
| `:moderate` | Explicit content, gore, hate speech |
| `:standard` | No blocking (uses model's filters) |
| `:none` | No validation |

### Manual Validation

```ruby
# Check if prompt is valid
ImageGenerator::ContentPolicy.valid?("A beautiful sunset", :strict)
# => true

# Validate (raises on violation)
ImageGenerator::ContentPolicy.validate!("Violent scene", :strict)
# => raises ContentPolicyViolation
```

## Prompt Templates

Define reusable templates for consistent styling.

### Custom Templates

```ruby
class ProductPhotoGenerator < ApplicationImageGenerator
  model "gpt-image-1"
  template "Professional product photography of {prompt}, " \
           "white background, studio lighting, 8k resolution"
end

result = ProductPhotoGenerator.call(prompt: "a red sneaker")
# Actual prompt: "Professional product photography of a red sneaker, ..."
```

### Built-in Presets

```ruby
# Get a preset template
template = ImageGenerator::Templates.preset(:product)
# => "Professional product photography of {prompt}, white background..."

# Apply a preset
prompt = ImageGenerator::Templates.apply_preset(:portrait, "a CEO")
# => "Professional portrait of a CEO, soft lighting..."

# List all presets
ImageGenerator::Templates.preset_names
# => [:product, :portrait, :landscape, :watercolor, :oil_painting, ...]
```

### Available Presets

**Photography:**
- `:product` - Professional product photography
- `:portrait` - Studio portrait with soft lighting
- `:landscape` - Dramatic landscape photography

**Artistic:**
- `:watercolor` - Watercolor painting style
- `:oil_painting` - Classical oil painting
- `:digital_art` - Modern digital art
- `:anime` - Anime/Studio Ghibli style

**Technical:**
- `:isometric` - 3D isometric render
- `:blueprint` - Technical blueprint
- `:wireframe` - 3D wireframe visualization

**Design:**
- `:icon` - App icon design
- `:logo` - Minimalist logo design
- `:ui_mockup` - Modern UI mockup

## Multiple Images

Generate multiple images in a single call:

```ruby
result = LogoGenerator.call(prompt: "Tech startup logo", count: 4)

result.count   # => 4
result.urls    # => ["https://...", "https://...", ...]

# Iterate over images
result.images.each_with_index do |image, idx|
  image.save("logo_#{idx + 1}.png")
end

# Save all at once
result.save_all("./logos")
```

## Provider-Specific Options

Some options are specific to certain providers:

```ruby
class FluxGenerator < ApplicationImageGenerator
  model "flux-pro"

  # Provider-specific options
  negative_prompt "blurry, low quality, distorted"
  seed 12345                    # Reproducible generation
  guidance_scale 7.5            # CFG scale (1.0-20.0)
  steps 50                      # Inference steps
end
```

## ActiveStorage Integration

Attach generated images directly to Rails models:

```ruby
class Product < ApplicationRecord
  has_one_attached :hero_image
  has_many_attached :gallery_images
end

class ProductImageGenerator < ApplicationImageGenerator
  include RubyLLM::Agents::ImageGenerator::ActiveStorageSupport

  model "gpt-image-1"
  size "1024x1024"
end

# Generate and attach a single image
product = Product.find(1)
result = ProductImageGenerator.generate_and_attach(
  prompt: "Professional product photo of a red sneaker",
  record: product,
  attachment_name: :hero_image
)

# Generate and attach multiple images
result = ProductImageGenerator.generate_and_attach_multiple(
  prompt: "Product gallery shots",
  record: product,
  attachment_name: :gallery_images,
  count: 4
)
```

## Runtime Overrides

Override class settings at call time:

```ruby
# Override model
result = LogoGenerator.call(
  prompt: "A logo",
  model: "dall-e-3"
)

# Override size and quality
result = LogoGenerator.call(
  prompt: "A logo",
  size: "1792x1024",
  quality: "hd"
)

# With tenant for multi-tenancy
result = LogoGenerator.call(
  prompt: "A logo",
  tenant: current_organization
)

# Skip cache
result = LogoGenerator.call(
  prompt: "A logo",
  skip_cache: true
)
```

## Execution Tracking

Image generation executions are tracked in the `ruby_llm_agents_executions` table:

```ruby
# View image generation executions
RubyLLM::Agents::Execution
  .where(execution_type: 'image_generation')
  .sum(:total_cost)

# Per-generator stats
RubyLLM::Agents::Execution
  .where(agent_type: 'LogoGenerator')
  .group(:model_id)
  .count
```

## Budget Controls

Image generation costs count toward tenant and global budgets:

```ruby
RubyLLM::Agents.configure do |config|
  config.budgets = {
    global_daily: 25.0,      # Includes image generation
    global_monthly: 500.0,
    enforcement: :hard
  }
end
```

## Multi-Tenancy

Full multi-tenancy support:

```ruby
# Using resolver
result = LogoGenerator.call(prompt: "A logo")
# Automatically uses Current.tenant if configured

# Explicit tenant
result = LogoGenerator.call(
  prompt: "A logo",
  tenant: "acme_corp"
)

# Tenant with budget limits
result = LogoGenerator.call(
  prompt: "A logo",
  tenant: {
    id: "acme_corp",
    daily_limit: 50.0,
    enforcement: :hard
  }
)
```

## Global Configuration

```ruby
RubyLLM::Agents.configure do |config|
  # Default image model
  config.default_image_model = "gpt-image-1"

  # Default settings
  config.default_image_size = "1024x1024"
  config.default_image_quality = "standard"
  config.default_image_style = "vivid"

  # Maximum prompt length
  config.max_image_prompt_length = 4000

  # Enable/disable tracking
  config.track_image_generation = true

  # Default cost for unknown models
  config.default_image_cost = 0.04

  # Model aliases
  config.image_model_aliases = {
    dalle: "dall-e-3",
    gpt_image: "gpt-image-1"
  }

  # Custom pricing overrides
  config.image_model_pricing = {
    "custom-model" => 0.05,
    "another-model" => {
      standard: 0.03,
      hd: 0.06
    }
  }
end
```

## Supported Models

Pricing is dynamically fetched from LiteLLM and falls back to these estimates:

| Provider | Model | Price per Image | Notes |
|----------|-------|-----------------|-------|
| OpenAI | `gpt-image-1` | $0.04-0.12 | Varies by size/quality |
| OpenAI | `dall-e-3` | $0.04-0.12 | Varies by size/quality |
| OpenAI | `dall-e-2` | $0.016-0.02 | Legacy, smaller sizes |
| Black Forest | `flux-pro` | $0.05 | High quality |
| Black Forest | `flux-dev` | $0.025 | Development model |
| Black Forest | `flux-schnell` | $0.003 | Fast, budget option |
| Stability | `sdxl` | $0.04 | Stable Diffusion XL |
| Stability | `stable-diffusion-3.5` | $0.03 | Latest SD version |
| Google | `imagen-3` | $0.02 | Google's image model |
| Ideogram | `ideogram-2` | $0.04 | Text-in-image specialist |

## Cost Considerations

Image generation can be expensive at scale:

| Model | Standard | HD | Large HD |
|-------|----------|----|---------:|
| gpt-image-1 / dall-e-3 | $0.04 | $0.08 | $0.12 |
| flux-pro | $0.05 | - | - |
| flux-schnell | $0.003 | - | - |

**Tips:**
- Use caching for repeated prompts
- Consider `flux-schnell` for drafts/previews
- Use smaller sizes during development
- Monitor costs in the dashboard
- Set budget limits to prevent overruns

## Examples

### Product Image Generator

```ruby
class ProductImageGenerator < ApplicationImageGenerator
  model "gpt-image-1"
  size "1024x1024"
  quality "hd"
  content_policy :strict

  template "Professional product photography of {prompt}, " \
           "white background, soft studio lighting, commercial quality, " \
           "high resolution, clean and minimalist"
end

result = ProductImageGenerator.call(prompt: "a wireless mouse")
result.save("product_photo.png")
```

### Logo Generator with Variations

```ruby
class LogoGenerator < ApplicationImageGenerator
  model "gpt-image-1"
  size "1024x1024"
  quality "hd"
  style "vivid"
  content_policy :strict

  template "Minimalist logo design for {prompt}, " \
           "clean lines, professional, vector style, " \
           "suitable for business use, modern aesthetic"
end

# Generate 4 variations
result = LogoGenerator.call(
  prompt: "a tech startup called 'Nexus AI'",
  count: 4
)

result.save_all("./logo_options")
puts "Generated #{result.count} logos for $#{result.total_cost}"
```

### Avatar Generator with ActiveStorage

```ruby
class AvatarGenerator < ApplicationImageGenerator
  include RubyLLM::Agents::ImageGenerator::ActiveStorageSupport

  model "flux-schnell"  # Fast and cheap for avatars
  size "512x512"

  template "Digital avatar portrait of {prompt}, " \
           "friendly expression, vibrant colors, " \
           "suitable for profile picture"
end

# In a controller
def generate_avatar
  result = AvatarGenerator.generate_and_attach(
    prompt: params[:description],
    record: current_user,
    attachment_name: :avatar
  )

  if result.success?
    redirect_to profile_path, notice: "Avatar generated!"
  else
    redirect_to profile_path, alert: result.error_message
  end
end
```
