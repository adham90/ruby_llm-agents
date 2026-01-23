# Plan: App-Level Agents Directory Structure

## Overview

Define the recommended directory structure for Rails applications using the `ruby_llm-agents` gem. This structure lives in `app/agents/` and contains user-defined agents that inherit from the gem's base classes.

## Context

- The gem's framework code stays in `lib/ruby_llm/agents/`
- Applications using the gem need a clear convention for organizing their custom agents
- This structure should be documented and scaffolded by generators

## Breaking Changes from Previous Structure

**Old structure (deprecated):**
```
app/{root}/                        # Configurable root (default: "llm")
├── agents/
├── text/embedders/
├── image/generators/
├── image/analyzers/
├── audio/speakers/
├── audio/transcribers/
└── workflows/
```

**New structure:**
```
app/
├── agents/                        # Fixed location (not configurable)
│   ├── images/                    # Flat by modality (no operation nesting)
│   ├── audio/
│   ├── embedders/
│   └── moderators/
└── workflows/
```

**Key changes:**
1. Root is now fixed at `app/agents/` (not configurable)
2. Plural folder names (`images/` not `image/`)
3. Flat modality folders (no `generators/`, `analyzers/` subfolders)
4. Simpler namespacing (`Images::Foo` not `Llm::Image::Foo`)

---

## Recommended Structure

```
app/
├── agents/
│   ├── application_agent.rb           # Base class for all app agents
│   ├── concerns/
│   │   └── # App-specific shared mixins
│   │
│   │── # ─── Task Agents (root level) ───
│   │── # Primary use case: conversational/tool-using agents
│   ├── customer_support_agent.rb
│   ├── research_agent.rb
│   ├── code_review_agent.rb
│   ├── data_extraction_agent.rb
│   │
│   │── # ─── Media: Images ───
│   ├── images/
│   │   ├── product_generator.rb
│   │   ├── avatar_generator.rb
│   │   └── content_analyzer.rb
│   │
│   │── # ─── Media: Videos (future) ───
│   ├── videos/
│   │   ├── promo_generator.rb
│   │   └── clip_analyzer.rb
│   │
│   │── # ─── Media: Audio ───
│   ├── audio/
│   │   ├── meeting_transcriber.rb
│   │   └── voice_narrator.rb
│   │
│   │── # ─── Text Operations ───
│   ├── embedders/
│   │   ├── semantic_embedder.rb
│   │   └── code_embedder.rb
│   │
│   └── moderators/
│       └── content_moderator.rb
│
└── workflows/
    ├── application_workflow.rb         # Base class for workflows
    ├── onboarding_workflow.rb
    ├── content_pipeline_workflow.rb
    └── document_processing_workflow.rb
```

---

## Design Principles

### 1. Task Agents at Root

The primary use case (conversational, tool-using agents) lives at the root level:

```
app/agents/
├── customer_support_agent.rb    # Not nested
├── research_agent.rb
```

**Rationale:** These are the "main" agents that most developers think of. No need to bury them in folders.

### 2. Media Grouped by Modality

Images, videos, and audio each get their own folder:

```
app/agents/
├── images/     # Generators, analyzers, editors, etc.
├── videos/     # Future: generators, analyzers
├── audio/      # Transcribers, speakers
```

**Rationale:**
- Each modality can have multiple operations (generate, analyze, edit)
- Avoids naming conflicts (image generator vs video generator)
- Matches how people think ("I need an image agent")

### 3. Text Operations Stay Separate

Embedders and moderators get dedicated folders:

```
app/agents/
├── embedders/
├── moderators/
```

**Rationale:**
- These are utility operations, not conversational
- Clear purpose from folder name
- Separate from task agents at root

### 4. Start Flat, Add Structure When Needed

Don't pre-create folders. Add them when you have 2+ files:

```
# Day 1: One embedder, keep at root
app/agents/
├── semantic_embedder.rb

# Day 30: Second embedder, create folder
app/agents/
├── embedders/
│   ├── semantic_embedder.rb
│   └── code_embedder.rb
```

### 5. Workflows Are Not Agents

Workflows compose agents but are a different concept:

```
app/
├── agents/      # Individual agents
└── workflows/   # Compositions of agents
```

---

## File Templates

### application_agent.rb

```ruby
# app/agents/application_agent.rb
class ApplicationAgent < RubyLLM::Agents::Core::Base
  # App-wide defaults and configuration

  # Example: Default model for all agents
  # model "gpt-4o"

  # Example: App-wide concern
  # include Agents::Concerns::Auditable
end
```

### Task Agent Example

```ruby
# app/agents/customer_support_agent.rb
class CustomerSupportAgent < ApplicationAgent
  model "gpt-4o"
  description "Handles customer inquiries and support tickets"

  param :inquiry, required: true
  param :customer_id

  tools :search_knowledge_base, :create_ticket, :escalate_to_human

  def execute(context)
    # Agent logic
  end
end
```

### Specialized Agent Example

```ruby
# app/agents/embedders/semantic_embedder.rb
module Embedders
  class SemanticEmbedder < RubyLLM::Agents::Embedder
    model "text-embedding-3-large"
    dimensions 1536

    def preprocess(text)
      # Custom preprocessing
      text.strip.downcase
    end
  end
end
```

### Image Agent Example

```ruby
# app/agents/images/product_generator.rb
module Images
  class ProductGenerator < RubyLLM::Agents::Image::Generator
    model "dall-e-3"
    size "1024x1024"
    quality "hd"

    template :product_shot, <<~PROMPT
      Professional product photography of {{product_name}},
      white background, studio lighting, high detail
    PROMPT
  end
end
```

### Workflow Example

```ruby
# app/workflows/application_workflow.rb
class ApplicationWorkflow < RubyLLM::Agents::Workflow::Orchestrator
  # App-wide workflow configuration
end

# app/workflows/content_pipeline_workflow.rb
class ContentPipelineWorkflow < ApplicationWorkflow
  description "Process and publish content"

  step :moderate, agent: Moderators::ContentModerator
  step :generate_image, agent: Images::ProductGenerator
  step :embed, agent: Embedders::SemanticEmbedder
end
```

---

## Namespacing Conventions

| Location | Module | Class Name |
|----------|--------|------------|
| `app/agents/foo_agent.rb` | (none) | `FooAgent` |
| `app/agents/images/foo.rb` | `Images` | `Images::Foo` |
| `app/agents/audio/foo.rb` | `Audio` | `Audio::Foo` |
| `app/agents/videos/foo.rb` | `Videos` | `Videos::Foo` |
| `app/agents/embedders/foo.rb` | `Embedders` | `Embedders::Foo` |
| `app/agents/moderators/foo.rb` | `Moderators` | `Moderators::Foo` |
| `app/agents/concerns/foo.rb` | `Agents::Concerns` | `Agents::Concerns::Foo` |
| `app/workflows/foo_workflow.rb` | (none) | `FooWorkflow` |

---

## Folder Purpose Reference

| Folder | Contains | Inherits From |
|--------|----------|---------------|
| `agents/` (root) | Task/conversational agents | `ApplicationAgent` |
| `agents/images/` | Image operations | `RubyLLM::Agents::Image::*` |
| `agents/videos/` | Video operations | `RubyLLM::Agents::Video::*` |
| `agents/audio/` | Audio operations | `RubyLLM::Agents::Audio::*` |
| `agents/embedders/` | Embedding generators | `RubyLLM::Agents::Embedder` |
| `agents/moderators/` | Content moderators | `RubyLLM::Agents::Moderator` |
| `agents/concerns/` | Shared mixins | N/A (modules) |
| `workflows/` | Agent compositions | `ApplicationWorkflow` |

---

## When to Create Folders

| Scenario | Action |
|----------|--------|
| First task agent | Create at root: `app/agents/foo_agent.rb` |
| First image agent | Create folder: `app/agents/images/foo.rb` |
| First embedder | Create at root: `app/agents/foo_embedder.rb` |
| Second embedder | Create folder, move both to `app/agents/embedders/` |
| First workflow | Create folder: `app/workflows/foo_workflow.rb` |

---

## Rails Autoloading

With Zeitwerk (Rails 6+), this structure autoloads correctly:

```ruby
# These all work automatically:
CustomerSupportAgent        # app/agents/customer_support_agent.rb
Images::ProductGenerator    # app/agents/images/product_generator.rb
Embedders::SemanticEmbedder # app/agents/embedders/semantic_embedder.rb
ContentPipelineWorkflow     # app/workflows/content_pipeline_workflow.rb
```

No explicit requires needed.

---

## Generator Commands

The gem provides these generators:

```bash
# Install the gem (creates base structure)
rails generate ruby_llm_agents:install

# Generate a task agent
rails generate ruby_llm_agents:agent CustomerSupport query:required

# Generate image agents
rails generate ruby_llm_agents:image_generator Product
rails generate ruby_llm_agents:image_analyzer Content
rails generate ruby_llm_agents:image_editor Photo
rails generate ruby_llm_agents:image_upscaler HighRes
rails generate ruby_llm_agents:image_variator Style
rails generate ruby_llm_agents:image_transformer Format
rails generate ruby_llm_agents:background_remover Product
rails generate ruby_llm_agents:image_pipeline Product

# Generate audio agents
rails generate ruby_llm_agents:transcriber Meeting
rails generate ruby_llm_agents:speaker Voice

# Generate text agents
rails generate ruby_llm_agents:embedder Semantic
# (moderator generator to be added)

# Generate a workflow
rails generate ruby_llm_agents:workflow ContentPipeline

# Migrate from old structure
rails generate ruby_llm_agents:migrate_structure
rails generate ruby_llm_agents:migrate_structure --dry-run
```

---

## Migration from Old Structure

### Automatic Migration

Run the migration generator:

```bash
# Preview changes (recommended first)
rails generate ruby_llm_agents:migrate_structure --dry-run

# Execute migration
rails generate ruby_llm_agents:migrate_structure
```

### What the Migration Does

1. **Detects old structure** at `app/{root}/` (default: `app/llm/`)
2. **Creates new directories** under `app/agents/` and `app/workflows/`
3. **Moves files** with `git mv` when in a git repo
4. **Updates namespaces** in Ruby files:
   - `Llm::` → (removed)
   - `Llm::Image::` → `Images::`
   - `Llm::Audio::` → `Audio::`
   - `Llm::Text::` → `Embedders::` or `Moderators::`
5. **Updates base class references**
6. **Removes empty old directories**

### File Mapping

| Old Location | New Location |
|--------------|--------------|
| `app/llm/agents/*.rb` | `app/agents/*.rb` |
| `app/llm/image/generators/*.rb` | `app/agents/images/*.rb` |
| `app/llm/image/analyzers/*.rb` | `app/agents/images/*.rb` |
| `app/llm/image/editors/*.rb` | `app/agents/images/*.rb` |
| `app/llm/image/upscalers/*.rb` | `app/agents/images/*.rb` |
| `app/llm/image/variators/*.rb` | `app/agents/images/*.rb` |
| `app/llm/image/transformers/*.rb` | `app/agents/images/*.rb` |
| `app/llm/image/background_removers/*.rb` | `app/agents/images/*.rb` |
| `app/llm/image/pipelines/*.rb` | `app/agents/images/*.rb` |
| `app/llm/audio/speakers/*.rb` | `app/agents/audio/*.rb` |
| `app/llm/audio/transcribers/*.rb` | `app/agents/audio/*.rb` |
| `app/llm/text/embedders/*.rb` | `app/agents/embedders/*.rb` |
| `app/llm/workflows/*.rb` | `app/workflows/*.rb` |

### Namespace Mapping

| Old Namespace | New Namespace |
|---------------|---------------|
| `Llm::CustomerSupportAgent` | `CustomerSupportAgent` |
| `Llm::Image::ProductGenerator` | `Images::ProductGenerator` |
| `Llm::Image::ContentAnalyzer` | `Images::ContentAnalyzer` |
| `Llm::Audio::MeetingTranscriber` | `Audio::MeetingTranscriber` |
| `Llm::Audio::VoiceSpeaker` | `Audio::VoiceSpeaker` |
| `Llm::Text::SemanticEmbedder` | `Embedders::SemanticEmbedder` |
| `Llm::ContentPipelineWorkflow` | `ContentPipelineWorkflow` |

### Manual Steps After Migration

1. **Update references** in your codebase:
   ```ruby
   # Before
   Llm::Image::ProductGenerator.call(prompt: "...")

   # After
   Images::ProductGenerator.call(prompt: "...")
   ```

2. **Update tests** to use new class names

3. **Remove old configuration** (if any):
   ```ruby
   # config/initializers/ruby_llm_agents.rb
   # Remove: config.root_directory = "llm"
   ```

4. **Verify autoloading** works:
   ```bash
   rails runner "puts Images::ProductGenerator"
   ```

---

## Implementation Plan

### Phase 1: Create Migration Generator

Create `lib/generators/ruby_llm_agents/migrate_structure_generator.rb`:

1. Detect old structure presence
2. Map old paths to new paths
3. Move files (with git mv if available)
4. Update namespaces in moved files
5. Clean up empty directories
6. Provide dry-run option

### Phase 2: Update Install Generator

Update `lib/generators/ruby_llm_agents/install_generator.rb`:

1. Remove configurable `root_directory`
2. Create `app/agents/` structure
3. Create `app/workflows/` structure
4. Update templates for new namespacing

### Phase 3: Update All Agent Generators

Update each generator to use new paths:

| Generator | Old Path | New Path |
|-----------|----------|----------|
| `agent_generator.rb` | `app/{root}/agents/` | `app/agents/` |
| `image_generator_generator.rb` | `app/{root}/image/generators/` | `app/agents/images/` |
| `image_analyzer_generator.rb` | `app/{root}/image/analyzers/` | `app/agents/images/` |
| `image_editor_generator.rb` | `app/{root}/image/editors/` | `app/agents/images/` |
| `image_upscaler_generator.rb` | `app/{root}/image/upscalers/` | `app/agents/images/` |
| `image_variator_generator.rb` | `app/{root}/image/variators/` | `app/agents/images/` |
| `image_transformer_generator.rb` | `app/{root}/image/transformers/` | `app/agents/images/` |
| `background_remover_generator.rb` | `app/{root}/image/background_removers/` | `app/agents/images/` |
| `image_pipeline_generator.rb` | `app/{root}/image/pipelines/` | `app/agents/images/` |
| `transcriber_generator.rb` | `app/{root}/audio/transcribers/` | `app/agents/audio/` |
| `speaker_generator.rb` | `app/{root}/audio/speakers/` | `app/agents/audio/` |
| `embedder_generator.rb` | `app/{root}/text/embedders/` | `app/agents/embedders/` |

### Phase 4: Update Templates

Update all `.rb.tt` templates:

1. Remove `{root_namespace}::` prefixes
2. Update module names to new convention
3. Update base class references

### Phase 5: Update Configuration

1. Deprecate `root_directory` config option
2. Remove from configuration.rb (with deprecation warning)
3. Update engine.rb autoload paths

### Phase 6: Documentation

1. Update README with new structure
2. Add UPGRADING.md guide
3. Update CHANGELOG

---

## Open Questions

1. **Should `concerns/` be `agents/concerns/` or just `concerns/`?**
   - Decision: `agents/concerns/` to keep agent-specific code together

2. **What about agent-specific views/partials?**
   - Consider: `app/views/agents/` if agents need UI components

3. **Testing structure?**
   - Mirror in `spec/agents/` or `test/agents/`

4. **Backwards compatibility period?**
   - Suggestion: Support old structure with deprecation warnings for 2 minor versions

---

## Success Criteria

- [ ] Clear convention documented
- [ ] Migration generator works correctly
- [ ] All agent generators produce correct structure
- [ ] Rails autoloading works without configuration
- [ ] Easy to understand for new developers
- [ ] Scales from 1 agent to 100+ agents
- [ ] Old structure migration is smooth
