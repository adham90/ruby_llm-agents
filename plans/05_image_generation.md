# Image Generation Support Plan

## Overview

Add image generation capabilities to ruby_llm-agents through a new `ImageGenerator` class that wraps `RubyLLM.paint()`. This follows the established patterns from `Embedder` and `Moderator` - a standalone class with its own DSL, execution flow, and result wrapper.

## RubyLLM API Reference

RubyLLM provides image generation via `RubyLLM.paint()`:

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

## Supported Models

### Currently in RubyLLM
- **OpenAI**: `gpt-image-1` (DALL-E 3) - Returns URLs
- **Google**: `imagen-3.0-generate-002` - Returns Base64 data

### Future/Custom Model Support
The design should be extensible for additional providers:
- **Stability AI**: Stable Diffusion models
- **Replicate**: Various models (SDXL, etc.)
- **Custom endpoints**: Via `assume_model_exists: true`

Note: Support for additional models depends on RubyLLM provider support. Our implementation will be model-agnostic and work with any model RubyLLM supports.

---

## API Design

### Basic Usage

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

### Configuration Options

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

### Runtime Overrides

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

### Batch Generation

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

### Multi-tenancy

```ruby
result = LogoGenerator.call(
  prompt: "Corporate logo",
  tenant: organization
)
# Budget checked against organization
# Execution tracked with tenant_id
```

---

## Implementation Tasks

### Task 1: Create ImageGenerator Base Class

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

### Task 2: Create DSL Module

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

### Task 3: Create Execution Module

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

        def generate_images
          count = resolve_count
          model = resolve_model

          Array.new(count) do
            RubyLLM.paint(
              prompt,
              model: model,
              size: resolve_size,
              quality: resolve_quality,
              style: resolve_style
            )
          end
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
          options[:model] || self.class.model
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

### Task 4: Create Result Class

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

        # Cost per image based on model and settings
        # These are approximate - actual costs depend on provider pricing
        cost_per_image = case model_id
                         when /gpt-image|dall-e-3/i
                           case quality
                           when "hd"
                             size_based_cost(:dalle3_hd)
                           else
                             size_based_cost(:dalle3_standard)
                           end
                         when /dall-e-2/i
                           size_based_cost(:dalle2)
                         when /imagen/i
                           0.02 # Google Imagen approximate
                         else
                           0.04 # Default estimate
                         end

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
        # Reconstruct from cached data
        # Note: This creates a lightweight result without full RubyLLM::Image objects
        CachedImageGenerationResult.new(data)
      end

      private

      def size_based_cost(model_type)
        # Pricing tiers based on size
        width, height = size.split("x").map(&:to_i)
        pixels = width * height

        case model_type
        when :dalle3_hd
          pixels >= 1_000_000 ? 0.12 : 0.08
        when :dalle3_standard
          pixels >= 1_000_000 ? 0.08 : 0.04
        when :dalle2
          case size
          when "1024x1024" then 0.02
          when "512x512" then 0.018
          else 0.016
          end
        else
          0.04
        end
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

### Task 5: Add Configuration Options

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
end
```

### Task 6: Update Main Module

**Update: `lib/ruby_llm/agents.rb`**

```ruby
# Add require for image generator:
require_relative "agents/image_generator"
require_relative "agents/image_generation_result"
```

### Task 7: Create Rails Generator

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
        say "Create your own image generators by inheriting from ApplicationImageGenerator:"
        say ""
        say "  class LogoGenerator < ApplicationImageGenerator"
        say "    model 'gpt-image-1'"
        say "    size '1024x1024'"
        say "    quality 'hd'"
        say "    style 'vivid'"
        say ""
        say "    description 'Generates company logos'"
        say "  end"
        say ""
        say "Then use it:"
        say ""
        say "  result = LogoGenerator.call(prompt: 'A minimalist tech logo')"
        say "  result.url  # => 'https://...'"
        say ""
      end
    end
  end
end
```

**File: `lib/generators/ruby_llm_agents/templates/application_image_generator.rb.tt`**

```ruby
# frozen_string_literal: true

class ApplicationImageGenerator < RubyLLM::Agents::ImageGenerator
  # Default model for all image generators
  model "gpt-image-1"

  # Default size
  size "1024x1024"

  # Default quality
  quality "standard"

  # Default style
  style "vivid"
end
```

### Task 8: Add ActiveStorage Integration Helper

**File: `lib/ruby_llm/agents/image_generator/active_storage_support.rb`**

```ruby
# frozen_string_literal: true

module RubyLLM
  module Agents
    class ImageGenerator
      module ActiveStorageSupport
        extend ActiveSupport::Concern

        class_methods do
          # Convenience method to generate and attach to a record
          def generate_and_attach(prompt:, record:, attachment_name:, **options)
            result = call(prompt: prompt, **options)

            return result unless result.success?

            attachment = record.public_send(attachment_name)

            if result.base64?
              # Google Imagen returns base64
              attachment.attach(
                io: StringIO.new(result.to_blob),
                filename: "generated_#{Time.current.to_i}.png",
                content_type: result.mime_type
              )
            else
              # OpenAI returns URLs - download and attach
              require "open-uri"
              downloaded = URI.open(result.url) # rubocop:disable Security/Open
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

Usage:
```ruby
class ProductImage < ApplicationImageGenerator
  include RubyLLM::Agents::ImageGenerator::ActiveStorageSupport

  model "gpt-image-1"
  size "1024x1024"
end

# Attach generated image to a Product record
result = ProductImage.generate_and_attach(
  prompt: "A professional product photo",
  record: product,
  attachment_name: :hero_image
)
```

### Task 9: Add Content Policy Support

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
            /\b(nude|naked|nsfw|explicit|sexual)\b/i,
            /\b(hate|racist|discrimination)\b/i,
            /\b(weapon|gun|knife|bomb)\b/i
          ],
          moderate: [
            /\b(nude|naked|nsfw|explicit|sexual)\b/i,
            /\b(gore|graphic violence)\b/i
          ],
          standard: []
        }.freeze

        def validate_content_policy!(prompt, level)
          return if level == :none

          patterns = BLOCKED_PATTERNS[level] || BLOCKED_PATTERNS[:standard]

          patterns.each do |pattern|
            if prompt.match?(pattern)
              raise ContentPolicyViolation, "Prompt contains blocked content"
            end
          end
        end
      end

      class ContentPolicyViolation < StandardError; end
    end
  end
end
```

### Task 10: Add Prompt Templates Support

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

        private

        def apply_template(prompt)
          template = self.class.template_string
          return prompt unless template

          template.gsub("{prompt}", prompt)
        end
      end
    end
  end
end
```

Usage:
```ruby
class ProductPhotoGenerator < ApplicationImageGenerator
  include RubyLLM::Agents::ImageGenerator::Templates

  model "gpt-image-1"
  quality "hd"

  # All prompts will be wrapped in this template
  template "Professional product photography of {prompt}, " \
           "studio lighting, white background, 4K quality"
end

# User provides simple prompt, template enhances it
result = ProductPhotoGenerator.call(prompt: "a red sneaker")
# Actual prompt: "Professional product photography of a red sneaker,
#                studio lighting, white background, 4K quality"
```

---

## File Structure

```
lib/ruby_llm/agents/
├── image_generator.rb                        # Main class
├── image_generator/
│   ├── dsl.rb                                # Configuration DSL
│   ├── execution.rb                          # Execution logic
│   ├── content_policy.rb                     # Content filtering
│   ├── templates.rb                          # Prompt templates
│   └── active_storage_support.rb             # Rails integration
├── image_generation_result.rb                # Result wrapper

lib/generators/ruby_llm_agents/
├── image_generator_generator.rb              # Rails generator
└── templates/
    └── application_image_generator.rb.tt     # Generator template

spec/ruby_llm/agents/
├── image_generator_spec.rb                   # Main specs
├── image_generator/
│   ├── dsl_spec.rb
│   ├── execution_spec.rb
│   └── content_policy_spec.rb
└── image_generation_result_spec.rb
```

---

## Usage Examples

### Basic Generation

```ruby
class ArtGenerator < ApplicationImageGenerator
  model "gpt-image-1"
  size "1024x1024"
  quality "hd"
  style "vivid"
end

result = ArtGenerator.call(prompt: "A sunset over mountains in impressionist style")
puts result.url
```

### With Caching (Deterministic Results)

```ruby
class IconGenerator < ApplicationImageGenerator
  model "gpt-image-1"
  size "512x512"
  quality "standard"

  cache_for 24.hours
  version "v2"  # Bump to invalidate cache
end

# First call generates, subsequent calls return cached
result = IconGenerator.call(prompt: "A simple home icon")
```

### Batch Generation for Variations

```ruby
class LogoGenerator < ApplicationImageGenerator
  model "gpt-image-1"
  size "1024x1024"
  quality "hd"
end

# Generate 4 variations
result = LogoGenerator.call(prompt: "A tech startup logo", count: 4)
result.urls.each_with_index do |url, idx|
  puts "Variation #{idx + 1}: #{url}"
end
```

### With ActiveStorage

```ruby
class ProductImageGenerator < ApplicationImageGenerator
  include RubyLLM::Agents::ImageGenerator::ActiveStorageSupport

  model "gpt-image-1"
  quality "hd"
end

# In a controller or service
ProductImageGenerator.generate_and_attach(
  prompt: "A professional photo of #{product.name}",
  record: product,
  attachment_name: :featured_image,
  tenant: current_organization
)
```

### With Templates

```ruby
class MarketingImageGenerator < ApplicationImageGenerator
  include RubyLLM::Agents::ImageGenerator::Templates

  model "gpt-image-1"
  quality "hd"
  style "vivid"

  template "High-quality marketing image: {prompt}. " \
           "Professional, modern, clean design, suitable for advertising."
end

# Simple prompt gets enhanced automatically
result = MarketingImageGenerator.call(prompt: "coffee cup on desk")
```

### Multi-Provider Support

```ruby
class FlexibleGenerator < ApplicationImageGenerator
  model "gpt-image-1"  # Default to OpenAI
end

# Use OpenAI
openai_result = FlexibleGenerator.call(
  prompt: "A landscape photo",
  model: "gpt-image-1"
)
openai_result.url  # Returns URL

# Use Google Imagen
google_result = FlexibleGenerator.call(
  prompt: "A landscape photo",
  model: "imagen-3.0-generate-002"
)
google_result.data     # Returns base64
google_result.base64?  # => true
```

---

## Testing Strategy

### Unit Tests

```ruby
RSpec.describe RubyLLM::Agents::ImageGenerator do
  describe "DSL" do
    it "inherits configuration from parent" do
      parent = Class.new(described_class) { model "gpt-image-1" }
      child = Class.new(parent)
      expect(child.model).to eq("gpt-image-1")
    end

    it "allows overriding in subclass" do
      parent = Class.new(described_class) { model "gpt-image-1" }
      child = Class.new(parent) { model "dall-e-2" }
      expect(child.model).to eq("dall-e-2")
    end
  end

  describe "validation" do
    it "rejects blank prompts" do
      generator = Class.new(described_class)
      expect {
        generator.call(prompt: "")
      }.to raise_error(ArgumentError, /cannot be blank/)
    end

    it "rejects prompts exceeding max length" do
      generator = Class.new(described_class)
      long_prompt = "x" * 5000
      expect {
        generator.call(prompt: long_prompt)
      }.to raise_error(ArgumentError, /exceeds maximum/)
    end
  end
end
```

### Integration Tests

```ruby
RSpec.describe "Image Generation Integration" do
  let(:generator_class) do
    Class.new(RubyLLM::Agents::ImageGenerator) do
      model "gpt-image-1"
      size "1024x1024"
    end
  end

  it "generates an image via RubyLLM" do
    mock_image = double(
      url: "https://example.com/image.png",
      data: nil,
      mime_type: "image/png",
      base64?: false,
      revised_prompt: "Enhanced prompt"
    )

    allow(RubyLLM).to receive(:paint).and_return(mock_image)

    result = generator_class.call(prompt: "A test image")

    expect(result.success?).to be true
    expect(result.url).to eq("https://example.com/image.png")
    expect(RubyLLM).to have_received(:paint).with(
      "A test image",
      model: "gpt-image-1",
      size: "1024x1024",
      quality: "standard",
      style: "vivid"
    )
  end

  it "records execution" do
    allow(RubyLLM).to receive(:paint).and_return(mock_image)

    expect {
      generator_class.call(prompt: "Test", tenant: { id: 123 })
    }.to change(RubyLLM::Agents::Execution, :count).by(1)

    execution = RubyLLM::Agents::Execution.last
    expect(execution.execution_type).to eq("image_generation")
    expect(execution.tenant_id).to eq(123)
  end
end
```

### Cost Calculation Tests

```ruby
RSpec.describe RubyLLM::Agents::ImageGenerationResult do
  describe "#total_cost" do
    it "calculates DALL-E 3 HD 1024x1024 cost" do
      result = build_result(model_id: "gpt-image-1", size: "1024x1024", quality: "hd")
      expect(result.total_cost).to eq(0.08)
    end

    it "calculates DALL-E 3 HD large size cost" do
      result = build_result(model_id: "gpt-image-1", size: "1792x1024", quality: "hd")
      expect(result.total_cost).to eq(0.12)
    end

    it "multiplies by count for batch" do
      result = build_result(model_id: "gpt-image-1", size: "1024x1024", quality: "standard", count: 4)
      expect(result.total_cost).to eq(0.04 * 4)
    end
  end
end
```

---

## Open Questions

### 1. Should we support image editing/inpainting?

RubyLLM may support image editing (providing a source image + mask). This would be a more complex feature.

**Recommendation**: Start with generation only. Add editing as a separate `ImageEditor` class later if needed.

### 2. Should we support image-to-image generation?

Some models support using an image as input to generate variations.

**Recommendation**: This could be a future enhancement. For now, focus on text-to-image.

### 3. How should we handle rate limiting?

Image generation APIs often have stricter rate limits than text APIs.

**Recommendation**: Add optional retry logic with exponential backoff. Consider adding a `rate_limit` DSL option.

### 4. Should we auto-download and cache image data?

URLs from OpenAI expire after some time.

**Recommendation**: Add an optional `persist_images: true` option that downloads and stores images locally or in cloud storage. Default to returning URLs only.

### 5. Model aliasing for portability?

Should we support model aliases like `fast_image` -> `dall-e-2` to make switching easier?

**Recommendation**: Not in v1. Keep it explicit for clarity. Consider for future.

---

## Implementation Order

### Phase 1: Core Implementation
1. Create `ImageGenerator` base class
2. Create `DSL` module
3. Create `Execution` module
4. Create `ImageGenerationResult` class
5. Add configuration options
6. Update main module requires

### Phase 2: Rails Integration
7. Create Rails generator
8. Add ActiveStorage support helper

### Phase 3: Enhanced Features
9. Add content policy support
10. Add prompt templates support

### Phase 4: Testing & Documentation
11. Write comprehensive specs
12. Add documentation and examples
13. Update README

---

## Dependencies

- RubyLLM gem with image generation support (`RubyLLM.paint`)
- Rails (optional, for ActiveStorage integration)
- No additional gems required

---

## Notes on Additional Model Support

The implementation is designed to be model-agnostic. Support for additional models (like models from Stability AI, Replicate, etc.) depends on RubyLLM adding provider support. Once RubyLLM supports a new image provider, this implementation will automatically work with it by simply specifying the model name.

For custom/self-hosted models, use the `assume_model_exists: true` option:

```ruby
class CustomGenerator < ApplicationImageGenerator
  model "my-custom-model"
end

result = CustomGenerator.call(
  prompt: "A test image",
  assume_model_exists: true
)
```
