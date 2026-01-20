# Generators

RubyLLM::Agents provides Rails generators to quickly scaffold agents, embedders, transcribers, and speakers.

## Installation Generator

Set up RubyLLM::Agents in your Rails app:

```bash
rails generate ruby_llm_agents:install
```

This creates:
- `db/migrate/xxx_create_ruby_llm_agents_executions.rb` - Execution tracking table
- `config/initializers/ruby_llm_agents.rb` - Configuration file
- `app/agents/application_agent.rb` - Base class for agents
- Mounts dashboard at `/agents` in routes

## Agent Generator

Create new AI agents:

```bash
# Basic agent
rails generate ruby_llm_agents:agent search

# Agent with parameters
rails generate ruby_llm_agents:agent search query:required limit:10

# Nested agent (creates chat/support_agent.rb)
rails generate ruby_llm_agents:agent chat/support message:required
```

**Options:**

| Option | Description | Example |
|--------|-------------|---------|
| `--model` | LLM model | `--model gpt-4o` |
| `--temperature` | Temperature (0.0-2.0) | `--temperature 0.7` |
| `--streaming` | Enable streaming | `--streaming` |
| `--cache` | Cache duration | `--cache 1.hour` |

**Parameter syntax:**
- `name` - Optional parameter
- `name:required` - Required parameter
- `name:default_value` - Parameter with default
- `name:10` - Numeric default
- `name:true` or `name:false` - Boolean default

**Examples:**

```bash
# Full-featured agent
rails generate ruby_llm_agents:agent content_generator \
  topic:required \
  tone:professional \
  word_count:500 \
  --model gpt-4o \
  --temperature 0.7 \
  --cache 2.hours

# Chat agent with streaming
rails generate ruby_llm_agents:agent chat \
  message:required \
  history:[] \
  --streaming \
  --model claude-3-5-sonnet
```

## Embedder Generator

Create vector embedding classes:

```bash
# Basic embedder
rails generate ruby_llm_agents:embedder document

# With options
rails generate ruby_llm_agents:embedder document --model text-embedding-3-large
rails generate ruby_llm_agents:embedder document --dimensions 512
rails generate ruby_llm_agents:embedder document --cache 1.week
```

**Options:**

| Option | Description | Default |
|--------|-------------|---------|
| `--model` | Embedding model | `text-embedding-3-small` |
| `--dimensions` | Vector dimensions | Model default |
| `--batch-size` | Texts per API call | `100` |
| `--cache` | Cache duration | None |

**Creates:**
- `app/embedders/application_embedder.rb` (if not exists)
- `app/embedders/[name]_embedder.rb`

## Transcriber Generator

Create speech-to-text classes:

```bash
# Basic transcriber
rails generate ruby_llm_agents:transcriber meeting

# With options
rails generate ruby_llm_agents:transcriber meeting --model gpt-4o-transcribe
rails generate ruby_llm_agents:transcriber meeting --language es
rails generate ruby_llm_agents:transcriber meeting --output-format srt
rails generate ruby_llm_agents:transcriber meeting --cache 30.days
```

**Options:**

| Option | Description | Default |
|--------|-------------|---------|
| `--model` | Transcription model | `whisper-1` |
| `--language` | Language code | Auto-detect |
| `--output-format` | Output format | `text` |
| `--timestamps` | Timestamp granularity | `none` |
| `--cache` | Cache duration | None |

**Output formats:** `text`, `json`, `srt`, `vtt`
**Timestamp options:** `none`, `segment`, `word`

**Creates:**
- `app/transcribers/application_transcriber.rb` (if not exists)
- `app/transcribers/[name]_transcriber.rb`

## Speaker Generator

Create text-to-speech classes:

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

**Options:**

| Option | Description | Default |
|--------|-------------|---------|
| `--provider` | TTS provider | `openai` |
| `--model` | TTS model | `tts-1` |
| `--voice` | Voice name | `nova` |
| `--speed` | Speech speed | `1.0` |
| `--format` | Output format | `mp3` |
| `--streaming` | Enable streaming | `false` |
| `--cache` | Cache duration | None |

**Providers:** `openai`, `elevenlabs`
**OpenAI voices:** `alloy`, `echo`, `fable`, `nova`, `onyx`, `shimmer`
**Formats:** `mp3`, `wav`, `ogg`, `flac`

**Creates:**
- `app/speakers/application_speaker.rb` (if not exists)
- `app/speakers/[name]_speaker.rb`

## Upgrade Generator

Add new migrations when upgrading RubyLLM::Agents:

```bash
rails generate ruby_llm_agents:upgrade
rails db:migrate
```

This adds any missing columns to the executions table for new features.

## Multi-Tenancy Generator

Set up multi-tenancy support:

```bash
rails generate ruby_llm_agents:multi_tenancy
rails db:migrate
```

This creates:
- `db/migrate/xxx_add_tenant_to_executions.rb` - Adds tenant_id column
- `db/migrate/xxx_create_tenant_budgets.rb` - Per-tenant budget table

## Generated File Structure

After using generators, your app will have:

```
app/
├── agents/
│   ├── application_agent.rb      # Base class
│   ├── search_agent.rb           # Your agents
│   └── chat/
│       └── support_agent.rb      # Nested agents
├── embedders/
│   ├── application_embedder.rb   # Base class
│   └── document_embedder.rb      # Your embedders
├── transcribers/
│   ├── application_transcriber.rb # Base class
│   └── meeting_transcriber.rb    # Your transcribers
└── speakers/
    ├── application_speaker.rb    # Base class
    └── narrator_speaker.rb       # Your speakers
```

## Tips

### Skip Existing Base Classes

If base classes already exist, generators will skip them:

```bash
# First agent creates application_agent.rb
rails generate ruby_llm_agents:agent first

# Second agent skips application_agent.rb
rails generate ruby_llm_agents:agent second
```

### Destroy Generated Files

Remove generated files:

```bash
rails destroy ruby_llm_agents:agent search
```

### Preview Without Creating

Use `--pretend` to see what would be generated:

```bash
rails generate ruby_llm_agents:agent search --pretend
```

## Related Pages

- [Getting Started](Getting-Started) - Initial setup
- [Agent DSL](Agent-DSL) - Agent configuration
- [Embeddings](Embeddings) - Vector embeddings
- [Audio](Audio) - Transcription and TTS
