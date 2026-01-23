# Plan: App-Level Agents Directory Structure

## Overview

Define the recommended directory structure for Rails applications using the `ruby_llm-agents` gem. This structure lives in `app/agents/` and contains user-defined agents that inherit from the gem's base classes.

## Context

- The gem's framework code stays in `lib/ruby_llm/agents/`
- Applications using the gem need a clear convention for organizing their custom agents
- This structure should be documented and optionally scaffolded by generators

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

## Generator Support (Future)

The gem could provide generators:

```bash
# Generate a task agent
rails generate agent CustomerSupport

# Generate an image agent
rails generate agent:image ProductGenerator

# Generate an embedder
rails generate agent:embedder Semantic

# Generate a workflow
rails generate workflow ContentPipeline
```

---

## Migration from Existing Apps

If an app already has agents elsewhere:

1. Create `app/agents/application_agent.rb`
2. Move task agents to `app/agents/`
3. Create modality folders as needed
4. Update any explicit requires (shouldn't be needed with Zeitwerk)
5. Update any full class references

---

## Open Questions

1. **Should `concerns/` be `agents/concerns/` or just `concerns/`?**
   - Recommendation: `agents/concerns/` to keep agent-specific code together

2. **What about agent-specific views/partials?**
   - Consider: `app/views/agents/` if agents need UI components

3. **Testing structure?**
   - Mirror in `spec/agents/` or `test/agents/`

---

## Success Criteria

- [ ] Clear convention documented
- [ ] Generators produce correct structure
- [ ] Rails autoloading works without configuration
- [ ] Easy to understand for new developers
- [ ] Scales from 1 agent to 100+ agents
