# Audio Support Implementation Plan

## Overview

Add audio capabilities to ruby_llm-agents with two base classes:

1. **`Transcriber`** - Audio-to-text (speech recognition)
2. **`Speaker`** - Text-to-audio (text-to-speech / TTS)

These enable voice assistants, podcast processing, audiobook generation, accessibility features, and more while maintaining the gem's execution tracking, budget controls, and multi-tenancy features.

## Why Separate Base Classes?

Audio operations are fundamentally different from chat agents:

| Aspect | Agent | Transcriber | Speaker |
|--------|-------|-------------|---------|
| Input | Text | Audio file | Text |
| Output | Text | Text | Audio file |
| Streaming | Token-by-token | ❌ | Chunk-by-chunk |
| Tools | ✅ | ❌ | ❌ |
| Schema | ✅ | ❌ | ❌ |

However, they still benefit from:
- Execution tracking (cost monitoring)
- Budget controls (audio operations cost money)
- Multi-tenancy (per-tenant API keys and limits)
- Reliability (retries, fallbacks)
- Caching (don't re-process same content)

---

## Part 1: Transcriber (Audio → Text)

### Supported Models

| Provider | Model | Features | Notes |
|----------|-------|----------|-------|
| OpenAI | `whisper-1` | General purpose | Default, most reliable |
| OpenAI | `gpt-4o-transcribe` | Faster, better accuracy | Good for technical content |
| OpenAI | `gpt-4o-mini-transcribe` | Fastest, lowest cost | Budget option |
| OpenAI | `gpt-4o-transcribe-diarize` | Speaker identification | Identifies who's speaking |
| Google | `gemini-2.5-flash` | Multimodal | Also handles video |
| Google | `gemini-2.5-pro` | Multimodal, higher quality | Premium option |

### API Design

#### Basic Usage

```ruby
class MeetingTranscriber < RubyLLM::Agents::Transcriber
  model 'whisper-1'
end

# From file path
result = MeetingTranscriber.call(audio: "meeting.mp3")
result.text           # "Hello everyone, welcome to the meeting..."
result.model_id       # "whisper-1"
result.duration_ms    # 2345
result.input_tokens   # Audio doesn't use tokens, but track for consistency
result.total_cost     # 0.006
result.audio_duration # 60.5 (seconds of audio)

# From file object
result = MeetingTranscriber.call(audio: File.open("meeting.mp3"))

# From URL
result = MeetingTranscriber.call(audio: "https://example.com/meeting.mp3")

# From binary data
result = MeetingTranscriber.call(audio: audio_blob, format: :mp3)
```

#### With Configuration Options

```ruby
class SpanishPodcastTranscriber < RubyLLM::Agents::Transcriber
  model 'gpt-4o-transcribe'
  language 'es'                    # ISO 639-1 language code

  # Context for better accuracy
  def prompt
    "Podcast sobre tecnología, programación Ruby, inteligencia artificial"
  end
end
```

#### Speaker Diarization

```ruby
class InterviewTranscriber < RubyLLM::Agents::Transcriber
  model 'gpt-4o-transcribe-diarize'
  language 'en'

  # Speaker identification
  diarization do
    speakers 'Interviewer', 'Guest'
    reference_samples(
      'Interviewer' => 'interviewer_sample.wav',
      'Guest' => 'guest_sample.wav'
    )
  end
end

result = InterviewTranscriber.call(audio: "interview.mp3")
result.text
# "Interviewer: Welcome to the show.
#  Guest: Thanks for having me.
#  Interviewer: Let's dive in..."

result.segments
# [
#   { speaker: "Interviewer", start: 0.0, end: 2.5, text: "Welcome to the show." },
#   { speaker: "Guest", start: 2.5, end: 4.8, text: "Thanks for having me." },
#   ...
# ]

result.speakers          # ["Interviewer", "Guest"]
result.speaker_segments  # Grouped by speaker
```

#### Output Formats

```ruby
class SubtitleTranscriber < RubyLLM::Agents::Transcriber
  model 'whisper-1'

  # Output format options
  output_format :srt           # or :vtt, :json, :text, :verbose_json
  include_timestamps :segment  # or :word, :none
end

result = SubtitleTranscriber.call(audio: "video.mp4")

result.text          # Plain text
result.srt           # SRT formatted subtitles
result.vtt           # WebVTT formatted subtitles
result.segments      # Array of timed segments
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

#### Long Audio Handling (Chunking)

```ruby
class LongFormTranscriber < RubyLLM::Agents::Transcriber
  model 'whisper-1'

  # Auto-split long audio files
  chunking do
    enabled true
    max_duration 600        # 10 minutes per chunk
    overlap 5               # 5 second overlap for continuity
    parallel true           # Process chunks in parallel
  end
end

# 2-hour podcast automatically split and processed
result = LongFormTranscriber.call(audio: "podcast_ep42.mp3")
result.text              # Complete transcription
result.chunks            # Individual chunk results
result.total_audio_duration  # 7200 (seconds)
```

#### Preprocessing Hooks

```ruby
class CleanAudioTranscriber < RubyLLM::Agents::Transcriber
  model 'whisper-1'

  # Audio preprocessing before transcription
  preprocess do
    normalize_volume true      # Normalize audio levels
    remove_silence true        # Trim silence at start/end
    noise_reduction :light     # :none, :light, :aggressive
    convert_to :mp3            # Ensure compatible format
    target_sample_rate 16000   # Optimal for Whisper
  end
end
```

#### Post-processing

```ruby
class CleanTranscriber < RubyLLM::Agents::Transcriber
  model 'whisper-1'

  postprocess do
    normalize_punctuation true     # Fix punctuation
    remove_filler_words true       # Remove "um", "uh", etc.
    capitalize_sentences true      # Proper capitalization
    format_numbers true            # "twenty three" → "23"
  end

  # Custom post-processing
  def postprocess_text(text)
    text
      .gsub(/\bRuby L L M\b/i, 'RubyLLM')  # Fix common misrecognitions
      .gsub(/\bopen A I\b/i, 'OpenAI')
  end
end
```

#### PII Redaction

```ruby
class SecureTranscriber < RubyLLM::Agents::Transcriber
  model 'whisper-1'

  # Automatically redact sensitive information
  redaction do
    enabled true
    types :phone, :email, :ssn, :credit_card, :address
    replacement '[REDACTED]'    # or :mask, :hash
  end
end

result = SecureTranscriber.call(audio: "support_call.mp3")
result.text
# "Please call me at [REDACTED] or email [REDACTED]"

result.redactions
# [
#   { type: :phone, original: "555-123-4567", position: 16..27 },
#   { type: :email, original: "john@example.com", position: 38..53 }
# ]

result.unredacted_text  # Only available if explicitly requested and authorized
```

#### Vocabulary Hints

```ruby
class TechnicalTranscriber < RubyLLM::Agents::Transcriber
  model 'gpt-4o-transcribe'

  # Boost recognition of specific terms
  vocabulary do
    terms 'RubyLLM', 'OpenAI', 'Anthropic', 'LangChain'
    acronyms 'API', 'SDK', 'LLM', 'RAG', 'RLHF'
    names 'Matz', 'DHH', 'Tenderlove'
  end

  # Or via prompt method
  def prompt
    "Technical discussion about Ruby programming. " \
    "Common terms: RubyLLM, OpenAI, Anthropic, API, SDK"
  end
end
```

#### Reliability

```ruby
class ReliableTranscriber < RubyLLM::Agents::Transcriber
  model 'gpt-4o-transcribe'

  reliability do
    retries max: 3, backoff: :exponential
    fallback_models 'whisper-1', 'gpt-4o-mini-transcribe'
    total_timeout 300           # 5 minutes for long files
    circuit_breaker errors: 5, within: 60
  end
end
```

#### Caching

```ruby
class CachedTranscriber < RubyLLM::Agents::Transcriber
  model 'whisper-1'

  cache_for 30.days

  # Cache key includes: file hash + model + language + config
end

# First call: transcribes and caches
CachedTranscriber.call(audio: "meeting.mp3")  # $0.05

# Second call: returns cached result
CachedTranscriber.call(audio: "meeting.mp3")  # $0.00
```

### TranscriptionResult Object

```ruby
class TranscriptionResult
  # Content
  attr_reader :text              # Full transcription text
  attr_reader :segments          # Array of timed segments
  attr_reader :words             # Array of timed words (if available)

  # Formatted outputs
  attr_reader :srt               # SRT subtitle format
  attr_reader :vtt               # WebVTT subtitle format

  # Speaker diarization
  attr_reader :speakers          # Identified speakers
  attr_reader :speaker_segments  # Segments grouped by speaker

  # Audio metadata
  attr_reader :audio_duration    # Duration in seconds
  attr_reader :audio_format      # Detected format
  attr_reader :audio_channels    # Mono/stereo
  attr_reader :audio_sample_rate # Sample rate

  # Language
  attr_reader :detected_language # Auto-detected language
  attr_reader :language_confidence

  # Timing
  attr_reader :duration_ms       # Processing time
  attr_reader :started_at
  attr_reader :completed_at

  # Cost & usage
  attr_reader :model_id
  attr_reader :total_cost
  attr_reader :audio_minutes     # Billable audio minutes

  # Quality
  attr_reader :confidence        # Overall confidence score
  attr_reader :word_confidences  # Per-word confidence

  # Redaction
  attr_reader :redactions        # Redacted items
  attr_reader :redacted?

  # Status
  attr_reader :status            # :success, :partial, :failed
  attr_reader :chunks            # For chunked processing

  # Helpers
  def success?
  def words_per_minute
  def segment_at(timestamp)
  def text_between(start_time, end_time)
end
```

---

## Part 2: Speaker (Text → Audio)

### Supported Providers & Models

| Provider | Models | Voices | Cloning | Streaming | Notes |
|----------|--------|--------|---------|-----------|-------|
| **ElevenLabs** | eleven_multilingual_v2, eleven_turbo_v2 | 1000+ | ✅ | ✅ | Best quality |
| **OpenAI** | tts-1, tts-1-hd | 6 (alloy, echo, fable, onyx, nova, shimmer) | ❌ | ✅ | Simple, reliable |
| **Google** | Standard, WaveNet, Neural2 | 200+ | ❌ | ✅ | Many languages |
| **Amazon Polly** | Standard, Neural | 60+ | ❌ | ✅ | AWS integration |

### API Design

#### Basic Usage

```ruby
class ArticleNarrator < RubyLLM::Agents::Speaker
  provider :openai
  model 'tts-1-hd'
  voice 'nova'
end

result = ArticleNarrator.call(text: "Welcome to my blog post about Ruby...")
result.audio         # Binary audio data
result.audio_url     # URL if saved to storage
result.duration      # 45.2 seconds
result.characters    # 1250 (for billing)
result.total_cost    # 0.019
result.format        # :mp3
```

#### ElevenLabs Configuration

```ruby
class PremiumNarrator < RubyLLM::Agents::Speaker
  provider :elevenlabs
  model 'eleven_multilingual_v2'
  voice 'Rachel'

  # Voice settings (ElevenLabs specific)
  voice_settings do
    stability 0.5            # 0-1: Lower = more expressive
    similarity_boost 0.75    # 0-1: Higher = closer to original voice
    style 0.5                # 0-1: Style exaggeration
    speaker_boost true       # Enhance speaker clarity
  end

  # Output settings
  output_format :mp3_44100_128   # Quality preset
  # Options: mp3_22050_32, mp3_44100_64, mp3_44100_128, mp3_44100_192
  #          pcm_16000, pcm_22050, pcm_24000, pcm_44100
  #          ulaw_8000 (for telephony)
end
```

#### OpenAI Configuration

```ruby
class SimpleNarrator < RubyLLM::Agents::Speaker
  provider :openai
  model 'tts-1-hd'           # or 'tts-1' for faster/cheaper
  voice 'nova'               # alloy, echo, fable, onyx, nova, shimmer

  speed 1.0                  # 0.25 to 4.0
  output_format :mp3         # mp3, opus, aac, flac
end
```

#### Voice Cloning (ElevenLabs)

```ruby
class MyVoiceNarrator < RubyLLM::Agents::Speaker
  provider :elevenlabs
  model 'eleven_multilingual_v2'

  # Clone from audio samples
  voice_clone do
    name 'My Custom Voice'
    description 'Professional male voice, American accent, warm tone'
    samples 'sample1.mp3', 'sample2.mp3', 'sample3.mp3'
    # Minimum 1 minute of clear audio recommended
  end
end

# Or use existing cloned voice by ID
class ExistingCloneNarrator < RubyLLM::Agents::Speaker
  provider :elevenlabs
  voice_id 'abc123xyz'       # Previously cloned voice ID
end
```

#### SSML Support (Speech Synthesis Markup Language)

```ruby
class ExpressiveNarrator < RubyLLM::Agents::Speaker
  provider :elevenlabs
  voice 'Rachel'

  ssml_enabled true
end

# Usage with SSML
result = ExpressiveNarrator.call(text: <<~SSML)
  <speak>
    Welcome to the show!
    <break time="1s"/>
    Today we're discussing <emphasis level="strong">artificial intelligence</emphasis>.
    <prosody rate="slow" pitch="+2st">This is very important.</prosody>
    <say-as interpret-as="spell-out">AI</say-as> stands for artificial intelligence.
  </speak>
SSML
```

#### Streaming Audio

```ruby
class StreamingNarrator < RubyLLM::Agents::Speaker
  provider :elevenlabs
  voice 'Rachel'
  streaming true
end

# Stream for real-time playback
StreamingNarrator.call(text: long_article) do |audio_chunk|
  # Each chunk is playable audio
  audio_player.play(audio_chunk)
  # Or write to stream
  response.write(audio_chunk)
end
```

#### Long Text Handling

```ruby
class BookNarrator < RubyLLM::Agents::Speaker
  provider :elevenlabs
  voice 'Rachel'

  # Auto-split long text
  chunking do
    enabled true
    max_characters 5000       # Split at sentence boundaries
    parallel false            # Process sequentially for consistent voice
    combine_output true       # Merge into single audio file
  end
end

result = BookNarrator.call(text: entire_book_text)
result.audio           # Combined audio file
result.chapters        # Individual chapter audios (if detected)
result.total_duration  # Full duration
```

#### Pronunciation Lexicon

```ruby
class TechnicalNarrator < RubyLLM::Agents::Speaker
  provider :elevenlabs
  voice 'Rachel'

  # Custom pronunciations
  lexicon do
    # word => pronunciation (IPA or respelling)
    pronounce 'RubyLLM', 'ruby L L M'
    pronounce 'PostgreSQL', 'post-gres-Q-L'
    pronounce 'Kubernetes', 'koo-ber-net-eez'
    pronounce 'nginx', 'engine-X'
    pronounce 'SQL', 'sequel'           # or 'S-Q-L'
    pronounce 'GIF', 'jif'              # fight me
  end
end
```

#### Multi-voice Conversations

```ruby
class DialogueNarrator < RubyLLM::Agents::Speaker
  provider :elevenlabs

  # Define multiple voices
  voices do
    voice :narrator, 'Rachel', stability: 0.7
    voice :alice, 'Bella', stability: 0.5
    voice :bob, 'Adam', stability: 0.5
  end
end

# Input with voice tags
script = <<~SCRIPT
  [narrator]Once upon a time, Alice met Bob.
  [alice]Hello Bob, how are you?
  [bob]I'm doing great, Alice!
  [narrator]And they became friends.
SCRIPT

result = DialogueNarrator.call(text: script)
# Automatically switches voices based on tags
```

#### Storage Integration

```ruby
class StoredNarrator < RubyLLM::Agents::Speaker
  provider :openai
  voice 'nova'

  # Auto-save to storage
  storage do
    adapter :s3                # :s3, :gcs, :azure, :local
    bucket 'my-audio-bucket'
    path_prefix 'narrations/'
    public_url true            # Generate public URLs
  end
end

result = StoredNarrator.call(text: "Hello world", filename: "greeting")
result.audio_url    # "https://my-audio-bucket.s3.amazonaws.com/narrations/greeting.mp3"
result.audio_key    # "narrations/greeting.mp3"
```

#### Reliability

```ruby
class ReliableSpeaker < RubyLLM::Agents::Speaker
  provider :elevenlabs
  voice 'Rachel'

  reliability do
    retries max: 3, backoff: :exponential
    fallback_provider :openai, voice: 'nova'  # Fall back to different provider
    total_timeout 120
    circuit_breaker errors: 5, within: 60
  end
end
```

#### Caching

```ruby
class CachedSpeaker < RubyLLM::Agents::Speaker
  provider :openai
  voice 'nova'

  cache_for 30.days

  # Cache key: text hash + voice + settings
end
```

### SpeechResult Object

```ruby
class SpeechResult
  # Audio content
  attr_reader :audio           # Binary audio data
  attr_reader :audio_url       # URL if stored
  attr_reader :audio_key       # Storage key
  attr_reader :audio_path      # Local file path

  # Audio metadata
  attr_reader :duration        # Duration in seconds
  attr_reader :format          # :mp3, :wav, :ogg, etc.
  attr_reader :sample_rate     # Sample rate
  attr_reader :bitrate         # Bitrate
  attr_reader :file_size       # Size in bytes

  # Input metadata
  attr_reader :characters      # Character count (for billing)
  attr_reader :text_length     # Original text length

  # Voice info
  attr_reader :provider        # :elevenlabs, :openai, etc.
  attr_reader :model_id
  attr_reader :voice_id
  attr_reader :voice_name

  # Timing
  attr_reader :duration_ms     # Processing time
  attr_reader :started_at
  attr_reader :completed_at

  # Cost & usage
  attr_reader :total_cost

  # Status
  attr_reader :status          # :success, :partial, :failed

  # Helpers
  def success?
  def save_to(path)
  def to_base64
end
```

---

## Part 3: Combined Features

### Voice Assistant Pipeline

```ruby
# Complete voice interaction loop
class VoiceAssistant
  def initialize(organization)
    @organization = organization
  end

  # User speaks → AI responds with voice
  def process_voice_query(audio_file)
    # 1. Transcribe user's voice
    transcription = QueryTranscriber.call(
      audio: audio_file,
      tenant: @organization
    )

    # 2. Process with AI agent
    response = AssistantAgent.call(
      query: transcription.text,
      tenant: @organization
    )

    # 3. Convert response to speech
    speech = ResponseSpeaker.call(
      text: response.content,
      tenant: @organization
    )

    VoiceResponse.new(
      transcription: transcription,
      response: response,
      speech: speech,
      total_cost: transcription.total_cost + response.total_cost + speech.total_cost
    )
  end
end
```

### Workflow Integration

```ruby
# Transcribe → Summarize → Translate → Speak pipeline
class PodcastLocalizationPipeline < RubyLLM::Agents::Workflow::Pipeline
  step :transcribe, agent: PodcastTranscriber

  step :summarize, agent: SummaryAgent,
       transform: ->(ctx) { { text: ctx[:transcribe].text } }

  step :translate, agent: TranslatorAgent,
       transform: ->(ctx) { { text: ctx[:summarize].content, target_language: 'es' } }

  step :narrate, agent: SpanishNarrator,
       transform: ->(ctx) { { text: ctx[:translate].content } }
end

result = PodcastLocalizationPipeline.call(audio: "episode.mp3")
result.steps[:transcribe].text     # English transcript
result.steps[:summarize].content   # Summary
result.steps[:translate].content   # Spanish translation
result.steps[:narrate].audio       # Spanish audio
result.total_cost                  # Combined cost
```

### Real-time Transcription (Future)

```ruby
class LiveTranscriber < RubyLLM::Agents::Transcriber
  model 'whisper-1'
  streaming true           # Real-time mode

  # Chunking for live audio
  live_settings do
    chunk_duration 5       # Process every 5 seconds
    overlap 1              # 1 second overlap
    min_silence 0.5        # Detect speech boundaries
  end
end

# Stream from microphone
LiveTranscriber.stream(audio_stream: microphone) do |partial|
  puts partial.text        # Real-time transcript updates
  update_ui(partial.text)
end
```

---

## Implementation Tasks

### Phase 1: Core Transcriber

1. **Transcriber Base Class** (`lib/ruby_llm/agents/transcriber.rb`)
2. **Transcriber DSL** (`lib/ruby_llm/agents/transcriber/dsl.rb`)
3. **Transcriber Execution** (`lib/ruby_llm/agents/transcriber/execution.rb`)
4. **TranscriptionResult** (`lib/ruby_llm/agents/transcription_result.rb`)
5. **Basic tests and example**

### Phase 2: Transcriber Features

6. **Language detection and hints**
7. **Output formats** (SRT, VTT, JSON)
8. **Chunking for long files**
9. **Instrumentation integration**
10. **Caching support**
11. **Reliability (retries, fallbacks)**

### Phase 3: Core Speaker

12. **Speaker Base Class** (`lib/ruby_llm/agents/speaker.rb`)
13. **Speaker DSL** (`lib/ruby_llm/agents/speaker/dsl.rb`)
14. **Speaker Execution** (`lib/ruby_llm/agents/speaker/execution.rb`)
15. **SpeechResult** (`lib/ruby_llm/agents/speech_result.rb`)
16. **Provider adapters** (OpenAI, ElevenLabs)

### Phase 4: Speaker Features

17. **Voice settings and customization**
18. **Streaming audio**
19. **SSML support**
20. **Pronunciation lexicon**
21. **Storage integration**
22. **Caching and reliability**

### Phase 5: Advanced Features

23. **Speaker diarization**
24. **Voice cloning integration**
25. **PII redaction**
26. **Multi-voice conversations**
27. **Workflow integration**
28. **Dashboard updates**

---

## File Structure

```
lib/ruby_llm/agents/
├── transcriber.rb                    # Transcriber base class
├── transcriber/
│   ├── dsl.rb                        # Configuration DSL
│   ├── execution.rb                  # Execution logic
│   ├── chunking.rb                   # Long audio handling
│   ├── formatters/
│   │   ├── srt.rb                    # SRT formatter
│   │   ├── vtt.rb                    # VTT formatter
│   │   └── json.rb                   # JSON formatter
│   └── processors/
│       ├── redactor.rb               # PII redaction
│       └── postprocessor.rb          # Text cleanup
├── transcription_result.rb           # Result object
│
├── speaker.rb                        # Speaker base class
├── speaker/
│   ├── dsl.rb                        # Configuration DSL
│   ├── execution.rb                  # Execution logic
│   ├── providers/
│   │   ├── base.rb                   # Provider interface
│   │   ├── openai.rb                 # OpenAI TTS
│   │   ├── elevenlabs.rb             # ElevenLabs
│   │   ├── google.rb                 # Google TTS
│   │   └── polly.rb                  # Amazon Polly
│   ├── voice_settings.rb             # Voice configuration
│   └── storage.rb                    # Audio storage
└── speech_result.rb                  # Result object

examples/
├── transcribers/
│   ├── basic_transcriber.rb
│   ├── meeting_transcriber.rb
│   ├── podcast_transcriber.rb
│   └── subtitle_generator.rb
└── speakers/
    ├── basic_narrator.rb
    ├── audiobook_narrator.rb
    ├── voice_assistant.rb
    └── multilingual_speaker.rb
```

---

## Configuration

```ruby
RubyLLM::Agents.configure do |config|
  # Transcription defaults
  config.default_transcription_model = 'whisper-1'
  config.default_transcription_language = nil     # Auto-detect
  config.track_transcriptions = true

  # TTS defaults
  config.default_tts_provider = :openai
  config.default_tts_model = 'tts-1'
  config.default_tts_voice = 'nova'
  config.track_speech = true

  # ElevenLabs API key (if using)
  config.elevenlabs_api_key = ENV['ELEVENLABS_API_KEY']

  # Audio storage
  config.audio_storage = {
    adapter: :s3,
    bucket: 'my-audio-bucket',
    region: 'us-east-1'
  }
end
```

---

## Cost Tracking

### Transcription Costs

| Model | Price |
|-------|-------|
| whisper-1 | $0.006 / minute |
| gpt-4o-transcribe | ~$0.01 / minute |
| gpt-4o-mini-transcribe | ~$0.005 / minute |

### TTS Costs

| Provider | Model | Price |
|----------|-------|-------|
| OpenAI | tts-1 | $0.015 / 1K chars |
| OpenAI | tts-1-hd | $0.030 / 1K chars |
| ElevenLabs | Standard | $0.30 / 1K chars |
| ElevenLabs | Pro | Varies by plan |

---

## Database Changes

```ruby
# Migration: Add execution_type support for audio
class AddAudioExecutionTypes < ActiveRecord::Migration[7.0]
  def change
    # execution_type can now be: 'chat', 'embedding', 'transcription', 'speech'

    # Add audio-specific metadata columns (optional)
    add_column :ruby_llm_agents_executions, :audio_duration, :float
    add_column :ruby_llm_agents_executions, :character_count, :integer
  end
end
```

---

## Open Questions

1. **Should we bundle FFmpeg for audio preprocessing?**
   - Recommendation: No, document as optional dependency

2. **Should we support real-time/streaming transcription?**
   - Recommendation: Phase 2, focus on file-based first

3. **How to handle very large files (> 1 hour)?**
   - Recommendation: Auto-chunking with configurable limits

4. **Should voice cloning be a separate class?**
   - Recommendation: Keep as Speaker feature for now

5. **Storage integration - built-in or external?**
   - Recommendation: Provide adapters, let users configure

---

## Dependencies

### Required
- `ruby_llm` gem (provides RubyLLM.transcribe)

### Optional
- `aws-sdk-s3` - S3 storage
- `google-cloud-storage` - GCS storage
- `ffmpeg` (system) - Audio preprocessing
- `webvtt-ruby` - VTT parsing/generation
