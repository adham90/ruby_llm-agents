# Image Generation & Manipulation Support Plan

## Overview

Add comprehensive image capabilities to ruby_llm-agents through a family of image-focused classes:

- **ImageGenerator** - Text-to-image generation (core)
- **ImageEditor** - Inpainting and image editing
- **ImageTransformer** - Image-to-image style transfer
- **ImageUpscaler** - Resolution enhancement
- **ImageVariator** - Generate variations of existing images
- **ImageAnalyzer** - Image understanding and captioning
- **BackgroundRemover** - Subject extraction
- **ImagePipeline** - Chain multiple operations

This follows the established patterns from `Embedder` and `Moderator` - standalone classes with their own DSL, execution flow, and result wrappers.

---

## Supported Models

### Currently in RubyLLM

| Model | Provider | Type | Output | Notes |
|-------|----------|------|--------|-------|
| `gpt-image-1` (DALL-E 3) | OpenAI | Text-to-Image | URL | Best quality, supports size/quality/style |
| `imagen-3.0-generate-002` | Google | Text-to-Image | Base64 | Fast, good quality |

### Extended Model Support (via Replicate/Custom Endpoints)

| Model | Provider | Type | Strengths | Est. Cost |
|-------|----------|------|-----------|-----------|
| **FLUX.2 Pro** | Black Forest Labs | Text-to-Image | Best open-source, character consistency | $0.05/image |
| **FLUX.2 Dev** | Black Forest Labs | Text-to-Image | Fast, good quality | $0.025/image |
| **FLUX.2 Schnell** | Black Forest Labs | Text-to-Image | Ultra-fast (<1s) | $0.003/image |
| **Stable Diffusion 3.5** | Stability AI | Text-to-Image | Highly customizable, ControlNet | $0.03/image |
| **SDXL** | Stability AI | Text-to-Image | Mature, wide support | $0.002/image |
| **SDXL Lightning** | Stability AI | Text-to-Image | Fastest (<1s), 1024x1024 | $0.002/image |
| **Ideogram 2.0** | Ideogram | Text-to-Image | Best text rendering in images | $0.04/image |
| **Real-ESRGAN** | Various | Upscaling | 4x upscale, photo-realistic | $0.01/image |
| **GFPGAN** | Various | Face Restoration | Face enhancement | $0.01/image |
| **Segment Anything** | Meta | Segmentation | Background removal | $0.01/image |
| **BLIP-2** | Salesforce | Analysis | Image captioning | $0.001/image |

### Model Aliases (Convenience)

```ruby
RubyLLM::Agents.configure do |config|
  config.image_model_aliases = {
    fast: "flux-schnell",
    quality: "gpt-image-1",
    cheap: "sdxl",
    open_source: "flux-2-dev"
  }
end

# Usage
result = LogoGenerator.call(prompt: "...", model: :fast)
```

---

## RubyLLM API Reference

### Text-to-Image
```ruby
image = RubyLLM.paint("A photorealistic red panda coding Ruby")
image = RubyLLM.paint("prompt", model: "gpt-image-1", size: "1024x1024")

# Response object (RubyLLM::Image)
image.url            # URL (OpenAI models)
image.data           # Base64 string (Google models)
image.mime_type      # "image/png"
image.base64?        # true/false
image.revised_prompt # Model-revised prompt (if applicable)
image.model_id       # Model used
image.save("path")   # Save to file
image.to_blob        # Binary data for storage
```

### Image Editing (if supported by RubyLLM)
```ruby
# Inpainting - edit specific regions
edited = RubyLLM.edit_image(
  image: source_image,
  mask: mask_image,
  prompt: "Replace with a red car"
)

# Variations - generate similar images
variations = RubyLLM.create_variations(
  image: source_image,
  count: 4
)
```

---

## Class Hierarchy

```
RubyLLM::Agents::
├── ImageGenerator                    # Text-to-image (Phase 1)
│   ├── DSL
│   ├── Execution
│   ├── ContentPolicy
│   ├── Templates
│   └── ActiveStorageSupport
├── ImageEditor                       # Inpainting/editing (Phase 2)
│   ├── DSL
│   └── Execution
├── ImageTransformer                  # Style transfer / img2img (Phase 2)
│   ├── DSL
│   └── Execution
├── ImageUpscaler                     # Resolution enhancement (Phase 2)
│   ├── DSL
│   └── Execution
├── ImageVariator                     # Generate variations (Phase 2)
│   ├── DSL
│   └── Execution
├── ImageAnalyzer                     # Captioning/understanding (Phase 3)
│   ├── DSL
│   └── Execution
├── BackgroundRemover                 # Subject extraction (Phase 3)
│   ├── DSL
│   └── Execution
├── ImagePipeline                     # Chain operations (Phase 4)
│   ├── DSL
│   └── Execution
└── Results/
    ├── ImageGenerationResult
    ├── ImageEditResult
    ├── ImageTransformResult
    ├── ImageUpscaleResult
    ├── ImageVariationResult
    ├── ImageAnalysisResult
    └── BackgroundRemovalResult
```

---

## Phase 1: Core Image Generation

### API Design

#### Basic Usage

```ruby
class LogoGenerator < ApplicationImageGenerator
  model "gpt-image-1"
  size "1024x1024"
  quality "hd"
  style "vivid"

  description "Generates company logos"
end

# Generate an image
result = LogoGenerator.call(prompt: "A minimalist tech startup logo")
result.url           # => "https://..."
result.model_id      # => "gpt-image-1"
result.success?      # => true
```

#### Configuration Options

```ruby
class ProductImageGenerator < ApplicationImageGenerator
  model "gpt-image-1"
  size "1792x1024"        # Landscape
  quality "standard"       # or "hd"
  style "natural"          # or "vivid"

  # Caching (useful for deterministic prompts)
  cache_for 1.hour
  version "v1"

  # Safety
  content_policy :strict   # Reject potentially problematic prompts

  description "Generates product mockup images"
end
```

#### Runtime Overrides

```ruby
# Override at call time
result = LogoGenerator.call(
  prompt: "A modern fintech logo",
  model: "imagen-3.0-generate-002",
  size: "1024x1024",
  quality: "hd",
  tenant: current_organization
)
```

#### Batch Generation

```ruby
# Generate multiple images from same prompt (variations)
result = LogoGenerator.call(
  prompt: "A coffee shop logo",
  count: 4
)

result.urls          # => ["url1", "url2", "url3", "url4"]
result.count         # => 4
result.batch?        # => true
```

#### Multi-tenancy

```ruby
result = LogoGenerator.call(
  prompt: "Corporate logo",
  tenant: organization
)
# Budget checked against organization
# Execution tracked with tenant_id
```

---

### Implementation Tasks

#### Task 1: Create ImageGenerator Base Class

**File: `lib/ruby_llm/agents/image_generator.rb`**

```ruby
# frozen_string_literal: true

module RubyLLM
  module Agents
    class ImageGenerator
      extend ImageGenerator::DSL
      include ImageGenerator::Execution

      class << self
        def call(prompt:, **options)
          new(prompt: prompt, **options).call
        end

        def inherited(subclass)
          super
          subclass.instance_variable_set(:@model, @model)
          subclass.instance_variable_set(:@size, @size)
          subclass.instance_variable_set(:@quality, @quality)
          subclass.instance_variable_set(:@style, @style)
          subclass.instance_variable_set(:@version, @version)
          subclass.instance_variable_set(:@description, @description)
          subclass.instance_variable_set(:@cache_ttl, @cache_ttl)
          subclass.instance_variable_set(:@content_policy, @content_policy)
        end
      end

      attr_reader :prompt, :options, :tenant_id

      def initialize(prompt:, **options)
        @prompt = prompt
        @options = options
        @tenant_id = nil
      end

      def call
        execute
      end
    end
  end
end

require_relative "image_generator/dsl"
require_relative "image_generator/execution"
```

#### Task 2: Create DSL Module

**File: `lib/ruby_llm/agents/image_generator/dsl.rb`**

```ruby
# frozen_string_literal: true

module RubyLLM
  module Agents
    class ImageGenerator
      module DSL
        def model(value = nil)
          if value
            @model = value
          else
            @model || inherited_or_default(:model, config.default_image_model)
          end
        end

        def size(value = nil)
          if value
            @size = value
          else
            @size || inherited_or_default(:size, config.default_image_size)
          end
        end

        def quality(value = nil)
          if value
            @quality = value
          else
            @quality || inherited_or_default(:quality, config.default_image_quality)
          end
        end

        def style(value = nil)
          if value
            @style = value
          else
            @style || inherited_or_default(:style, config.default_image_style)
          end
        end

        def version(value = nil)
          if value
            @version = value
          else
            @version || inherited_or_default(:version, "v1")
          end
        end

        def description(value = nil)
          if value
            @description = value
          else
            @description || inherited_or_default(:description, nil)
          end
        end

        def cache_for(ttl)
          @cache_ttl = ttl
        end

        def cache_ttl
          @cache_ttl || inherited_or_default(:cache_ttl, nil)
        end

        def cache_enabled?
          !cache_ttl.nil?
        end

        def content_policy(level = nil)
          if level
            @content_policy = level
          else
            @content_policy || inherited_or_default(:content_policy, :standard)
          end
        end

        # Provider-specific options
        def negative_prompt(value = nil)
          if value
            @negative_prompt = value
          else
            @negative_prompt || inherited_or_default(:negative_prompt, nil)
          end
        end

        def seed(value = nil)
          if value
            @seed = value
          else
            @seed || inherited_or_default(:seed, nil)
          end
        end

        def guidance_scale(value = nil)
          if value
            @guidance_scale = value
          else
            @guidance_scale || inherited_or_default(:guidance_scale, nil)
          end
        end

        def steps(value = nil)
          if value
            @steps = value
          else
            @steps || inherited_or_default(:steps, nil)
          end
        end

        private

        def config
          RubyLLM::Agents.configuration
        end

        def inherited_or_default(attribute, default)
          if superclass.respond_to?(attribute)
            superclass.public_send(attribute)
          else
            default
          end
        end
      end
    end
  end
end
```

#### Task 3: Create Execution Module

**File: `lib/ruby_llm/agents/image_generator/execution.rb`**

```ruby
# frozen_string_literal: true

module RubyLLM
  module Agents
    class ImageGenerator
      module Execution
        def execute
          started_at = Time.current

          resolve_tenant_context!
          check_budget! if budget_tracking_enabled?
          validate_prompt!
          validate_content_policy!

          # Check cache for single image requests
          cached = check_cache if cache_enabled? && single_image_request?
          return cached if cached

          # Generate image(s)
          images = generate_images

          # Build result
          result = build_result(
            images: images,
            started_at: started_at,
            completed_at: Time.current
          )

          # Cache single image results
          write_cache(result) if cache_enabled? && single_image_request?

          # Track execution
          record_execution(result) if execution_tracking_enabled?

          result
        rescue StandardError => e
          record_failed_execution(e, started_at) if execution_tracking_enabled?
          build_error_result(e, started_at)
        end

        private

        def resolve_tenant_context!
          tenant = options[:tenant]
          return unless tenant

          @tenant_id = case tenant
                       when Hash then tenant[:id]
                       when Integer, String then tenant
                       else
                         tenant.try(:llm_tenant_id) || tenant.try(:id)
                       end
        end

        def check_budget!
          BudgetTracker.check!(
            agent_type: self.class.name,
            tenant_id: @tenant_id,
            execution_type: "image_generation"
          )
        end

        def validate_prompt!
          raise ArgumentError, "Prompt cannot be blank" if prompt.nil? || prompt.strip.empty?

          max_length = config.max_image_prompt_length || 4000
          if prompt.length > max_length
            raise ArgumentError, "Prompt exceeds maximum length of #{max_length} characters"
          end
        end

        def validate_content_policy!
          policy = self.class.content_policy
          return if policy == :none || policy == :standard

          ContentPolicy.validate!(prompt, policy)
        end

        def generate_images
          count = resolve_count
          model = resolve_model

          Array.new(count) do
            paint_options = build_paint_options
            RubyLLM.paint(apply_template(prompt), **paint_options)
          end
        end

        def build_paint_options
          opts = {
            model: resolve_model,
            size: resolve_size
          }

          # Add optional parameters if set
          opts[:quality] = resolve_quality if resolve_quality
          opts[:style] = resolve_style if resolve_style
          opts[:negative_prompt] = resolve_negative_prompt if resolve_negative_prompt
          opts[:seed] = resolve_seed if resolve_seed
          opts[:guidance_scale] = resolve_guidance_scale if resolve_guidance_scale
          opts[:steps] = resolve_steps if resolve_steps
          opts[:assume_model_exists] = true if options[:assume_model_exists]

          opts
        end

        def apply_template(text)
          template = self.class.try(:template_string)
          return text unless template

          template.gsub("{prompt}", text)
        end

        def build_result(images:, started_at:, completed_at:)
          ImageGenerationResult.new(
            images: images,
            prompt: prompt,
            model_id: resolve_model,
            size: resolve_size,
            quality: resolve_quality,
            style: resolve_style,
            started_at: started_at,
            completed_at: completed_at,
            tenant_id: @tenant_id,
            generator_class: self.class.name
          )
        end

        def build_error_result(error, started_at)
          ImageGenerationResult.new(
            images: [],
            prompt: prompt,
            model_id: resolve_model,
            size: resolve_size,
            quality: resolve_quality,
            style: resolve_style,
            started_at: started_at,
            completed_at: Time.current,
            tenant_id: @tenant_id,
            generator_class: self.class.name,
            error_class: error.class.name,
            error_message: error.message
          )
        end

        # Resolution methods (runtime options override class config)
        def resolve_model
          model = options[:model] || self.class.model
          # Handle aliases
          config.image_model_aliases&.dig(model.to_sym) || model
        end

        def resolve_size
          options[:size] || self.class.size
        end

        def resolve_quality
          options[:quality] || self.class.quality
        end

        def resolve_style
          options[:style] || self.class.style
        end

        def resolve_negative_prompt
          options[:negative_prompt] || self.class.negative_prompt
        end

        def resolve_seed
          options[:seed] || self.class.seed
        end

        def resolve_guidance_scale
          options[:guidance_scale] || self.class.guidance_scale
        end

        def resolve_steps
          options[:steps] || self.class.steps
        end

        def resolve_count
          options[:count] || 1
        end

        def single_image_request?
          resolve_count == 1
        end

        # Caching
        def cache_enabled?
          self.class.cache_enabled? && !options[:skip_cache]
        end

        def cache_key
          [
            "ruby_llm_agents",
            "image_generator",
            self.class.name,
            self.class.version,
            resolve_model,
            resolve_size,
            resolve_quality,
            resolve_style,
            Digest::SHA256.hexdigest(prompt)
          ].join(":")
        end

        def check_cache
          return nil unless defined?(Rails) && Rails.cache

          cached_data = Rails.cache.read(cache_key)
          return nil unless cached_data

          ImageGenerationResult.from_cache(cached_data)
        end

        def write_cache(result)
          return unless defined?(Rails) && Rails.cache
          return unless result.success?

          Rails.cache.write(cache_key, result.to_cache, expires_in: self.class.cache_ttl)
        end

        # Execution tracking
        def execution_tracking_enabled?
          config.track_image_generation
        end

        def record_execution(result)
          return unless defined?(Execution)

          execution_data = {
            agent_type: self.class.name,
            tenant_id: @tenant_id,
            execution_type: "image_generation",
            model_id: result.model_id,
            input_tokens: result.input_tokens,
            output_tokens: 0,
            total_cost: result.total_cost,
            duration_ms: result.duration_ms,
            metadata: {
              prompt_length: prompt.length,
              size: result.size,
              quality: result.quality,
              count: result.count
            }
          }

          if config.async_execution_logging && defined?(ExecutionLoggerJob)
            ExecutionLoggerJob.perform_later(execution_data)
          else
            Execution.create!(execution_data)
          end
        end

        def record_failed_execution(error, started_at)
          return unless defined?(Execution)

          Execution.create!(
            agent_type: self.class.name,
            tenant_id: @tenant_id,
            execution_type: "image_generation",
            model_id: resolve_model,
            duration_ms: ((Time.current - started_at) * 1000).round,
            error_class: error.class.name,
            error_message: error.message,
            metadata: { prompt_length: prompt&.length }
          )
        end

        def budget_tracking_enabled?
          config.budget_tracking_enabled && defined?(BudgetTracker)
        end

        def config
          RubyLLM::Agents.configuration
        end
      end
    end
  end
end
```

#### Task 4: Create Result Class

**File: `lib/ruby_llm/agents/image_generation_result.rb`**

```ruby
# frozen_string_literal: true

module RubyLLM
  module Agents
    class ImageGenerationResult
      attr_reader :images, :prompt, :model_id, :size, :quality, :style,
                  :started_at, :completed_at, :tenant_id, :generator_class,
                  :error_class, :error_message

      def initialize(images:, prompt:, model_id:, size:, quality:, style:,
                     started_at:, completed_at:, tenant_id:, generator_class:,
                     error_class: nil, error_message: nil)
        @images = images
        @prompt = prompt
        @model_id = model_id
        @size = size
        @quality = quality
        @style = style
        @started_at = started_at
        @completed_at = completed_at
        @tenant_id = tenant_id
        @generator_class = generator_class
        @error_class = error_class
        @error_message = error_message
      end

      # Status helpers
      def success?
        error_class.nil? && images.any?
      end

      def error?
        !success?
      end

      def single?
        count == 1
      end

      def batch?
        count > 1
      end

      # Image access
      def image
        images.first
      end

      def url
        image&.url
      end

      def urls
        images.map(&:url).compact
      end

      def data
        image&.data
      end

      def datas
        images.map(&:data).compact
      end

      def base64?
        image&.base64? || false
      end

      def mime_type
        image&.mime_type
      end

      def revised_prompt
        image&.revised_prompt
      end

      def revised_prompts
        images.map(&:revised_prompt).compact
      end

      # Count
      def count
        images.size
      end

      # Timing
      def duration_ms
        return 0 unless started_at && completed_at
        ((completed_at - started_at) * 1000).round
      end

      # Cost estimation (varies by model/size/quality)
      def total_cost
        return 0 if error?

        cost_per_image = estimate_cost_per_image
        cost_per_image * count
      end

      def input_tokens
        # Approximate token count for prompt
        (prompt.length / 4.0).ceil
      end

      # File operations
      def save(path)
        raise "No image to save" unless image
        image.save(path)
      end

      def save_all(directory, prefix: "image")
        images.each_with_index do |img, idx|
          filename = "#{prefix}_#{idx + 1}.png"
          img.save(File.join(directory, filename))
        end
      end

      def to_blob
        image&.to_blob
      end

      def blobs
        images.map(&:to_blob)
      end

      # Serialization
      def to_h
        {
          success: success?,
          count: count,
          urls: urls,
          base64: base64?,
          mime_type: mime_type,
          prompt: prompt,
          revised_prompts: revised_prompts,
          model_id: model_id,
          size: size,
          quality: quality,
          style: style,
          total_cost: total_cost,
          input_tokens: input_tokens,
          duration_ms: duration_ms,
          started_at: started_at&.iso8601,
          completed_at: completed_at&.iso8601,
          tenant_id: tenant_id,
          generator_class: generator_class,
          error_class: error_class,
          error_message: error_message
        }
      end

      # Caching
      def to_cache
        {
          urls: urls,
          datas: datas,
          mime_type: mime_type,
          revised_prompts: revised_prompts,
          model_id: model_id,
          total_cost: total_cost,
          cached_at: Time.current.iso8601
        }
      end

      def self.from_cache(data)
        CachedImageGenerationResult.new(data)
      end

      private

      def estimate_cost_per_image
        case model_id
        when /gpt-image|dall-e-3/i
          dalle3_cost
        when /dall-e-2/i
          dalle2_cost
        when /imagen/i
          0.02
        when /flux.*pro/i
          0.05
        when /flux.*dev/i
          0.025
        when /flux.*schnell/i
          0.003
        when /sdxl|stable-diffusion/i
          0.002
        when /ideogram/i
          0.04
        else
          0.04 # Default estimate
        end
      end

      def dalle3_cost
        pixels = parse_pixels
        case quality
        when "hd"
          pixels >= 1_000_000 ? 0.12 : 0.08
        else
          pixels >= 1_000_000 ? 0.08 : 0.04
        end
      end

      def dalle2_cost
        case size
        when "1024x1024" then 0.02
        when "512x512" then 0.018
        else 0.016
        end
      end

      def parse_pixels
        return 1_048_576 unless size # Default 1024x1024
        width, height = size.split("x").map(&:to_i)
        width * height
      end
    end

    # Lightweight result for cached images
    class CachedImageGenerationResult
      attr_reader :urls, :datas, :mime_type, :revised_prompts, :model_id,
                  :total_cost, :cached_at

      def initialize(data)
        @urls = data[:urls] || []
        @datas = data[:datas] || []
        @mime_type = data[:mime_type]
        @revised_prompts = data[:revised_prompts] || []
        @model_id = data[:model_id]
        @total_cost = data[:total_cost]
        @cached_at = data[:cached_at]
      end

      def success?
        urls.any? || datas.any?
      end

      def error?
        !success?
      end

      def cached?
        true
      end

      def url
        urls.first
      end

      def data
        datas.first
      end

      def base64?
        datas.any?
      end

      def count
        [urls.size, datas.size].max
      end

      def single?
        count == 1
      end

      def batch?
        count > 1
      end
    end
  end
end
```

#### Task 5: Add Configuration Options

**Update: `lib/ruby_llm/agents/configuration.rb`**

```ruby
# Add these attributes to the Configuration class:

# Image Generation defaults
attr_accessor :default_image_model
attr_accessor :default_image_size
attr_accessor :default_image_quality
attr_accessor :default_image_style
attr_accessor :max_image_prompt_length
attr_accessor :track_image_generation
attr_accessor :image_model_aliases

# In initialize, add defaults:
def initialize
  # ... existing defaults ...

  # Image Generation
  @default_image_model = "gpt-image-1"
  @default_image_size = "1024x1024"
  @default_image_quality = "standard"
  @default_image_style = "vivid"
  @max_image_prompt_length = 4000
  @track_image_generation = true
  @image_model_aliases = {
    fast: "flux-schnell",
    quality: "gpt-image-1",
    cheap: "sdxl"
  }
end
```

#### Task 6: Add Content Policy Support

**File: `lib/ruby_llm/agents/image_generator/content_policy.rb`**

```ruby
# frozen_string_literal: true

module RubyLLM
  module Agents
    class ImageGenerator
      module ContentPolicy
        BLOCKED_PATTERNS = {
          strict: [
            /\b(violence|violent|gore|blood|death|kill|murder)\b/i,
            /\b(nude|naked|nsfw|explicit|sexual|porn)\b/i,
            /\b(hate|racist|discrimination|slur)\b/i,
            /\b(weapon|gun|knife|bomb|explosive)\b/i,
            /\b(drug|cocaine|heroin|meth)\b/i
          ],
          moderate: [
            /\b(nude|naked|nsfw|explicit|sexual|porn)\b/i,
            /\b(gore|graphic.?violence)\b/i,
            /\b(hate.?speech|slur)\b/i
          ],
          standard: []
        }.freeze

        class << self
          def validate!(prompt, level)
            return if level == :none

            patterns = BLOCKED_PATTERNS[level] || BLOCKED_PATTERNS[:standard]

            patterns.each do |pattern|
              if prompt.match?(pattern)
                raise ContentPolicyViolation, "Prompt contains blocked content matching policy: #{level}"
              end
            end
          end
        end
      end

      class ContentPolicyViolation < StandardError; end
    end
  end
end
```

#### Task 7: Add Prompt Templates Support

**File: `lib/ruby_llm/agents/image_generator/templates.rb`**

```ruby
# frozen_string_literal: true

module RubyLLM
  module Agents
    class ImageGenerator
      module Templates
        extend ActiveSupport::Concern

        class_methods do
          def template(template_string)
            @template = template_string
          end

          def template_string
            @template || inherited_or_default(:template_string, nil)
          end
        end
      end
    end
  end
end
```

#### Task 8: Add ActiveStorage Integration

**File: `lib/ruby_llm/agents/image_generator/active_storage_support.rb`**

```ruby
# frozen_string_literal: true

module RubyLLM
  module Agents
    class ImageGenerator
      module ActiveStorageSupport
        extend ActiveSupport::Concern

        class_methods do
          def generate_and_attach(prompt:, record:, attachment_name:, **options)
            result = call(prompt: prompt, **options)

            return result unless result.success?

            attachment = record.public_send(attachment_name)

            if result.base64?
              attachment.attach(
                io: StringIO.new(result.to_blob),
                filename: "generated_#{Time.current.to_i}.png",
                content_type: result.mime_type
              )
            else
              require "open-uri"
              downloaded = URI.open(result.url)
              attachment.attach(
                io: downloaded,
                filename: "generated_#{Time.current.to_i}.png",
                content_type: "image/png"
              )
            end

            result
          end
        end
      end
    end
  end
end
```

#### Task 9: Create Rails Generator

**File: `lib/generators/ruby_llm_agents/image_generator_generator.rb`**

```ruby
# frozen_string_literal: true

require "rails/generators/base"

module RubyLlmAgents
  module Generators
    class ImageGeneratorGenerator < Rails::Generators::Base
      source_root File.expand_path("templates", __dir__)

      def create_application_image_generator
        template "application_image_generator.rb.tt",
                 "app/agents/application_image_generator.rb"
      end

      def show_readme
        say ""
        say "Image generator base class created!", :green
        say ""
        say "Create your own generators:"
        say ""
        say "  class LogoGenerator < ApplicationImageGenerator"
        say "    model 'gpt-image-1'"
        say "    size '1024x1024'"
        say "    quality 'hd'"
        say "  end"
        say ""
      end
    end
  end
end
```

---

## Phase 2: Image Editing & Transformation

### ImageEditor (Inpainting)

```ruby
class ProductEditor < ApplicationImageEditor
  model "gpt-image-1"  # or "sdxl-inpaint"
end

# Edit a specific region
result = ProductEditor.call(
  image: source_image_path_or_url,
  mask: mask_image,  # White = edit, Black = keep
  prompt: "Replace with a blue version"
)

result.url  # Edited image
```

**File: `lib/ruby_llm/agents/image_editor.rb`**

```ruby
# frozen_string_literal: true

module RubyLLM
  module Agents
    class ImageEditor
      extend ImageEditor::DSL
      include ImageEditor::Execution

      class << self
        def call(image:, mask:, prompt:, **options)
          new(image: image, mask: mask, prompt: prompt, **options).call
        end
      end

      attr_reader :image, :mask, :prompt, :options, :tenant_id

      def initialize(image:, mask:, prompt:, **options)
        @image = image
        @mask = mask
        @prompt = prompt
        @options = options
        @tenant_id = nil
      end

      def call
        execute
      end
    end
  end
end
```

### ImageTransformer (Style Transfer / Img2Img)

```ruby
class StyleTransformer < ApplicationImageTransformer
  model "sdxl"
  strength 0.7  # How much to transform (0.0-1.0)
end

# Transform an existing image
result = StyleTransformer.call(
  image: photo_path,
  prompt: "Convert to watercolor painting style"
)

result.url
```

**File: `lib/ruby_llm/agents/image_transformer.rb`**

```ruby
# frozen_string_literal: true

module RubyLLM
  module Agents
    class ImageTransformer
      extend ImageTransformer::DSL
      include ImageTransformer::Execution

      class << self
        def call(image:, prompt:, **options)
          new(image: image, prompt: prompt, **options).call
        end
      end

      attr_reader :image, :prompt, :options, :tenant_id

      def initialize(image:, prompt:, **options)
        @image = image
        @prompt = prompt
        @options = options
        @tenant_id = nil
      end

      def call
        execute
      end
    end
  end
end
```

**DSL additions:**

```ruby
module DSL
  def strength(value = nil)
    if value
      @strength = value
    else
      @strength || inherited_or_default(:strength, 0.75)
    end
  end

  def preserve_composition(value = nil)
    if value
      @preserve_composition = value
    else
      @preserve_composition || inherited_or_default(:preserve_composition, true)
    end
  end
end
```

### ImageUpscaler

```ruby
class PhotoUpscaler < ApplicationImageUpscaler
  model "real-esrgan"  # or "real-esrgan-x4plus"
  scale 4              # 2x, 4x, or 8x
end

result = PhotoUpscaler.call(image: low_res_image)
result.url      # High resolution version
result.scale    # 4
result.size     # "4096x4096" (if input was 1024x1024)
```

**File: `lib/ruby_llm/agents/image_upscaler.rb`**

```ruby
# frozen_string_literal: true

module RubyLLM
  module Agents
    class ImageUpscaler
      extend ImageUpscaler::DSL
      include ImageUpscaler::Execution

      class << self
        def call(image:, **options)
          new(image: image, **options).call
        end
      end

      attr_reader :image, :options, :tenant_id

      def initialize(image:, **options)
        @image = image
        @options = options
        @tenant_id = nil
      end

      def call
        execute
      end
    end
  end
end
```

**DSL:**

```ruby
module DSL
  def scale(value = nil)
    if value
      raise ArgumentError, "Scale must be 2, 4, or 8" unless [2, 4, 8].include?(value)
      @scale = value
    else
      @scale || inherited_or_default(:scale, 4)
    end
  end

  def face_enhance(value = nil)
    if value.nil?
      @face_enhance || inherited_or_default(:face_enhance, false)
    else
      @face_enhance = value
    end
  end
end
```

### ImageVariator

```ruby
class LogoVariator < ApplicationImageVariator
  model "gpt-image-1"
  variation_strength 0.3  # How different variations should be
end

result = LogoVariator.call(
  image: original_logo,
  count: 4
)

result.urls  # 4 variations of the original
```

---

## Phase 3: Analysis & Extraction

### ImageAnalyzer

```ruby
class ProductAnalyzer < ApplicationImageAnalyzer
  model "blip-2"  # or "gpt-4-vision"
  analysis_type :detailed  # :caption, :detailed, :tags, :objects
end

result = ProductAnalyzer.call(image: product_photo)

result.caption      # "A silver laptop on a wooden desk"
result.tags         # [:electronics, :laptop, :desk, :technology]
result.objects      # [{name: "laptop", confidence: 0.98, bbox: [...]}, ...]
result.colors       # [{hex: "#C0C0C0", name: "silver", percentage: 45}, ...]
result.description  # Detailed multi-sentence description
```

**File: `lib/ruby_llm/agents/image_analyzer.rb`**

```ruby
# frozen_string_literal: true

module RubyLLM
  module Agents
    class ImageAnalyzer
      extend ImageAnalyzer::DSL
      include ImageAnalyzer::Execution

      class << self
        def call(image:, **options)
          new(image: image, **options).call
        end
      end

      attr_reader :image, :options, :tenant_id

      def initialize(image:, **options)
        @image = image
        @options = options
        @tenant_id = nil
      end

      def call
        execute
      end
    end
  end
end
```

### BackgroundRemover

```ruby
class ProductBackgroundRemover < ApplicationBackgroundRemover
  model "segment-anything"  # or "rembg"
  output_format :png        # Transparent PNG
end

result = ProductBackgroundRemover.call(image: product_photo)

result.url           # Transparent PNG
result.foreground    # Just the subject
result.mask          # Segmentation mask
result.has_alpha?    # true
```

---

## Phase 4: Pipeline Orchestration

### ImagePipeline

Chain multiple operations together:

```ruby
class ProductImagePipeline < ApplicationImagePipeline
  # Define the pipeline steps
  step :generate, generator: ProductGenerator
  step :upscale, upscaler: PhotoUpscaler, scale: 2
  step :remove_background, remover: BackgroundRemover
  step :analyze, analyzer: ProductAnalyzer

  # Optional: Add watermark at the end
  after_pipeline :add_watermark
end

result = ProductImagePipeline.call(prompt: "A sleek laptop")

result.final_image   # Final processed image
result.steps         # Array of intermediate results
result.analysis      # Analysis from the analyzer step
result.total_cost    # Combined cost of all steps
result.duration_ms   # Total time
```

**File: `lib/ruby_llm/agents/image_pipeline.rb`**

```ruby
# frozen_string_literal: true

module RubyLLM
  module Agents
    class ImagePipeline
      extend ImagePipeline::DSL
      include ImagePipeline::Execution

      class << self
        def call(**options)
          new(**options).call
        end

        def steps
          @steps ||= []
        end

        def step(name, **config)
          steps << { name: name, config: config }
        end
      end

      attr_reader :options, :tenant_id, :step_results

      def initialize(**options)
        @options = options
        @tenant_id = nil
        @step_results = []
      end

      def call
        execute
      end

      private

      def execute
        started_at = Time.current
        current_image = nil

        self.class.steps.each do |step|
          result = execute_step(step, current_image)
          @step_results << { name: step[:name], result: result }

          break unless result.success?
          current_image = result.url || result.data
        end

        build_pipeline_result(started_at)
      end

      def execute_step(step, input_image)
        case step[:name]
        when :generate
          step[:config][:generator].call(prompt: options[:prompt], **step[:config])
        when :upscale
          step[:config][:upscaler].call(image: input_image, **step[:config])
        when :remove_background
          step[:config][:remover].call(image: input_image, **step[:config])
        when :transform
          step[:config][:transformer].call(image: input_image, **step[:config])
        when :analyze
          step[:config][:analyzer].call(image: input_image, **step[:config])
        end
      end
    end
  end
end
```

---

## ControlNet Support (Advanced)

For models that support ControlNet (SDXL, SD 3.5):

```ruby
class ArchitectureGenerator < ApplicationImageGenerator
  model "sdxl"
  control_type :canny_edge  # :depth, :pose, :segmentation, :scribble
  control_strength 0.8
end

result = ArchitectureGenerator.call(
  prompt: "Modern glass skyscraper, photorealistic",
  control_image: sketch_image  # Edge/structure reference
)
```

**DSL additions:**

```ruby
module ControlNetDSL
  CONTROL_TYPES = %i[
    canny_edge
    depth
    pose
    segmentation
    scribble
    lineart
    softedge
    normal
    mlsd
  ].freeze

  def control_type(value = nil)
    if value
      raise ArgumentError, "Unknown control type" unless CONTROL_TYPES.include?(value)
      @control_type = value
    else
      @control_type || inherited_or_default(:control_type, nil)
    end
  end

  def control_strength(value = nil)
    if value
      raise ArgumentError, "Strength must be 0.0-1.0" unless value.between?(0.0, 1.0)
      @control_strength = value
    else
      @control_strength || inherited_or_default(:control_strength, 0.75)
    end
  end
end
```

---

## File Structure

```
lib/ruby_llm/agents/
├── image_generator.rb
├── image_generator/
│   ├── dsl.rb
│   ├── execution.rb
│   ├── content_policy.rb
│   ├── templates.rb
│   ├── control_net.rb
│   └── active_storage_support.rb
├── image_editor.rb
├── image_editor/
│   ├── dsl.rb
│   └── execution.rb
├── image_transformer.rb
├── image_transformer/
│   ├── dsl.rb
│   └── execution.rb
├── image_upscaler.rb
├── image_upscaler/
│   ├── dsl.rb
│   └── execution.rb
├── image_variator.rb
├── image_variator/
│   ├── dsl.rb
│   └── execution.rb
├── image_analyzer.rb
├── image_analyzer/
│   ├── dsl.rb
│   └── execution.rb
├── background_remover.rb
├── background_remover/
│   ├── dsl.rb
│   └── execution.rb
├── image_pipeline.rb
├── image_pipeline/
│   ├── dsl.rb
│   └── execution.rb
└── results/
    ├── image_generation_result.rb
    ├── image_edit_result.rb
    ├── image_transform_result.rb
    ├── image_upscale_result.rb
    ├── image_variation_result.rb
    ├── image_analysis_result.rb
    ├── background_removal_result.rb
    └── image_pipeline_result.rb

lib/generators/ruby_llm_agents/
├── image_generator_generator.rb
├── image_editor_generator.rb
├── image_transformer_generator.rb
├── image_upscaler_generator.rb
├── image_analyzer_generator.rb
├── background_remover_generator.rb
└── templates/
    ├── application_image_generator.rb.tt
    ├── application_image_editor.rb.tt
    ├── application_image_transformer.rb.tt
    ├── application_image_upscaler.rb.tt
    ├── application_image_analyzer.rb.tt
    └── application_background_remover.rb.tt

spec/ruby_llm/agents/
├── image_generator_spec.rb
├── image_editor_spec.rb
├── image_transformer_spec.rb
├── image_upscaler_spec.rb
├── image_variator_spec.rb
├── image_analyzer_spec.rb
├── background_remover_spec.rb
└── image_pipeline_spec.rb
```

---

## Usage Examples

### Basic Generation with Model Selection

```ruby
class ArtGenerator < ApplicationImageGenerator
  model "flux-2-pro"  # Use FLUX for best open-source quality
  size "1024x1024"
  guidance_scale 7.5
  steps 30
end

result = ArtGenerator.call(prompt: "A sunset over mountains, impressionist style")
```

### Fast Generation for Previews

```ruby
class PreviewGenerator < ApplicationImageGenerator
  model :fast  # Uses flux-schnell via alias
  size "512x512"
end

# Generate quick preview, then high quality
preview = PreviewGenerator.call(prompt: "Logo concept")
if user_approves?(preview)
  final = LogoGenerator.call(prompt: "Logo concept", model: :quality)
end
```

### Complete Product Pipeline

```ruby
class ProductPipeline < ApplicationImagePipeline
  step :generate, generator: ProductGenerator
  step :upscale, upscaler: PhotoUpscaler, scale: 2
  step :remove_background, remover: BackgroundRemover
end

result = ProductPipeline.call(
  prompt: "Professional photo of wireless earbuds",
  tenant: current_organization
)

# Attach to product
product.images.attach(
  io: StringIO.new(result.to_blob),
  filename: "product_hero.png"
)
```

### Style Transfer

```ruby
class AnimeTransformer < ApplicationImageTransformer
  model "sdxl"
  strength 0.8
  template "anime style, studio ghibli, {prompt}"
end

result = AnimeTransformer.call(
  image: user_photo,
  prompt: "portrait of a person"
)
```

---

## Testing Strategy

### Unit Tests

```ruby
RSpec.describe RubyLLM::Agents::ImageGenerator do
  describe "DSL" do
    it "supports model aliases" do
      generator = Class.new(described_class) { model :fast }
      expect(generator.new(prompt: "test").send(:resolve_model)).to eq("flux-schnell")
    end

    it "validates strength range" do
      expect {
        Class.new(described_class) { strength 1.5 }
      }.to raise_error(ArgumentError)
    end
  end
end
```

### Integration Tests

```ruby
RSpec.describe "Image Generation Integration" do
  it "generates with FLUX model" do
    VCR.use_cassette("flux_generation") do
      result = TestGenerator.call(
        prompt: "A simple red circle",
        model: "flux-schnell"
      )
      expect(result.success?).to be true
    end
  end
end
```

---

## Implementation Priority

| Phase | Feature | Priority | Complexity | Dependencies |
|-------|---------|----------|------------|--------------|
| **1** | ImageGenerator | P1 | Medium | RubyLLM.paint |
| **1** | Model Aliases | P1 | Low | Configuration |
| **1** | Content Policy | P1 | Low | None |
| **1** | Templates | P1 | Low | None |
| **1** | ActiveStorage | P1 | Low | Rails |
| **2** | ImageVariator | P2 | Low | RubyLLM |
| **2** | ImageTransformer | P2 | Medium | Replicate/Custom |
| **2** | ImageEditor | P2 | Medium | Replicate/Custom |
| **2** | ImageUpscaler | P2 | Low | Replicate/Custom |
| **3** | ImageAnalyzer | P3 | Medium | Vision models |
| **3** | BackgroundRemover | P3 | Medium | Replicate/Custom |
| **3** | ControlNet | P3 | High | SDXL/SD3 |
| **4** | ImagePipeline | P4 | Medium | All above |

---

## Dependencies

### Required
- RubyLLM gem with `RubyLLM.paint` support

### Optional
- Rails (for ActiveStorage, generators, caching)
- Replicate gem (for FLUX, SDXL, upscaling models)
- AWS SDK / GCS (for cloud storage of generated images)

### Provider Support Status

| Provider | Generation | Editing | Variations | Upscaling | Analysis |
|----------|------------|---------|------------|-----------|----------|
| OpenAI | ✅ | ✅ | ✅ | ❌ | Via GPT-4V |
| Google | ✅ | ❌ | ❌ | ❌ | Via Gemini |
| Replicate | ✅ | ✅ | ✅ | ✅ | ✅ |
| Stability | ✅ | ✅ | ✅ | ✅ | ❌ |

---

## Open Questions

1. **Replicate Integration**: Should we add first-class Replicate support for additional models, or rely on custom endpoints?
   - **Recommendation**: Add optional Replicate adapter in Phase 2

2. **Image Storage**: Should we auto-persist images to prevent URL expiration?
   - **Recommendation**: Add `persist: true` option that saves to configured storage

3. **Async Generation**: Should long-running operations be async by default?
   - **Recommendation**: Yes, add `async: true` option returning a job ID

4. **Webhook Support**: Should we support webhooks for completion notification?
   - **Recommendation**: Add in Phase 4 with ImagePipeline

---

## Notes

- All model support depends on RubyLLM provider availability or custom endpoint configuration
- Cost estimates are approximate and should be verified against current provider pricing
- Some features (ControlNet, advanced editing) may require direct Replicate/Stability API integration
