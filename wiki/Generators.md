# Generators

RubyLLM::Agents provides Rails generators to quickly scaffold agents, embedders, transcribers, speakers, and image operations.

## Directory Structure

All generated files are organized under `app/agents/`:

```
app/
└── agents/                           # Root directory
    ├── application_agent.rb          # Core agents
    ├── search_agent.rb
    ├── audio/                        # Audio operations
    │   ├── application_speaker.rb
    │   ├── narrator_speaker.rb
    │   ├── application_transcriber.rb
    │   └── meeting_transcriber.rb
    ├── embedders/                    # Text embeddings
    │   ├── application_embedder.rb
    │   └── document_embedder.rb
    └── images/                       # Image operations
        ├── application_image_generator.rb
        ├── logo_generator.rb
        ├── application_image_analyzer.rb
        ├── product_analyzer.rb
        ├── application_image_editor.rb
        ├── photo_editor.rb
        ├── application_image_transformer.rb
        ├── anime_transformer.rb
        ├── application_image_upscaler.rb
        ├── photo_upscaler.rb
        ├── application_image_variator.rb
        ├── logo_variator.rb
        ├── application_background_remover.rb
        ├── product_background_remover.rb
        ├── application_image_pipeline.rb
        └── product_pipeline.rb
```

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

**Creates:**
- `app/agents/application_agent.rb` (if not exists)
- `app/agents/[name]_agent.rb`

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
- `app/agents/embedders/application_embedder.rb` (if not exists)
- `app/agents/embedders/[name]_embedder.rb`

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
- `app/agents/audio/application_transcriber.rb` (if not exists)
- `app/agents/audio/[name]_transcriber.rb`

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
- `app/agents/audio/application_speaker.rb` (if not exists)
- `app/agents/audio/[name]_speaker.rb`

## Image Operations Generators

RubyLLM::Agents provides a suite of generators for image operations.

### Image Generator Generator

Create image generation classes:

```bash
# Basic generator
rails generate ruby_llm_agents:image_generator logo

# With options
rails generate ruby_llm_agents:image_generator product --model gpt-image-1 --size 1024x1024
rails generate ruby_llm_agents:image_generator avatar --quality hd --style vivid
rails generate ruby_llm_agents:image_generator banner --cache 1.day
```

**Options:**

| Option | Description | Default |
|--------|-------------|---------|
| `--model` | Image generation model | `gpt-image-1` |
| `--size` | Image size | `1024x1024` |
| `--quality` | Quality level (standard, hd) | `standard` |
| `--style` | Style (vivid, natural) | `vivid` |
| `--content_policy` | Content policy level | `standard` |
| `--cache` | Cache duration | None |

**Creates:**
- `app/agents/images/application_image_generator.rb` (if not exists)
- `app/agents/images/[name]_generator.rb`

### Image Variator Generator

Create image variation classes:

```bash
# Basic variator
rails generate ruby_llm_agents:image_variator logo

# With options
rails generate ruby_llm_agents:image_variator product --model gpt-image-1 --size 1024x1024
rails generate ruby_llm_agents:image_variator avatar --variation_strength 0.3
```

**Options:**

| Option | Description | Default |
|--------|-------------|---------|
| `--model` | Image model | `gpt-image-1` |
| `--size` | Output image size | `1024x1024` |
| `--variation_strength` | Variation strength (0.0-1.0) | `0.5` |
| `--cache` | Cache duration | None |

**Creates:**
- `app/agents/images/application_image_variator.rb` (if not exists)
- `app/agents/images/[name]_variator.rb`

### Image Editor Generator

Create image editing classes (inpainting/outpainting):

```bash
# Basic editor
rails generate ruby_llm_agents:image_editor product

# With options
rails generate ruby_llm_agents:image_editor background --model gpt-image-1 --size 1024x1024
rails generate ruby_llm_agents:image_editor photo --content_policy strict
```

**Options:**

| Option | Description | Default |
|--------|-------------|---------|
| `--model` | Image model | `gpt-image-1` |
| `--size` | Output image size | `1024x1024` |
| `--content_policy` | Content policy level | `standard` |
| `--cache` | Cache duration | None |

**Creates:**
- `app/agents/images/application_image_editor.rb` (if not exists)
- `app/agents/images/[name]_editor.rb`

### Image Transformer Generator

Create style transfer/image transformation classes:

```bash
# Basic transformer
rails generate ruby_llm_agents:image_transformer anime

# With options
rails generate ruby_llm_agents:image_transformer watercolor --model sdxl --strength 0.8
rails generate ruby_llm_agents:image_transformer oil --template "oil painting, {prompt}"
```

**Options:**

| Option | Description | Default |
|--------|-------------|---------|
| `--model` | Image model | `sdxl` |
| `--size` | Output image size | `1024x1024` |
| `--strength` | Transformation strength (0.0-1.0) | `0.75` |
| `--template` | Prompt template | None |
| `--content_policy` | Content policy level | `standard` |
| `--cache` | Cache duration | None |

**Creates:**
- `app/agents/images/application_image_transformer.rb` (if not exists)
- `app/agents/images/[name]_transformer.rb`

### Image Upscaler Generator

Create image upscaling classes:

```bash
# Basic upscaler
rails generate ruby_llm_agents:image_upscaler photo

# With options
rails generate ruby_llm_agents:image_upscaler portrait --model real-esrgan --scale 4
rails generate ruby_llm_agents:image_upscaler face --face_enhance
```

**Options:**

| Option | Description | Default |
|--------|-------------|---------|
| `--model` | Upscaling model | `real-esrgan` |
| `--scale` | Upscale factor (2, 4, 8) | `4` |
| `--face_enhance` | Enable face enhancement | `false` |
| `--cache` | Cache duration | None |

**Creates:**
- `app/agents/images/application_image_upscaler.rb` (if not exists)
- `app/agents/images/[name]_upscaler.rb`

### Image Analyzer Generator

Create image analysis classes (vision AI):

```bash
# Basic analyzer
rails generate ruby_llm_agents:image_analyzer product

# With options
rails generate ruby_llm_agents:image_analyzer content --model gpt-4o --analysis_type detailed
rails generate ruby_llm_agents:image_analyzer photo --extract_colors --detect_objects
rails generate ruby_llm_agents:image_analyzer document --extract_text
```

**Options:**

| Option | Description | Default |
|--------|-------------|---------|
| `--model` | Vision model | `gpt-4o` |
| `--analysis_type` | Analysis type | `detailed` |
| `--extract_colors` | Enable color extraction | `false` |
| `--detect_objects` | Enable object detection | `false` |
| `--extract_text` | Enable OCR | `false` |
| `--max_tags` | Maximum tags to return | `10` |
| `--cache` | Cache duration | None |

**Analysis types:** `caption`, `detailed`, `tags`, `objects`, `colors`, `all`

**Creates:**
- `app/agents/images/application_image_analyzer.rb` (if not exists)
- `app/agents/images/[name]_analyzer.rb`

### Background Remover Generator

Create background removal classes:

```bash
# Basic remover
rails generate ruby_llm_agents:background_remover product

# With options
rails generate ruby_llm_agents:background_remover portrait --model segment-anything --alpha_matting
rails generate ruby_llm_agents:background_remover photo --refine_edges --return_mask
```

**Options:**

| Option | Description | Default |
|--------|-------------|---------|
| `--model` | Segmentation model | `rembg` |
| `--output_format` | Output format (png, webp) | `png` |
| `--refine_edges` | Enable edge refinement | `false` |
| `--alpha_matting` | Enable alpha matting | `false` |
| `--return_mask` | Also return segmentation mask | `false` |
| `--cache` | Cache duration | None |

**Creates:**
- `app/agents/images/application_background_remover.rb` (if not exists)
- `app/agents/images/[name]_background_remover.rb`

### Image Pipeline Generator

Create multi-step image processing pipelines:

```bash
# Basic pipeline
rails generate ruby_llm_agents:image_pipeline product

# With steps
rails generate ruby_llm_agents:image_pipeline ecommerce --steps generate,upscale,remove_background
rails generate ruby_llm_agents:image_pipeline content --steps generate,analyze
rails generate ruby_llm_agents:image_pipeline full --steps generate,upscale,transform,analyze
```

**Options:**

| Option | Description | Default |
|--------|-------------|---------|
| `--steps` | Pipeline steps (comma-separated) | `generate,upscale` |
| `--stop_on_error` | Stop on first error | `true` |
| `--cache` | Cache duration | None |

**Available steps:** `generate`, `upscale`, `transform`, `analyze`, `remove_background`

**Creates:**
- `app/agents/images/application_image_pipeline.rb` (if not exists)
- `app/agents/images/[name]_pipeline.rb`

## Upgrade Generator

Add new migrations when upgrading RubyLLM::Agents:

```bash
rails generate ruby_llm_agents:upgrade
rails db:migrate
```

This adds any missing columns to the executions table for new features.

## Restructure Generator

Migrate existing apps from the old directory structure to the new organized structure:

```bash
rails generate ruby_llm_agents:restructure
```

This migrates files from:
- `app/llm/agents/` → `app/agents/`
- `app/llm/text/embedders/` → `app/agents/embedders/`
- `app/llm/audio/speakers/` → `app/agents/audio/`
- `app/llm/audio/transcribers/` → `app/agents/audio/`
- `app/llm/image/generators/` → `app/agents/images/`
- `app/llm/image/variators/` → `app/agents/images/`
- `app/llm/image/editors/` → `app/agents/images/`
- `app/llm/image/transformers/` → `app/agents/images/`
- `app/llm/image/upscalers/` → `app/agents/images/`
- `app/llm/image/analyzers/` → `app/agents/images/`
- `app/llm/image/background_removers/` → `app/agents/images/`
- `app/llm/image/pipelines/` → `app/agents/images/`

**Note:** The restructure generator removes the `module LLM` wrapper from classes and updates file paths. Review the changes before committing.

## Multi-Tenancy Generator

Set up multi-tenancy support:

```bash
rails generate ruby_llm_agents:multi_tenancy
rails db:migrate
```

This creates:
- `db/migrate/xxx_add_tenant_to_executions.rb` - Adds tenant_id column
- `db/migrate/xxx_create_tenant_budgets.rb` - Per-tenant budget table

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
- [Image Operations](Image-Generation) - Image generation, analysis, and processing
- [Configuration](Configuration) - Global configuration options
