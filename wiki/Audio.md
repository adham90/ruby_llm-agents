# Audio Support

RubyLLM::Agents provides two base classes for audio operations:

- **Transcriber** - Audio-to-text (speech recognition)
- **Speaker** - Text-to-audio (text-to-speech / TTS)

## Table of Contents

- [Transcription (Audio → Text)](#transcription-audio--text)
  - [Quick Start](#transcriber-quick-start)
  - [Transcriber DSL](#transcriber-dsl)
  - [TranscriptionResult](#transcriptionresult)
  - [Subtitle Generation](#subtitle-generation)
- [Text-to-Speech (Text → Audio)](#text-to-speech-text--audio)
  - [Quick Start](#speaker-quick-start)
  - [Speaker DSL](#speaker-dsl)
  - [SpeechResult](#speechresult)
  - [Streaming Audio](#streaming-audio)
  - [ElevenLabs Configuration](#elevenlabs-configuration)
- [Generators](#generators)
- [Configuration](#configuration)
- [Cost Tracking](#cost-tracking)

---

## Transcription (Audio → Text)

Convert audio files to text using speech recognition models.

### Transcriber Quick Start

```ruby
# Generate a transcriber
rails generate ruby_llm_agents:transcriber meeting

# app/agents/audio/meeting_transcriber.rb
class MeetingTranscriber < ApplicationTranscriber
  model "whisper-1"
  language "en"
end

# Usage
result = Audio::MeetingTranscriber.call(audio: "meeting.mp3")
result.text           # "Hello, welcome to the meeting..."
result.audio_duration # 120.5 (seconds)
result.total_cost     # 0.012
```

### Transcriber DSL

```ruby
class MyTranscriber < ApplicationTranscriber
  # Model selection
  model "whisper-1"              # Default transcription model
  # Alternatives: "gpt-4o-transcribe", "gpt-4o-mini-transcribe"

  # Language settings
  language "en"                   # ISO 639-1 code (nil = auto-detect)

  # Output format
  output_format :text             # :text, :json, :srt, :vtt

  # Timestamp granularity
  include_timestamps :segment     # :none, :segment, :word

  # Caching
  cache_for 30.days               # Enable caching

  # Optional: Provide context for better accuracy
  def prompt
    "Technical discussion about Ruby programming"
  end

  # Optional: Post-process transcription
  def postprocess_text(text)
    text
      .gsub(/\bum\b/i, '')       # Remove filler words
      .gsub(/\buh\b/i, '')
      .squeeze(' ')
  end
end
```

### Input Sources

```ruby
# From file path
result = Audio::MeetingTranscriber.call(audio: "meeting.mp3")

# From URL
result = Audio::MeetingTranscriber.call(audio: "https://example.com/audio.mp3")

# From File object
result = Audio::MeetingTranscriber.call(audio: File.open("meeting.mp3"))

# From binary data with format hint
result = Audio::MeetingTranscriber.call(audio: audio_blob, format: :mp3)
```

### Reliability Configuration

```ruby
class ReliableTranscriber < ApplicationTranscriber
  model "gpt-4o-transcribe"

  reliability do
    retry_on_failure max_attempts: 3
  end

  fallback_models "whisper-1", "gpt-4o-mini-transcribe"
end
```

### TranscriptionResult

```ruby
result = Audio::MeetingTranscriber.call(audio: "meeting.mp3")

# Text content
result.text              # Full transcription text
result.segments          # Array of segments with timestamps
result.words             # Array of words with timestamps (if requested)

# Audio metadata
result.audio_duration    # Duration in seconds
result.audio_format      # Detected format
result.language          # Requested language
result.detected_language # Auto-detected language

# Execution metadata
result.model_id          # Model used
result.duration_ms       # Processing time
result.total_cost        # Cost in USD
result.started_at        # Execution start time
result.completed_at      # Execution end time
result.tenant_id         # Multi-tenant identifier

# Status
result.success?          # true if no error
result.error?            # true if failed

# Subtitle generation
result.srt               # SRT subtitle format
result.vtt               # VTT subtitle format

# Analysis helpers
result.words_per_minute        # Speaking rate
result.segment_at(30.5)        # Find segment at timestamp
result.text_between(10, 60)    # Get text in time range
```

### Subtitle Generation

```ruby
class SubtitleTranscriber < ApplicationTranscriber
  model "whisper-1"
  include_timestamps :segment
end

result = Audio::SubtitleTranscriber.call(audio: "video.mp4")

# Save as SRT (for video players)
File.write("captions.srt", result.srt)

# Save as VTT (for web video)
File.write("captions.vtt", result.vtt)
```

**SRT Output:**
```
1
00:00:00,000 --> 00:00:02,500
Hello everyone.

2
00:00:02,500 --> 00:00:05,000
Welcome to the meeting.
```

**VTT Output:**
```
WEBVTT

00:00:00.000 --> 00:00:02.500
Hello everyone.

00:00:02.500 --> 00:00:05.000
Welcome to the meeting.
```

---

## Text-to-Speech (Text → Audio)

Generate natural speech audio from text.

### Speaker Quick Start

```ruby
# Generate a speaker
rails generate ruby_llm_agents:speaker narrator

# app/agents/audio/narrator_speaker.rb
class NarratorSpeaker < ApplicationSpeaker
  provider :openai
  model "tts-1"
  voice "nova"
end

# Usage
result = Audio::NarratorSpeaker.call(text: "Hello, world!")
result.audio          # Binary audio data
result.save_to("output.mp3")
```

### Speaker DSL

```ruby
class MyNarrator < ApplicationSpeaker
  # Provider selection
  provider :openai              # :openai, :elevenlabs

  # Model and voice
  model "tts-1-hd"              # "tts-1" for faster/cheaper
  voice "nova"                  # Voice name
  # OpenAI voices: alloy, echo, fable, nova, onyx, shimmer

  # Voice ID (ElevenLabs)
  voice_id "21m00Tcm..."        # Voice ID for cloned voices

  # Audio settings
  speed 1.0                     # Speech speed (0.25-4.0 for OpenAI)
  output_format :mp3            # :mp3, :wav, :ogg, :flac

  # Streaming
  streaming true                # Enable streaming mode

  # Caching
  cache_for 7.days              # Enable caching

  # Custom pronunciation lexicon
  lexicon do
    pronounce "API", "A P I"
    pronounce "SQL", "sequel"
    pronounce "RubyLLM", "ruby L L M"
    pronounce "nginx", "engine-X"
  end
end
```

### SpeechResult

```ruby
result = Audio::ArticleNarrator.call(text: "Hello!")

# Audio data
result.audio          # Binary audio data
result.save_to(path)  # Save to file
result.to_base64      # Base64 encoded
result.to_data_uri    # Data URI for web embedding

# Metadata
result.duration       # Audio duration (seconds)
result.format         # Output format (:mp3, :wav, etc.)
result.file_size      # Size in bytes
result.characters     # Input character count

# Provider info
result.provider       # :openai, :elevenlabs
result.model_id       # Model used
result.voice_id       # Voice identifier
result.voice_name     # Voice name

# Execution
result.duration_ms    # Processing time
result.total_cost     # Cost in USD
result.started_at     # Execution start time
result.completed_at   # Execution end time
result.tenant_id      # Multi-tenant identifier
result.success?       # true if no error
```

### Streaming Audio

```ruby
class StreamingNarrator < ApplicationSpeaker
  provider :elevenlabs
  voice "Rachel"
  streaming true
end

# Stream to audio player
Audio::StreamingNarrator.stream(text: "Long article...") do |chunk|
  audio_player.play(chunk.audio)
end

# Force streaming on any speaker
Audio::ArticleNarrator.stream(text: "Hello!") do |chunk|
  buffer << chunk.audio
end
```

### ElevenLabs Configuration

```ruby
class PremiumNarrator < ApplicationSpeaker
  provider :elevenlabs
  model "eleven_multilingual_v2"
  voice_id "21m00Tcm4TlvDq8ikWAM"

  # Voice settings specific to ElevenLabs
  voice_settings do
    stability 0.5            # 0-1: Lower = more expressive
    similarity_boost 0.75    # 0-1: Higher = closer to original voice
    style 0.5                # 0-1: Style exaggeration
    speaker_boost true       # Enhance speaker clarity
  end
end
```

### Reliability Configuration

```ruby
class ReliableSpeaker < ApplicationSpeaker
  provider :elevenlabs
  voice "Rachel"

  reliability do
    retry_on_failure max_attempts: 3
  end

  fallback_models "tts-1-hd", "tts-1"
end
```

---

## Generators

### Generate a Transcriber

```bash
# Basic transcriber
rails generate ruby_llm_agents:transcriber meeting

# With options
rails generate ruby_llm_agents:transcriber meeting --model gpt-4o-transcribe
rails generate ruby_llm_agents:transcriber meeting --language es
rails generate ruby_llm_agents:transcriber meeting --output-format srt
rails generate ruby_llm_agents:transcriber meeting --cache 30.days
```

This creates:
- `app/agents/audio/application_transcriber.rb` (if not exists)
- `app/agents/audio/meeting_transcriber.rb`

### Generate a Speaker

```bash
# Basic speaker
rails generate ruby_llm_agents:speaker narrator

# With options
rails generate ruby_llm_agents:speaker narrator --provider elevenlabs
rails generate ruby_llm_agents:speaker narrator --voice alloy
rails generate ruby_llm_agents:speaker narrator --speed 1.25
rails generate ruby_llm_agents:speaker narrator --format wav
rails generate ruby_llm_agents:speaker narrator --cache 7.days
```

This creates:
- `app/agents/audio/application_speaker.rb` (if not exists)
- `app/agents/audio/narrator_speaker.rb`

---

## Configuration

### Global Defaults

```ruby
# config/initializers/ruby_llm_agents.rb
RubyLLM::Agents.configure do |config|
  # Transcription defaults
  config.default_transcription_model = "whisper-1"
  config.track_transcriptions = true

  # TTS defaults
  config.default_tts_provider = :openai
  config.default_tts_model = "tts-1"
  config.default_tts_voice = "nova"
  config.track_speech = true
end
```

### Supported Models

#### Transcription Models

| Provider | Model | Notes |
|----------|-------|-------|
| OpenAI | `whisper-1` | Default, most reliable |
| OpenAI | `gpt-4o-transcribe` | Faster, better accuracy |
| OpenAI | `gpt-4o-mini-transcribe` | Budget option |

#### TTS Models

| Provider | Models | Voices |
|----------|--------|--------|
| OpenAI | `tts-1`, `tts-1-hd` | alloy, echo, fable, nova, onyx, shimmer |
| ElevenLabs | `eleven_monolingual_v1`, `eleven_multilingual_v2` | Various voice IDs |

---

## Cost Tracking

### Transcription Costs

| Model | Price |
|-------|-------|
| whisper-1 | $0.006 / minute |
| gpt-4o-transcribe | ~$0.01 / minute |
| gpt-4o-mini-transcribe | ~$0.005 / minute |

Transcription costs are calculated based on audio duration.

### TTS Costs

| Provider | Model | Price |
|----------|-------|-------|
| OpenAI | tts-1 | $0.015 / 1K chars |
| OpenAI | tts-1-hd | $0.030 / 1K chars |
| ElevenLabs | Standard | $0.30 / 1K chars |

TTS costs are calculated based on character count.

---

## Multi-Tenancy

Audio operations fully support multi-tenancy:

```ruby
# Using resolver
result = Audio::MeetingTranscriber.call(audio: "meeting.mp3")
# Automatically uses Current.tenant if configured

# Explicit tenant
result = Audio::MeetingTranscriber.call(
  audio: "meeting.mp3",
  tenant: "acme_corp"
)

# Tenant with budget limits
result = Audio::ArticleNarrator.call(
  text: "Hello world",
  tenant: {
    id: "acme_corp",
    daily_limit: 50.0,
    enforcement: :hard
  }
)
```

---

## Examples

### Meeting Transcription

```ruby
class MeetingTranscriber < ApplicationTranscriber
  model "whisper-1"
  language "en"
  include_timestamps :segment

  def prompt
    "Business meeting with technical discussions about software"
  end

  def postprocess_text(text)
    text
      .gsub(/\bum\b/i, '')
      .gsub(/\buh\b/i, '')
      .squeeze(' ')
  end
end

result = Audio::MeetingTranscriber.call(audio: "meeting.mp3")
puts result.text
puts "Duration: #{result.audio_duration} seconds"
puts "Cost: $#{result.total_cost}"
```

### Article Narration

```ruby
class ArticleNarrator < ApplicationSpeaker
  provider :openai
  model "tts-1-hd"
  voice "nova"
  speed 1.1

  lexicon do
    pronounce "API", "A P I"
    pronounce "JSON", "jay-son"
  end
end

result = Audio::ArticleNarrator.call(text: article_content)
result.save_to("article_audio.mp3")
puts "Duration: #{result.duration} seconds"
puts "Cost: $#{result.total_cost}"
```

### Voice Assistant Pipeline

```ruby
class VoiceAssistant
  def process_query(audio_file)
    # 1. Transcribe user's voice
    transcription = Audio::QueryTranscriber.call(audio: audio_file)

    # 2. Process with AI agent
    response = LLM::AssistantAgent.call(query: transcription.text)

    # 3. Convert response to speech
    speech = Audio::ResponseSpeaker.call(text: response.content)

    {
      transcription: transcription,
      response: response,
      speech: speech,
      total_cost: transcription.total_cost + response.total_cost + speech.total_cost
    }
  end
end
```
