# Image Operations

Generate, analyze, edit, and transform images with templates, content policy, and cost tracking.

This guide covers all image-related capabilities:
- **Image Generation** - Create images from text prompts
- **Image Analysis** - Extract captions, tags, objects, and colors from images
- **Background Removal** - Extract subjects from images
- **Image Pipelines** - Chain multiple operations into automated workflows
- **Image Variations** - Create variations of existing images
- **Image Editing** - Modify images with text instructions
- **Image Transformation** - Apply style transfers and transformations
- **Image Upscaling** - Enhance image resolution

---

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

---

# Image Analysis

Extract captions, tags, objects, colors, and text from images using vision models.

## Overview

The `ImageAnalyzer` base class provides a DSL for creating image analyzers with:
- Caption generation and detailed descriptions
- Tag extraction for image categorization
- Object detection with confidence levels
- Color extraction with percentages
- OCR text extraction
- Built-in execution tracking and cost monitoring
- Multi-tenancy support
- Caching for repeated analyses

## Quick Start

### Generate an ImageAnalyzer

```bash
rails generate ruby_llm_agents:image_analyzer Product
```

This creates `app/image_analyzers/product_analyzer.rb`:

```ruby
class ProductAnalyzer < ApplicationImageAnalyzer
  model "gpt-4o"
  analysis_type :detailed
end
```

### Basic Usage

```ruby
# Analyze an image
result = ProductAnalyzer.call(image: "product.jpg")
result.caption        # "A red sneaker on white background"
result.description    # Detailed description
result.tags           # ["sneaker", "red", "footwear", "product"]
result.success?       # true

# Analyze from URL
result = ProductAnalyzer.call(image: "https://example.com/image.jpg")

# With specific analysis types
result = ProductAnalyzer.call(image: "photo.jpg", analysis_type: :all)
result.objects        # [{ name: "shoe", confidence: "high" }]
result.colors         # [{ hex: "#FF0000", percentage: 30 }]
```

## Configuration DSL

### Model Selection

```ruby
class ProductAnalyzer < ApplicationImageAnalyzer
  model "gpt-4o"          # OpenAI GPT-4 Vision
  # or
  model "claude-3-opus"   # Anthropic Claude Vision
  # or
  model "gemini-pro"      # Google Gemini Vision
end
```

### Analysis Types

```ruby
class DetailedAnalyzer < ApplicationImageAnalyzer
  model "gpt-4o"
  analysis_type :detailed    # Caption + detailed description
end

class TaggingAnalyzer < ApplicationImageAnalyzer
  model "gpt-4o"
  analysis_type :tags        # Tags only
  max_tags 20                # Maximum number of tags
end

class FullAnalyzer < ApplicationImageAnalyzer
  model "gpt-4o"
  analysis_type :all         # Everything: caption, description, tags, objects, colors
  extract_colors true        # Extract dominant colors
  detect_objects true        # Detect objects with locations
  extract_text true          # OCR text extraction
end
```

Available analysis types:
- `:caption` - Short caption only
- `:detailed` - Caption + description (default)
- `:tags` - Tags/keywords only
- `:objects` - Object detection with confidence
- `:colors` - Color palette extraction
- `:all` - All analysis types

### Custom Prompts

```ruby
class EcommerceAnalyzer < ApplicationImageAnalyzer
  model "gpt-4o"
  custom_prompt "Describe this product for an e-commerce listing. " \
                "Include material, color, style, and key features."
end
```

### Caching

```ruby
class CachedAnalyzer < ApplicationImageAnalyzer
  model "gpt-4o"
  cache_for 7.days       # Cache results for repeated images
end
```

## ImageAnalysisResult

The result object provides access to analysis data:

```ruby
result = MyAnalyzer.call(image: "photo.jpg")

# Content
result.caption           # Short caption
result.description       # Detailed description
result.tags              # Array of tags
result.tag_symbols       # Tags as symbols [:sunset, :mountains]
result.objects           # Detected objects with confidence
result.colors            # Extracted colors
result.text              # OCR extracted text

# Queries
result.caption?          # true if caption present
result.tags?             # true if tags present
result.objects?          # true if objects detected
result.colors?           # true if colors extracted
result.has_tag?("car")   # Check for specific tag
result.has_object?("person")  # Check for object

# Colors
result.dominant_color    # { hex: "#FF0000", percentage: 30 }

# Objects with filtering
result.high_confidence_objects
result.objects_with_confidence("high")

# Status
result.success?          # true if analysis succeeded
result.error?            # true if failed

# Metadata
result.model_id          # Model used
result.analysis_type     # Type of analysis
result.duration_ms       # Processing time
result.total_cost        # Cost in USD
```

## Examples

### Product Catalog Analyzer

```ruby
class ProductCatalogAnalyzer < ApplicationImageAnalyzer
  model "gpt-4o"
  analysis_type :all
  extract_colors true
  detect_objects true
  max_tags 15

  custom_prompt "Analyze this product image for e-commerce. " \
                "Identify the product type, brand if visible, " \
                "colors, materials, and key features."
end

result = ProductCatalogAnalyzer.call(image: "product.jpg")

# Use for categorization
category = determine_category(result.tags)

# Extract primary color for filtering
primary_color = result.dominant_color[:name]

# Build search keywords
keywords = result.tags.join(", ")
```

### Content Moderation Analyzer

```ruby
class ContentModerationAnalyzer < ApplicationImageAnalyzer
  model "gpt-4o"
  analysis_type :detailed
  detect_objects true

  custom_prompt "Analyze this image for content moderation. " \
                "Identify any inappropriate content, violence, " \
                "nudity, or concerning elements. Be specific."
end

result = ContentModerationAnalyzer.call(image: uploaded_file)

if result.has_object?("weapon") || result.has_tag?("violence")
  flag_for_review(result)
end
```

---

# Background Removal

Extract subjects from images by removing backgrounds.

## Overview

The `BackgroundRemover` base class provides a DSL for creating background removers with:
- Subject extraction with alpha transparency
- Optional alpha matting for fine edges
- Edge refinement for clean cutouts
- Mask output for compositing
- Built-in execution tracking and cost monitoring
- Multi-tenancy support
- Caching for repeated operations

## Quick Start

### Generate a BackgroundRemover

```bash
rails generate ruby_llm_agents:background_remover Photo
```

This creates `app/background_removers/photo_background_remover.rb`:

```ruby
class PhotoBackgroundRemover < ApplicationBackgroundRemover
  model "rembg"
  output_format :png
end
```

### Basic Usage

```ruby
# Remove background
result = PhotoBackgroundRemover.call(image: "photo.jpg")
result.url              # URL of foreground image
result.has_alpha?       # true (PNG with transparency)
result.success?         # true

# Save the result
result.save("foreground.png")

# Get mask if available
if result.mask?
  result.save_mask("mask.png")
end
```

## Configuration DSL

### Model Selection

```ruby
class ProductRemover < ApplicationBackgroundRemover
  model "rembg"              # Fast, good for general use
  # or
  model "segment-anything"   # Better quality, slower
end
```

### Output Format

```ruby
class TransparentRemover < ApplicationBackgroundRemover
  model "rembg"
  output_format :png        # PNG with alpha (default)
end

class WebOptimizedRemover < ApplicationBackgroundRemover
  model "rembg"
  output_format :webp       # WebP with alpha
end
```

### Edge Refinement

```ruby
class HighQualityRemover < ApplicationBackgroundRemover
  model "segment-anything"
  output_format :png
  refine_edges true          # Smooth edge transitions
  alpha_matting true         # Fine edge detection
  foreground_threshold 0.6   # Foreground sensitivity (0.0-1.0)
  background_threshold 0.4   # Background sensitivity (0.0-1.0)
  erode_size 2               # Edge erosion for cleaner cuts
end
```

### Mask Output

```ruby
class MaskRemover < ApplicationBackgroundRemover
  model "rembg"
  return_mask true           # Also return the mask image
end

result = MaskRemover.call(image: "photo.jpg")
result.mask?                 # true
result.mask_url              # URL of mask image
result.save_mask("mask.png") # Save mask separately
```

### Caching

```ruby
class CachedRemover < ApplicationBackgroundRemover
  model "rembg"
  cache_for 30.days          # Cache results
end
```

## BackgroundRemovalResult

The result object provides access to extracted images:

```ruby
result = MyRemover.call(image: "photo.jpg")

# Foreground (subject)
result.foreground        # Foreground image object
result.url               # Foreground URL
result.data              # Base64 data (if available)
result.base64?           # true if base64 encoded

# Mask (optional)
result.mask?             # true if mask available
result.mask              # Mask image object
result.mask_url          # Mask URL
result.mask_data         # Mask base64 data

# Properties
result.has_alpha?        # true for PNG/WebP with transparency
result.output_format     # :png or :webp

# File operations
result.save("foreground.png")
result.save_mask("mask.png")
result.to_blob           # Binary foreground data
result.mask_blob         # Binary mask data

# Status
result.success?          # true if removal succeeded
result.error?            # true if failed

# Metadata
result.model_id          # Model used
result.alpha_matting     # Whether alpha matting was used
result.refine_edges      # Whether edge refinement was used
result.duration_ms       # Processing time
result.total_cost        # Cost in USD
```

## Examples

### Product Photo Background Remover

```ruby
class ProductPhotoRemover < ApplicationBackgroundRemover
  model "segment-anything"
  output_format :png
  refine_edges true
  alpha_matting true
  foreground_threshold 0.55

  description "Removes backgrounds from product photos"
end

# In a controller
def remove_background
  result = ProductPhotoRemover.call(image: params[:image])

  if result.success?
    # Attach to product using ActiveStorage
    @product.processed_image.attach(
      io: StringIO.new(result.to_blob),
      filename: "product_transparent.png",
      content_type: "image/png"
    )
    render json: { url: result.url }
  else
    render json: { error: result.error_message }, status: :unprocessable_entity
  end
end
```

### Portrait Background Remover with Compositing

```ruby
class PortraitRemover < ApplicationBackgroundRemover
  model "segment-anything"
  output_format :png
  alpha_matting true
  refine_edges true
  return_mask true

  description "Extracts portraits for compositing"
end

# Get subject and mask for compositing
result = PortraitRemover.call(image: "portrait.jpg")

if result.success?
  # Save foreground with transparency
  result.save("subject.png")

  # Save mask for further editing
  result.save_mask("subject_mask.png") if result.mask?

  # Use with image editing software or composite in Ruby
  composite_with_background(result.to_blob, "new_background.jpg")
end
```

---

# Image Variations

Generate variations of existing images while maintaining composition and style.

## Overview

The `ImageVariator` base class provides a DSL for creating image variators with:
- Variation generation from source images
- Controllable variation strength
- Multiple variation generation in a single call
- Built-in execution tracking and cost monitoring
- Multi-tenancy support
- Caching for repeated operations

## Quick Start

### Generate an ImageVariator

```bash
rails generate ruby_llm_agents:image_variator Logo
```

This creates `app/image_variators/logo_variator.rb`:

```ruby
class LogoVariator < ApplicationImageVariator
  model "gpt-image-1"
  size "1024x1024"
  variation_strength 0.5
end
```

### Basic Usage

```ruby
# Generate variations
result = LogoVariator.call(image: "logo.png", count: 4)
result.urls           # ["https://...", "https://...", ...]
result.count          # 4
result.success?       # true

# Save all variations
result.save_all("./logo_variations")
```

## Configuration DSL

### Model and Size

```ruby
class ProductVariator < ApplicationImageVariator
  model "gpt-image-1"
  size "1024x1024"
end
```

### Variation Strength

Control how different variations should be from the original:

```ruby
class SubtleVariator < ApplicationImageVariator
  model "gpt-image-1"
  variation_strength 0.2  # Subtle changes
end

class BoldVariator < ApplicationImageVariator
  model "gpt-image-1"
  variation_strength 0.8  # More dramatic changes
end
```

### Caching

```ruby
class CachedVariator < ApplicationImageVariator
  model "gpt-image-1"
  cache_for 1.day
end
```

## ImageVariationResult

```ruby
result = MyVariator.call(image: "source.png", count: 4)

# Images
result.images          # All variation image objects
result.urls            # All variation URLs
result.count           # Number of variations

# Status
result.success?        # true if generation succeeded
result.single?         # true if single variation
result.batch?          # true if multiple variations

# File operations
result.save("variation.png")    # Save first variation
result.save_all("./variations") # Save all variations

# Metadata
result.model_id        # Model used
result.total_cost      # Cost in USD
result.duration_ms     # Processing time
```

---

# Image Editing

Edit specific regions of images using masks (inpainting/outpainting).

## Overview

The `ImageEditor` base class provides a DSL for creating image editors with:
- Mask-based region editing (inpainting)
- Prompt-guided content generation
- Multiple edit generation
- Built-in execution tracking and cost monitoring
- Content policy enforcement
- Multi-tenancy support

## Quick Start

### Generate an ImageEditor

```bash
rails generate ruby_llm_agents:image_editor Product
```

This creates `app/image_editors/product_editor.rb`:

```ruby
class ProductEditor < ApplicationImageEditor
  model "gpt-image-1"
  size "1024x1024"
end
```

### Basic Usage

```ruby
# Edit an image region
result = ProductEditor.call(
  image: "product.png",
  mask: "mask.png",       # White areas will be edited
  prompt: "Replace background with beach scene"
)
result.url            # Edited image URL
result.success?       # true

# Generate multiple edit options
result = ProductEditor.call(
  image: "product.png",
  mask: "mask.png",
  prompt: "Add sunset sky",
  count: 3
)
result.urls           # ["https://...", ...]
```

## Configuration DSL

### Model and Size

```ruby
class BackgroundEditor < ApplicationImageEditor
  model "gpt-image-1"
  size "1024x1024"
end
```

### Content Policy

```ruby
class SafeEditor < ApplicationImageEditor
  model "gpt-image-1"
  content_policy :strict  # Validate edit prompts
end
```

### Caching

```ruby
class CachedEditor < ApplicationImageEditor
  model "gpt-image-1"
  cache_for 1.hour
end
```

## Mask Format

Masks should be:
- Same dimensions as the source image
- PNG format with alpha channel
- White (255) areas indicate regions to edit
- Black (0) areas indicate regions to preserve

## ImageEditResult

```ruby
result = MyEditor.call(image: "photo.png", mask: "mask.png", prompt: "...")

# Images
result.image           # Edited image object
result.images          # All edited images (if count > 1)
result.url             # First edited image URL
result.urls            # All edited image URLs

# Status
result.success?        # true if edit succeeded
result.error?          # true if failed

# File operations
result.save("edited.png")
result.save_all("./edits")

# Metadata
result.model_id        # Model used
result.total_cost      # Cost in USD
result.duration_ms     # Processing time
```

---

# Image Transformation

Apply style transfers and image-to-image transformations.

## Overview

The `ImageTransformer` base class provides a DSL for creating transformers with:
- Style transfer from images
- Prompt-guided transformations
- Controllable transformation strength
- Composition preservation
- Built-in execution tracking and cost monitoring
- Multi-tenancy support

## Quick Start

### Generate an ImageTransformer

```bash
rails generate ruby_llm_agents:image_transformer Anime
```

This creates `app/image_transformers/anime_transformer.rb`:

```ruby
class AnimeTransformer < ApplicationImageTransformer
  model "sdxl"
  strength 0.75
end
```

### Basic Usage

```ruby
# Transform an image
result = AnimeTransformer.call(
  image: "photo.jpg",
  prompt: "anime style portrait"
)
result.url            # Transformed image URL
result.success?       # true

# Override strength at runtime
result = AnimeTransformer.call(
  image: "photo.jpg",
  prompt: "anime style portrait",
  strength: 0.9       # More dramatic transformation
)
```

## Configuration DSL

### Model and Size

```ruby
class WatercolorTransformer < ApplicationImageTransformer
  model "sdxl"
  size "1024x1024"
end
```

### Transformation Strength

Control how much the image changes:

```ruby
class SubtleTransformer < ApplicationImageTransformer
  model "sdxl"
  strength 0.3        # Subtle style transfer
  preserve_composition true
end

class DramaticTransformer < ApplicationImageTransformer
  model "sdxl"
  strength 0.9        # Dramatic transformation
end
```

### Prompt Templates

```ruby
class OilPaintingTransformer < ApplicationImageTransformer
  model "sdxl"
  strength 0.8
  template "oil painting, classical style, museum quality, {prompt}"
end
```

### Advanced Options

```ruby
class PreciseTransformer < ApplicationImageTransformer
  model "sdxl"
  strength 0.75
  negative_prompt "blurry, low quality, distorted"
  guidance_scale 7.5  # CFG scale (1.0-20.0)
  steps 50            # Inference steps
end
```

### Caching

```ruby
class CachedTransformer < ApplicationImageTransformer
  model "sdxl"
  cache_for 1.day
end
```

## ImageTransformResult

```ruby
result = MyTransformer.call(image: "photo.jpg", prompt: "watercolor")

# Images
result.image           # Transformed image object
result.images          # All transformed images (if count > 1)
result.url             # First transformed image URL
result.urls            # All transformed image URLs

# Status
result.success?        # true if transformation succeeded
result.error?          # true if failed

# File operations
result.save("transformed.png")
result.save_all("./transforms")

# Metadata
result.model_id        # Model used
result.strength        # Transformation strength used
result.total_cost      # Cost in USD
result.duration_ms     # Processing time
```

## Examples

### Photo to Painting

```ruby
class ArtTransformer < ApplicationImageTransformer
  model "sdxl"
  strength 0.85
  template "masterpiece painting, {prompt}, detailed brushwork"
  negative_prompt "photo, realistic, modern"
end

result = ArtTransformer.call(
  image: "landscape.jpg",
  prompt: "impressionist landscape at sunset"
)
```

---

# Image Upscaling

Enhance image resolution using AI upscaling models.

## Overview

The `ImageUpscaler` base class provides a DSL for creating upscalers with:
- Resolution enhancement (2x, 4x, 8x)
- Optional face enhancement
- Noise reduction
- Built-in execution tracking and cost monitoring
- Multi-tenancy support
- Caching for repeated operations

## Quick Start

### Generate an ImageUpscaler

```bash
rails generate ruby_llm_agents:image_upscaler Photo
```

This creates `app/image_upscalers/photo_upscaler.rb`:

```ruby
class PhotoUpscaler < ApplicationImageUpscaler
  model "real-esrgan"
  scale 4
end
```

### Basic Usage

```ruby
# Upscale an image
result = PhotoUpscaler.call(image: "low_res.jpg")
result.url            # High resolution image URL
result.output_size    # "4096x4096" (if input was 1024x1024)
result.success?       # true

# Save the result
result.save("high_res.png")
```

## Configuration DSL

### Model Selection

```ruby
class PhotoUpscaler < ApplicationImageUpscaler
  model "real-esrgan"     # General purpose, good quality
  # or
  model "swinir"          # Better for natural images
end
```

### Scale Factor

```ruby
class SmallUpscaler < ApplicationImageUpscaler
  model "real-esrgan"
  scale 2                 # 2x upscale
end

class LargeUpscaler < ApplicationImageUpscaler
  model "real-esrgan"
  scale 8                 # 8x upscale (maximum)
end
```

### Face Enhancement

```ruby
class PortraitUpscaler < ApplicationImageUpscaler
  model "real-esrgan"
  scale 4
  face_enhance true       # Improve facial details
end
```

### Noise Reduction

```ruby
class DenoisingUpscaler < ApplicationImageUpscaler
  model "real-esrgan"
  scale 4
  denoise_strength 0.5    # Reduce noise (0.0-1.0)
end
```

### Caching

```ruby
class CachedUpscaler < ApplicationImageUpscaler
  model "real-esrgan"
  cache_for 7.days
end
```

## ImageUpscaleResult

```ruby
result = MyUpscaler.call(image: "photo.jpg")

# Image
result.image           # Upscaled image object
result.url             # Upscaled image URL
result.data            # Base64 data (if available)

# Dimensions
result.input_size      # Original size "1024x1024"
result.output_size     # Upscaled size "4096x4096"
result.scale_factor    # 4

# Status
result.success?        # true if upscaling succeeded
result.error?          # true if failed

# File operations
result.save("upscaled.png")
result.to_blob         # Binary image data

# Metadata
result.model_id        # Model used
result.face_enhance    # Whether face enhancement was used
result.total_cost      # Cost in USD
result.duration_ms     # Processing time
```

## Examples

### Product Photo Upscaler

```ruby
class ProductUpscaler < ApplicationImageUpscaler
  model "real-esrgan"
  scale 4

  description "Upscales product photos for e-commerce"
end

# In a controller
def upscale_image
  result = ProductUpscaler.call(image: params[:image])

  if result.success?
    @product.high_res_image.attach(
      io: StringIO.new(result.to_blob),
      filename: "product_hd.png",
      content_type: "image/png"
    )
    redirect_to @product, notice: "Image upscaled!"
  else
    redirect_to @product, alert: result.error_message
  end
end
```

### Portrait Upscaler with Face Enhancement

```ruby
class PortraitUpscaler < ApplicationImageUpscaler
  model "real-esrgan"
  scale 4
  face_enhance true
  denoise_strength 0.3

  description "Upscales portraits with face enhancement"
end

result = PortraitUpscaler.call(image: "headshot.jpg")
result.save("headshot_hd.png")
```

---

# Image Pipelines

Chain multiple image operations into automated workflows.

## Overview

The `ImagePipeline` base class provides a DSL for creating multi-step image workflows with:
- Sequential execution of image operations
- Conditional step execution
- Aggregated cost tracking
- Unified result access
- Before/after callbacks
- Caching for deterministic pipelines
- Multi-tenancy support

## Quick Start

### Generate an ImagePipeline

```bash
rails generate ruby_llm_agents:image_pipeline Product --steps generate,upscale,analyze
```

This creates `app/image_pipelines/product_pipeline.rb`:

```ruby
class ProductPipeline < ApplicationImagePipeline
  step :generate, generator: ProductGenerator
  step :upscale, upscaler: ProductUpscaler
  step :analyze, analyzer: ProductAnalyzer

  description "Product image processing pipeline"
  version "1.0"
end
```

### Basic Usage

```ruby
# Run the pipeline
result = ProductPipeline.call(prompt: "Professional laptop photo")
result.success?        # true if all steps succeeded
result.final_image     # Final processed image URL
result.total_cost      # Combined cost of all steps

# Access individual steps
result.step(:generate)  # ImageGenerationResult
result.step(:upscale)   # ImageUpscaleResult
result.analysis         # Shortcut to analyzer result

# Save the final image
result.save("output.png")
```

## Configuration DSL

### Defining Steps

```ruby
class MyPipeline < ApplicationImagePipeline
  # Generation step (text-to-image)
  step :generate, generator: ProductGenerator

  # Upscaling step
  step :upscale, upscaler: PhotoUpscaler, scale: 2

  # Transformation step (img2img)
  step :transform, transformer: StyleTransformer, strength: 0.7

  # Editing step (inpainting)
  step :edit, editor: PhotoEditor

  # Variation step
  step :vary, variator: ProductVariator

  # Analysis step (non-image output)
  step :analyze, analyzer: ContentAnalyzer

  # Background removal step
  step :remove_bg, remover: BackgroundRemover
end
```

### Step Types

| Type | Option Key | Input | Output |
|------|------------|-------|--------|
| Generator | `:generator` | Prompt | Image |
| Upscaler | `:upscaler` | Image | Image |
| Transformer | `:transformer` | Image + Prompt | Image |
| Editor | `:editor` | Image + Mask + Prompt | Image |
| Variator | `:variator` | Image | Image |
| Analyzer | `:analyzer` | Image | Analysis |
| Remover | `:remover` | Image | Image |

### Conditional Steps

Execute steps based on context:

```ruby
class SmartPipeline < ApplicationImagePipeline
  step :generate, generator: ProductGenerator

  # Only upscale if high_quality option is passed
  step :upscale, upscaler: PhotoUpscaler, if: ->(ctx) { ctx[:high_quality] }

  # Skip background removal if keep_background is true
  step :remove_bg, remover: BackgroundRemover, unless: ->(ctx) { ctx[:keep_background] }

  step :analyze, analyzer: ProductAnalyzer
end

# Usage with conditions
result = SmartPipeline.call(
  prompt: "Product photo",
  high_quality: true,      # Triggers upscale step
  keep_background: false   # Triggers remove_bg step
)
```

### Step Options

Pass options to individual steps:

```ruby
class CustomPipeline < ApplicationImagePipeline
  step :generate, generator: ProductGenerator, size: "1792x1024"
  step :upscale, upscaler: PhotoUpscaler, scale: 4
  step :transform, transformer: StyleTransformer, strength: 0.8
end
```

### Callbacks

Run code before or after the pipeline:

```ruby
class CallbackPipeline < ApplicationImagePipeline
  step :generate, generator: ProductGenerator
  step :upscale, upscaler: PhotoUpscaler

  # Before callbacks
  before_pipeline :validate_inputs
  before_pipeline { |ctx| ctx[:started_at] = Time.current }

  # After callbacks
  after_pipeline :log_completion
  after_pipeline { |result| notify_webhook(result) }

  private

  def validate_inputs
    raise ArgumentError, "Prompt required" unless context[:prompt]
  end

  def log_completion(result)
    Rails.logger.info("Pipeline #{self.class.name}: #{result.success?}")
  end

  def notify_webhook(result)
    WebhookService.notify(result.to_h)
  end
end
```

### Error Handling

```ruby
class ResilientPipeline < ApplicationImagePipeline
  step :generate, generator: ProductGenerator
  step :upscale, upscaler: PhotoUpscaler
  step :analyze, analyzer: ProductAnalyzer

  # Stop pipeline on first error (default)
  stop_on_error true

  # Or continue despite errors
  # stop_on_error false
end

result = ResilientPipeline.call(prompt: "Test")

if result.partial?
  # Some steps succeeded, some failed
  puts "Completed #{result.successful_step_count}/#{result.step_count} steps"
end
```

### Caching

```ruby
class CachedPipeline < ApplicationImagePipeline
  step :generate, generator: ProductGenerator
  step :upscale, upscaler: PhotoUpscaler

  cache_for 1.hour

  # Version bump invalidates cache
  version "2.0"
end
```

### Metadata

```ruby
class DocumentedPipeline < ApplicationImagePipeline
  step :generate, generator: ProductGenerator

  description "Generates professional product images"
  version "1.0"
end
```

## ImagePipelineResult

The result object provides access to all step results:

```ruby
result = MyPipeline.call(prompt: "Test")

# Status
result.success?              # true if all steps succeeded
result.error?                # true if any step failed
result.partial?              # true if some succeeded, some failed
result.completed?            # true if pipeline finished

# Steps
result.steps                 # Array of all step results
result.step(:generate)       # Get specific step result
result[:upscale]             # Alias for step()
result.step_names            # [:generate, :upscale, ...]
result.step_count            # Total step count
result.successful_step_count # Steps that succeeded
result.failed_step_count     # Steps that failed

# Images
result.final_image           # URL/data of last image-producing step
result.url                   # Final image URL
result.data                  # Final image base64 data
result.to_blob               # Final image binary data

# Shortcut accessors
result.generation            # Generator step result
result.upscale               # Upscaler step result
result.transform             # Transformer step result
result.analysis              # Analyzer step result
result.background_removal    # Remover step result

# Cost and timing
result.total_cost            # Combined cost of all steps
result.duration_ms           # Total pipeline duration
result.primary_model_id      # Model from first step

# File operations
result.save("output.png")           # Save final image
result.save_all("./dir", prefix: "step")  # Save all intermediate images

# Serialization
result.to_h                  # Hash representation
result.to_cache              # Cacheable format
```

## Examples

### E-commerce Product Pipeline

```ruby
class EcommercePipeline < ApplicationImagePipeline
  # Generate professional product photo
  step :generate, generator: ProductPhotoGenerator

  # Upscale for high resolution
  step :upscale, upscaler: PhotoUpscaler, scale: 2

  # Remove background for transparent cutout
  step :remove_bg, remover: ProductBackgroundRemover

  # Analyze for auto-tagging
  step :analyze, analyzer: ProductAnalyzer

  description "Complete e-commerce product image workflow"
  version "1.0"
end

result = EcommercePipeline.call(
  prompt: "Professional photo of wireless headphones",
  tenant: current_store
)

if result.success?
  product.hero_image.attach(
    io: StringIO.new(result.to_blob),
    filename: "product.png",
    content_type: "image/png"
  )

  product.update!(
    tags: result.analysis.tags,
    description: result.analysis.description
  )
end
```

### Content Moderation Pipeline

```ruby
class ModerationPipeline < ApplicationImagePipeline
  # Analyze uploaded content
  step :analyze, analyzer: ContentModerationAnalyzer

  description "Content safety analysis"
  version "1.0"

  after_pipeline :log_moderation_result

  private

  def log_moderation_result(result)
    if result.analysis&.success?
      Rails.logger.info(
        "[Moderation] safe=#{result.analysis.safe?}, " \
        "tags=#{result.analysis.tags.join(', ')}"
      )
    end
  end
end

result = ModerationPipeline.call(image: uploaded_file.path)

if result.analysis&.safe?
  save_to_storage(uploaded_file)
else
  queue_for_review(uploaded_file, result.analysis)
end
```

### Marketing Asset Pipeline

```ruby
class MarketingPipeline < ApplicationImagePipeline
  step :generate, generator: MarketingImageGenerator, size: "1792x1024"
  step :upscale, upscaler: PhotoUpscaler, scale: 2

  cache_for 1.day
  description "High-quality marketing asset generation"
  version "1.0"

  before_pipeline :validate_prompt

  private

  def validate_prompt
    prompt = context[:prompt]
    raise ArgumentError, "Prompt required" if prompt.blank?
    raise ArgumentError, "Prompt too short" if prompt.length < 10
  end
end

# Generate hero images for campaigns
result = MarketingPipeline.call(
  prompt: "Modern tech startup team collaborating in bright office",
  tenant: current_organization
)

campaign.hero_image.attach(
  io: StringIO.new(result.to_blob),
  filename: "hero.png"
)
```

### Conditional Quality Pipeline

```ruby
class QualityPipeline < ApplicationImagePipeline
  step :generate, generator: ProductGenerator

  # Premium tier gets upscaling
  step :upscale, upscaler: PhotoUpscaler, scale: 4,
       if: ->(ctx) { ctx[:tier] == :premium }

  # Enterprise tier gets background removal
  step :remove_bg, remover: BackgroundRemover,
       if: ->(ctx) { ctx[:tier] == :enterprise }

  # Everyone gets analysis
  step :analyze, analyzer: ProductAnalyzer
end

# Basic tier - just generate + analyze
result = QualityPipeline.call(prompt: "Product", tier: :basic)
result.step_count  # 2

# Premium tier - generate + upscale + analyze
result = QualityPipeline.call(prompt: "Product", tier: :premium)
result.step_count  # 3

# Enterprise tier - all steps
result = QualityPipeline.call(prompt: "Product", tier: :enterprise)
result.step_count  # 4
```

---

## Global Configuration (Image Operations)

```ruby
RubyLLM::Agents.configure do |config|
  # Image Generation
  config.default_image_model = "gpt-image-1"
  config.default_image_size = "1024x1024"
  config.track_image_generation = true

  # Image Analysis
  config.default_analyzer_model = "gpt-4o"
  config.default_analysis_type = :detailed
  config.default_analyzer_max_tags = 10

  # Background Removal
  config.default_background_remover_model = "rembg"
  config.default_background_output_format = :png
end
```
