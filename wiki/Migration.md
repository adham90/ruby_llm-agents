# Migration Guide: v0.5.0 to v1.0.0

This guide helps you upgrade your application from RubyLLM::Agents v0.5.0 to v1.0.0.

## Overview

### Major Version Highlights

v1.0.0 introduces significant improvements to the gem's architecture:

- **New Directory Structure** - Organized layout under `app/llm/` with logical groupings
- **Namespace Changes** - All classes now use the `Llm::` namespace prefix
- **Audio Agents** - New Transcriber and Speaker agents for speech-to-text and text-to-speech
- **Image Operations** - Comprehensive image generation, analysis, editing, and pipelines
- **Extended Thinking** - Support for chain-of-thought reasoning
- **Content Moderation** - Built-in content safety filtering
- **Middleware Pipeline** - Pluggable architecture for agent execution
- **Multi-Tenant API Keys** - Per-tenant API configuration support

### Breaking Changes Summary

| Change | Impact | Migration Required |
|--------|--------|-------------------|
| Directory structure | High | Yes - file moves |
| Class namespaces | High | Yes - code updates |
| `cache` → `cache_for` | Low | Recommended |
| Result hash access | Low | Recommended |

### Estimated Migration Effort

- **Small apps** (1-5 agents): ~15 minutes with automated tool
- **Medium apps** (5-20 agents): ~30 minutes with automated tool
- **Large apps** (20+ agents): ~1 hour with automated tool + manual review

---

## Directory Structure Changes (Breaking)

### Old Structure (v0.5.0)

```
app/
├── agents/
│   ├── application_agent.rb
│   └── support_agent.rb
├── embedders/
│   └── document_embedder.rb
├── speakers/
│   └── narrator_speaker.rb
├── transcribers/
│   └── meeting_transcriber.rb
├── image_generators/
│   └── logo_generator.rb
├── image_analyzers/
│   └── product_analyzer.rb
├── image_editors/
│   └── photo_editor.rb
├── image_transformers/
│   └── anime_transformer.rb
├── image_upscalers/
│   └── photo_upscaler.rb
├── image_variators/
│   └── logo_variator.rb
├── background_removers/
│   └── product_remover.rb
└── image_pipelines/
    └── product_pipeline.rb
```

### New Structure (v1.0.0)

```
app/
└── llm/                              # Root directory (customizable)
    ├── agents/                       # Core conversation agents
    │   ├── application_agent.rb
    │   └── support_agent.rb
    ├── audio/                        # Audio operations
    │   ├── speakers/
    │   │   ├── application_speaker.rb
    │   │   └── narrator_speaker.rb
    │   └── transcribers/
    │       ├── application_transcriber.rb
    │       └── meeting_transcriber.rb
    ├── text/                         # Text operations
    │   ├── embedders/
    │   │   ├── application_embedder.rb
    │   │   └── document_embedder.rb
    │   └── moderators/
    │       └── application_moderator.rb
    ├── image/                        # Image operations
    │   ├── generators/
    │   │   ├── application_image_generator.rb
    │   │   └── logo_generator.rb
    │   ├── analyzers/
    │   │   └── product_analyzer.rb
    │   ├── editors/
    │   │   └── photo_editor.rb
    │   ├── transformers/
    │   │   └── anime_transformer.rb
    │   ├── upscalers/
    │   │   └── photo_upscaler.rb
    │   ├── variators/
    │   │   └── logo_variator.rb
    │   ├── background_removers/
    │   │   └── product_remover.rb
    │   └── pipelines/
    │       └── product_pipeline.rb
    ├── workflows/                    # Workflow orchestration
    └── tools/                        # Custom tools
```

---

## Namespace Changes (Breaking)

All classes now live under the `Llm::` namespace (or your configured root namespace).

### Complete Mapping

| Old Class Name | New Class Name |
|----------------|----------------|
| `ApplicationAgent` | `Llm::ApplicationAgent` |
| `SupportAgent` | `Llm::SupportAgent` |
| `Chat::SupportAgent` | `Llm::Chat::SupportAgent` |
| `ApplicationEmbedder` | `Llm::Text::ApplicationEmbedder` |
| `DocumentEmbedder` | `Llm::Text::DocumentEmbedder` |
| `ApplicationSpeaker` | `Llm::Audio::ApplicationSpeaker` |
| `NarratorSpeaker` | `Llm::Audio::NarratorSpeaker` |
| `ApplicationTranscriber` | `Llm::Audio::ApplicationTranscriber` |
| `MeetingTranscriber` | `Llm::Audio::MeetingTranscriber` |
| `ApplicationImageGenerator` | `Llm::Image::ApplicationImageGenerator` |
| `LogoGenerator` | `Llm::Image::LogoGenerator` |
| `ApplicationImageAnalyzer` | `Llm::Image::ApplicationImageAnalyzer` |
| `ProductAnalyzer` | `Llm::Image::ProductAnalyzer` |
| `ApplicationImageEditor` | `Llm::Image::ApplicationImageEditor` |
| `PhotoEditor` | `Llm::Image::PhotoEditor` |
| `ApplicationImageTransformer` | `Llm::Image::ApplicationImageTransformer` |
| `AnimeTransformer` | `Llm::Image::AnimeTransformer` |
| `ApplicationImageUpscaler` | `Llm::Image::ApplicationImageUpscaler` |
| `PhotoUpscaler` | `Llm::Image::PhotoUpscaler` |
| `ApplicationImageVariator` | `Llm::Image::ApplicationImageVariator` |
| `LogoVariator` | `Llm::Image::LogoVariator` |
| `ApplicationBackgroundRemover` | `Llm::Image::ApplicationBackgroundRemover` |
| `ProductRemover` | `Llm::Image::ProductRemover` |
| `ApplicationImagePipeline` | `Llm::Image::ApplicationImagePipeline` |
| `ProductPipeline` | `Llm::Image::ProductPipeline` |

---

## Automated Migration with Restructure Generator

The easiest way to migrate is using the provided generator:

```bash
# Preview what will change (recommended first step)
rails generate ruby_llm_agents:restructure --dry_run

# Run the actual migration
rails generate ruby_llm_agents:restructure
```

### What the Generator Does

1. **Creates new directory structure** under `app/llm/`
2. **Moves all files** to their new locations
3. **Wraps classes** in proper namespace modules
4. **Cleans up** empty old directories

### Generator Options

```bash
# Use a custom root directory (default: llm)
rails generate ruby_llm_agents:restructure --root=ai

# Use a custom namespace (default: Llm)
rails generate ruby_llm_agents:restructure --namespace=AI

# Combine options
rails generate ruby_llm_agents:restructure --root=ai --namespace=AI
```

### Directory Mapping

| Old Directory | New Directory |
|---------------|---------------|
| `app/agents/` | `app/llm/agents/` |
| `app/embedders/` | `app/llm/text/embedders/` |
| `app/moderators/` | `app/llm/text/moderators/` |
| `app/speakers/` | `app/llm/audio/speakers/` |
| `app/transcribers/` | `app/llm/audio/transcribers/` |
| `app/image_generators/` | `app/llm/image/generators/` |
| `app/image_analyzers/` | `app/llm/image/analyzers/` |
| `app/image_editors/` | `app/llm/image/editors/` |
| `app/image_transformers/` | `app/llm/image/transformers/` |
| `app/image_upscalers/` | `app/llm/image/upscalers/` |
| `app/image_variators/` | `app/llm/image/variators/` |
| `app/background_removers/` | `app/llm/image/background_removers/` |
| `app/image_pipelines/` | `app/llm/image/pipelines/` |
| `app/workflows/` | `app/llm/workflows/` |
| `app/tools/` | `app/llm/tools/` |

---

## Manual Migration Steps

If you prefer manual migration or need to handle special cases:

### Step 1: Create New Directory Structure

```bash
mkdir -p app/llm/{agents,audio/{speakers,transcribers},text/{embedders,moderators},image/{generators,analyzers,editors,transformers,upscalers,variators,background_removers,pipelines},workflows,tools}
```

### Step 2: Move Files

```bash
# Agents
mv app/agents/*.rb app/llm/agents/

# Audio
mv app/speakers/*.rb app/llm/audio/speakers/
mv app/transcribers/*.rb app/llm/audio/transcribers/

# Text
mv app/embedders/*.rb app/llm/text/embedders/

# Image
mv app/image_generators/*.rb app/llm/image/generators/
mv app/image_analyzers/*.rb app/llm/image/analyzers/
mv app/image_editors/*.rb app/llm/image/editors/
mv app/image_transformers/*.rb app/llm/image/transformers/
mv app/image_upscalers/*.rb app/llm/image/upscalers/
mv app/image_variators/*.rb app/llm/image/variators/
mv app/background_removers/*.rb app/llm/image/background_removers/
mv app/image_pipelines/*.rb app/llm/image/pipelines/
```

### Step 3: Add Namespace Wrappers

**Before (v0.5.0):**

```ruby
# app/agents/support_agent.rb
class SupportAgent < ApplicationAgent
  model "gpt-4o"

  def system_prompt
    "You are a helpful support agent."
  end
end
```

**After (v1.0.0):**

```ruby
# app/llm/agents/support_agent.rb
module Llm
  class SupportAgent < ApplicationAgent
    model "gpt-4o"

    def system_prompt
      "You are a helpful support agent."
    end
  end
end
```

**Embedder example:**

```ruby
# app/llm/text/embedders/document_embedder.rb
module Llm
  module Text
    class DocumentEmbedder < ApplicationEmbedder
      model "text-embedding-3-small"
    end
  end
end
```

**Speaker example:**

```ruby
# app/llm/audio/speakers/narrator_speaker.rb
module Llm
  module Audio
    class NarratorSpeaker < ApplicationSpeaker
      voice "nova"
    end
  end
end
```

### Step 4: Update References

Find and replace all class references in your codebase:

```ruby
# Before
SupportAgent.call(message: "Help!")
DocumentEmbedder.call(text: "Hello")

# After
Llm::SupportAgent.call(message: "Help!")
Llm::Text::DocumentEmbedder.call(text: "Hello")
```

Common locations to check:
- Controllers
- Services
- Jobs/Workers
- Rake tasks
- Initializers
- Tests/Specs

### Step 5: Clean Up Old Directories

```bash
rmdir app/agents app/embedders app/speakers app/transcribers \
      app/image_generators app/image_analyzers app/image_editors \
      app/image_transformers app/image_upscalers app/image_variators \
      app/background_removers app/image_pipelines 2>/dev/null
```

---

## DSL Changes

### cache → cache_for (Deprecated)

```ruby
# Before (deprecated, still works)
class MyAgent < ApplicationAgent
  cache 1.hour
end

# After (preferred)
class MyAgent < Llm::ApplicationAgent
  cache_for 1.hour
end
```

### New DSL Features

**Extended Thinking:**

```ruby
class ReasoningAgent < Llm::ApplicationAgent
  model "claude-sonnet-4-20250514"

  thinking do
    enabled true
    budget_tokens 10_000
  end
end
```

**Content Moderation:**

```ruby
class SafeAgent < Llm::ApplicationAgent
  moderation do
    enabled true
    on_violation :block  # or :warn, :log
  end
end
```

**Fallback Provider:**

```ruby
class ReliableAgent < Llm::ApplicationAgent
  reliability do
    fallback_provider "anthropic"  # New in v1.0.0
    fallback_models "gpt-4o-mini", "claude-3-5-sonnet"
  end
end
```

**Retryable Error Patterns:**

```ruby
class RobustAgent < Llm::ApplicationAgent
  reliability do
    retries max: 3, backoff: :exponential
    retryable_patterns [/timeout/i, /rate limit/i]  # New in v1.0.0
  end
end
```

---

## New Features Available After Migration

### Audio Agents

```ruby
# Speech-to-text
result = Llm::Audio::MeetingTranscriber.call(audio: audio_file)
puts result.content  # Transcribed text

# Text-to-speech
result = Llm::Audio::NarratorSpeaker.call(text: "Hello world")
result.content  # Audio data
```

### Image Operations

```ruby
# Generate image
result = Llm::Image::LogoGenerator.call(prompt: "A tech startup logo")

# Analyze image
result = Llm::Image::ProductAnalyzer.call(image: image_file)

# Multi-step pipeline
result = Llm::Image::ProductPipeline.call(prompt: "Product photo")
```

### Extended Thinking

```ruby
result = ReasoningAgent.call(question: "Complex problem...")
puts result.thinking  # Chain-of-thought reasoning
puts result.content   # Final answer
```

### Multi-Tenant API Keys

```ruby
# Configure per-tenant API keys
RubyLLM::Agents.configure do |config|
  config.multi_tenancy_enabled = true
  config.tenant_resolver = ->(context) { context[:organization_id] }
end
```

---

## Configuration Changes

### New Configuration Options

```ruby
# config/initializers/ruby_llm_agents.rb
RubyLLM::Agents.configure do |config|
  # Directory customization (new)
  config.root_directory = "llm"      # Default: "llm"
  config.root_namespace = "Llm"      # Default: "Llm"

  # Multi-tenancy (enhanced)
  config.multi_tenancy_enabled = true
  config.tenant_resolver = ->(context) { context[:tenant_id] }

  # All other options remain the same
  config.default_model = "gpt-4o"
  config.track_executions = true
  # ...
end
```

### Custom Root Directory

If you prefer a different root:

```ruby
config.root_directory = "ai"
config.root_namespace = "AI"
```

This creates `app/ai/` with namespace `AI::`:

```ruby
class AI::SupportAgent < AI::ApplicationAgent
  # ...
end
```

---

## Testing Migration

### Update Test File Locations

```
# Before
spec/agents/support_agent_spec.rb

# After
spec/llm/agents/support_agent_spec.rb
```

### Update Test Constants

```ruby
# Before
RSpec.describe SupportAgent do
  # ...
end

# After
RSpec.describe Llm::SupportAgent do
  # ...
end
```

### Example Test Update

```ruby
# spec/llm/agents/support_agent_spec.rb
require "rails_helper"

RSpec.describe Llm::SupportAgent do
  describe ".call" do
    it "returns a helpful response" do
      result = described_class.call(message: "Help me")
      expect(result).to be_success
    end
  end
end
```

---

## Troubleshooting

### Common Issues

#### "uninitialized constant SupportAgent"

**Cause:** Class reference wasn't updated to new namespace.

**Fix:** Update to `Llm::SupportAgent`

#### "Unable to autoload constant Llm::SupportAgent"

**Cause:** File not moved to correct location.

**Fix:** Ensure file is at `app/llm/agents/support_agent.rb`

#### "superclass mismatch for class SupportAgent"

**Cause:** Duplicate class definitions with different parent classes.

**Fix:** Remove old file from `app/agents/`

#### Tests failing with NameError

**Cause:** Test files reference old class names.

**Fix:** Update `RSpec.describe SupportAgent` to `RSpec.describe Llm::SupportAgent`

#### "undefined method 'cache' for class"

**Cause:** `cache` is deprecated.

**Fix:** Use `cache_for` instead

### Verification Checklist

After migration, verify:

- [ ] `rails console` loads without errors
- [ ] `Llm::ApplicationAgent` is accessible
- [ ] All your agents are accessible with new namespaces
- [ ] Test suite passes
- [ ] Application starts without errors
- [ ] Dashboard shows all agents correctly

### Getting Help

If you encounter issues:

1. Check the [Troubleshooting](Troubleshooting) page
2. Search [GitHub Issues](https://github.com/adham90/ruby_llm-agents/issues)
3. Open a new issue with:
   - Error message
   - Ruby/Rails versions
   - Steps to reproduce

---

## Related Pages

- [Getting Started](Getting-Started) - Fresh installation guide
- [Generators](Generators) - All available generators
- [Configuration](Configuration) - Configuration options
- [Agent DSL](Agent-DSL) - Agent configuration reference
- [Audio](Audio) - Audio agent documentation
- [Image Operations](Image-Generation) - Image agent documentation
