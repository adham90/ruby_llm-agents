# Plan 08: RubyLLM Feature Parity

**Status:** Draft
**Created:** 2025-01-20
**RubyLLM Version Reviewed:** 1.11.0

## Overview

This plan addresses feature gaps identified by comparing ruby_llm-agents against recent RubyLLM releases (v1.7.0 - v1.11.0). The goal is to ensure our gem exposes all relevant RubyLLM capabilities through our agent DSL.

---

## Gap 1: Transcription Diarization Support

**RubyLLM Version:** 1.9.0
**Priority:** High
**Effort:** Low

### Background

RubyLLM v1.9.0 introduced one-liner transcription API with diarization (speaker identification). Our `Transcriber` class doesn't expose this feature.

### Implementation

#### 1.1 Add DSL Methods

```ruby
# lib/ruby_llm/agents/audio/transcriber/dsl.rb

# Sets or returns whether to enable speaker diarization
#
# @param value [Boolean, nil] Whether to identify different speakers
# @return [Boolean] The current diarization setting
# @example
#   diarization true
def diarization(value = nil)
  @diarization = value unless value.nil?
  @diarization || inherited_or_default(:diarization, false)
end

# Alias for clarity
alias_method :speaker_identification, :diarization
```

#### 1.2 Update Execution to Pass Diarization Option

```ruby
# lib/ruby_llm/agents/audio/transcriber/execution.rb

def build_transcription_options
  opts = {}
  opts[:model] = effective_model
  opts[:language] = effective_language if effective_language
  opts[:response_format] = self.class.output_format
  opts[:timestamp_granularities] = timestamp_granularities
  opts[:diarization] = self.class.diarization if self.class.diarization
  opts
end
```

#### 1.3 Update TranscriptionResult

```ruby
# lib/ruby_llm/agents/results/transcription_result.rb

# Add speaker segments accessor
def speakers
  @raw_result.speakers if @raw_result.respond_to?(:speakers)
end

def speaker_segments
  @raw_result.speaker_segments if @raw_result.respond_to?(:speaker_segments)
end
```

#### 1.4 Example Usage

```ruby
class MeetingTranscriber < RubyLLM::Agents::Transcriber
  model 'whisper-1'
  diarization true
  include_timestamps :segment
end

result = MeetingTranscriber.call(audio: "meeting.mp3")
result.speakers        # => ["Speaker 1", "Speaker 2"]
result.speaker_segments # => [{speaker: "Speaker 1", text: "...", start: 0.0, end: 2.5}, ...]
```

---

## Gap 2: Video File Support for Multimodal Analysis

**RubyLLM Version:** 1.8.0
**Priority:** Medium
**Effort:** Medium

### Background

RubyLLM v1.8.0 added video file support for multimodal models. Our `ImageAnalyzer` is named and documented for images only, but the underlying RubyLLM API supports video.

### Implementation Options

**Option A: Expand ImageAnalyzer (Recommended)**
- Rename internally but keep backward compatibility
- Update documentation to mention video support
- Add video-specific options

**Option B: Create Separate VideoAnalyzer**
- New class specifically for video
- More explicit but adds maintenance burden

### Recommended Approach: Option A

#### 2.1 Update ImageAnalyzer Documentation and DSL

```ruby
# lib/ruby_llm/agents/image/analyzer.rb

# Image and video analyzer for understanding visual content
#
# Analyzes images and videos using vision models to extract captions, tags,
# descriptions, detected objects, and color information.
#
# @example Analyze an image
#   result = RubyLLM::Agents::ImageAnalyzer.call(image: "photo.jpg")
#
# @example Analyze a video
#   result = RubyLLM::Agents::ImageAnalyzer.call(image: "video.mp4")
#   result.frames        # Frame-by-frame analysis (if supported)
#   result.description   # Overall video description
```

#### 2.2 Add Video-Specific DSL Options

```ruby
# lib/ruby_llm/agents/image/analyzer/dsl.rb

# Sets the number of frames to sample from video
#
# @param value [Integer, nil] Number of frames to analyze
# @return [Integer] Current frame sample count
# @example
#   sample_frames 10
def sample_frames(value = nil)
  @sample_frames = value if value
  @sample_frames || inherited_or_default(:sample_frames, nil)
end

# Sets whether to analyze audio track in video
#
# @param value [Boolean, nil] Whether to include audio analysis
# @return [Boolean] Current setting
def analyze_audio(value = nil)
  @analyze_audio = value unless value.nil?
  @analyze_audio || inherited_or_default(:analyze_audio, false)
end
```

#### 2.3 Update Result Class

```ruby
# lib/ruby_llm/agents/results/image_analysis_result.rb

# Returns frame-by-frame analysis for video input
def frames
  @data[:frames]
end

# Returns video duration if applicable
def duration
  @data[:duration]
end

# Returns whether input was a video
def video?
  @data[:media_type] == :video
end
```

#### 2.4 Create Alias for Clarity

```ruby
# lib/ruby_llm/agents.rb

module RubyLLM
  module Agents
    # Alias for semantic clarity when working with video
    MediaAnalyzer = ImageAnalyzer
  end
end
```

---

## Gap 3: Anthropic Prompt Caching Support

**RubyLLM Version:** 1.9.0
**Priority:** Medium
**Effort:** Medium

### Background

RubyLLM v1.9.0 added raw content blocks enabling Anthropic prompt caching. This is different from our response caching - it caches large system prompts at the provider level to reduce costs and latency.

### Implementation

#### 3.1 Add DSL for Prompt Caching

```ruby
# lib/ruby_llm/agents/core/base/dsl.rb

# Enables Anthropic prompt caching for the system prompt
#
# When enabled, large system prompts are cached at the provider level,
# reducing costs and latency for subsequent calls with the same prompt.
# Only effective with Anthropic/Claude models.
#
# @param value [Boolean, nil] Whether to enable prompt caching
# @return [Boolean] The current setting
# @example
#   cache_system_prompt true
def cache_system_prompt(value = nil)
  @cache_system_prompt = value unless value.nil?
  @cache_system_prompt || inherited_or_default(:cache_system_prompt, false)
end

# Alias matching RubyLLM terminology
alias_method :prompt_caching, :cache_system_prompt
```

#### 3.2 Update Client Building

```ruby
# lib/ruby_llm/agents/core/base/execution.rb

def build_client
  chat = RubyLLM.chat(model: @model)

  # Apply system prompt with optional caching
  if system_prompt
    if self.class.cache_system_prompt
      chat.with_instructions(system_prompt, cache: true)
    else
      chat.with_instructions(system_prompt)
    end
  end

  # ... rest of client building
end
```

#### 3.3 Add Configuration Default

```ruby
# lib/ruby_llm/agents/core/configuration.rb

# Default setting for Anthropic prompt caching
# @return [Boolean]
attr_accessor :default_cache_system_prompt

def initialize
  # ...existing defaults...
  @default_cache_system_prompt = false
end
```

#### 3.4 Example Usage

```ruby
class LargeContextAgent < ApplicationAgent
  model "claude-sonnet-4-20250514"
  cache_system_prompt true  # Enable Anthropic prompt caching

  def system_prompt
    # Large system prompt that benefits from caching
    <<~PROMPT
      You are an expert assistant with access to the following knowledge base:
      #{load_large_knowledge_base}
    PROMPT
  end
end
```

---

## Gap 4: Default Model Updates

**RubyLLM Version:** 1.9.2
**Priority:** Low
**Effort:** Low

### Background

RubyLLM v1.9.2 made Imagen 4.0 the default for image generation. We should review and update our default models to match current best practices.

### Implementation

#### 4.1 Update Configuration Defaults

```ruby
# lib/ruby_llm/agents/core/configuration.rb

def initialize
  @default_model = "gpt-4o"
  @default_temperature = 0.7
  @default_timeout = 120
  @default_streaming = false
  @default_thinking = nil
  @default_tools = []
  @default_retries = { max: 0, backoff: :exponential, base: 0.4, max_delay: 8.0 }
  @default_fallback_models = []
  @default_total_timeout = nil

  # Audio defaults
  @default_transcription_model = "whisper-1"
  @default_speech_model = "tts-1"
  @default_speech_voice = "alloy"

  # Image defaults - Updated for Imagen 4.0
  @default_image_model = "imagen-4.0"  # Was: "dall-e-3"
  @default_image_size = "1024x1024"
  @default_image_quality = "standard"

  # Moderation default
  @default_moderation_model = "omni-moderation-latest"

  # Embedding default
  @default_embedding_model = "text-embedding-3-small"
end
```

#### 4.2 Document Model Options

Add a section to README or create `docs/models.md` listing recommended models for each agent type.

---

## Gap 5: xAI/Grok Model Documentation

**RubyLLM Version:** 1.11.0
**Priority:** Low
**Effort:** Low

### Background

RubyLLM v1.11.0 added xAI as a first-class provider with Grok model support. While this works automatically, we should document it.

### Implementation

#### 5.1 Add to Documentation

```markdown
## Supported Providers

ruby_llm-agents supports all providers available in RubyLLM:

- **OpenAI**: GPT-4o, GPT-4, GPT-3.5, DALL-E, Whisper, TTS
- **Anthropic**: Claude 4 Opus, Claude 4 Sonnet, Claude 3.5 Haiku
- **Google**: Gemini 2.5/3 Pro/Flash, Imagen 4.0
- **AWS Bedrock**: All supported models
- **xAI**: Grok models (v1.11.0+)
- **Mistral**: Mistral Large, Magistral
- **DeepSeek**: DeepSeek models

### Using xAI/Grok

```ruby
class GrokAgent < ApplicationAgent
  model "grok-2"  # or "grok-beta"

  def user_prompt
    "Analyze this with your unique perspective: #{query}"
  end
end
```
```

#### 5.2 Add Integration Test (Optional)

```ruby
# spec/integration/providers/xai_spec.rb

RSpec.describe "xAI Integration", :integration do
  it "works with Grok models" do
    agent_class = Class.new(RubyLLM::Agents::Base) do
      model "grok-2"
      param :query, required: true

      def user_prompt
        query
      end
    end

    result = agent_class.call(query: "Hello")
    expect(result).to be_present
  end
end
```

---

## Implementation Order

| Phase | Gap | Effort | Dependencies |
|-------|-----|--------|--------------|
| 1 | Gap 1: Diarization | Low | None |
| 2 | Gap 4: Default Models | Low | None |
| 3 | Gap 5: xAI Documentation | Low | None |
| 4 | Gap 3: Prompt Caching | Medium | None |
| 5 | Gap 2: Video Support | Medium | None |

---

## Testing Strategy

### Unit Tests
- DSL method tests for new options
- Result class tests for new accessors
- Configuration default tests

### Integration Tests
- Diarization with real audio (if API available)
- Video analysis with sample video
- Prompt caching cost verification (manual)

### Documentation
- Update README with new features
- Add examples for each new capability
- Update YARD documentation

---

## Migration Notes

All changes are **additive** and **backward compatible**:
- Existing agents continue to work unchanged
- New DSL methods have sensible defaults
- No breaking changes to public API

---

## Open Questions

1. Should `ImageAnalyzer` be renamed to `MediaAnalyzer` with `ImageAnalyzer` as alias, or keep current name?
2. Should we add a global configuration for prompt caching, or keep it opt-in per agent?
3. Do we need explicit xAI configuration helpers, or is passthrough to RubyLLM sufficient?

---

## References

- [RubyLLM Releases](https://github.com/crmne/ruby_llm/releases)
- [RubyLLM v1.11.0 - xAI Support](https://github.com/crmne/ruby_llm/releases/tag/v1.11.0)
- [RubyLLM v1.10.0 - Extended Thinking](https://github.com/crmne/ruby_llm/releases/tag/v1.10.0)
- [RubyLLM v1.9.0 - Schema DSL & Diarization](https://github.com/crmne/ruby_llm/releases/tag/v1.9.0)
- [RubyLLM v1.8.0 - Video & Moderation](https://github.com/crmne/ruby_llm/releases/tag/v1.8.0)
