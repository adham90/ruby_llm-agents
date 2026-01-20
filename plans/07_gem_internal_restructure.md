# Plan: Restructure Gem Internal Code Organization

## Overview

Reorganize the `lib/ruby_llm/agents/` directory from a flat structure to a grouped structure for better maintainability as the codebase grows.

## Current State

**83 total Ruby files** with a semi-flat structure that's becoming unwieldy:

```
lib/ruby_llm/agents/
├── # 31 root-level files (agents, results, infrastructure mixed)
├── base/                    # 10 files - agent framework
├── budget/                  # 4 files
├── reliability/             # 5 files
├── concerns/                # 2 files
├── workflow/                # 7 files
├── image_generator/         # 6 files
├── image_analyzer/          # 2 files (dsl + execution)
├── image_editor/            # 2 files
├── image_transformer/       # 2 files
├── image_upscaler/          # 2 files
├── image_variator/          # 2 files
├── image_pipeline/          # 2 files
├── background_remover/      # 2 files
├── embedder/                # 2 files
├── transcriber/             # 2 files
└── speaker/                 # 2 files
```

### Current Files by Category

#### Core Infrastructure (10 files at root)
- `base.rb` - Base agent class
- `configuration.rb` - Configuration management
- `deprecations.rb` - Deprecation handling
- `errors.rb` - Error definitions
- `engine.rb` - Rails engine
- `version.rb` - Version info
- `inflections.rb` - Rails inflections
- `instrumentation.rb` - Instrumentation
- `resolved_config.rb` - Config resolution
- `llm_tenant.rb` - Tenant management

#### Result Objects (11 files at root)
- `result.rb` - Base result
- `embedding_result.rb`
- `moderation_result.rb`
- `transcription_result.rb`
- `speech_result.rb`
- `image_generation_result.rb`
- `image_variation_result.rb`
- `image_edit_result.rb`
- `image_transform_result.rb`
- `image_upscale_result.rb`
- `image_analysis_result.rb`
- `background_removal_result.rb`
- `image_pipeline_result.rb`

#### Image Agents (7 agents at root)
- `image_generator.rb`
- `image_variator.rb`
- `image_editor.rb`
- `image_transformer.rb`
- `image_upscaler.rb`
- `image_analyzer.rb`
- `background_remover.rb`

#### Audio Agents (2 agents at root)
- `transcriber.rb` - Audio transcription
- `speaker.rb` - Text-to-speech

#### Text Agents (2 agents at root)
- `embedder.rb` - Embedding generation
- `moderator.rb` - Content moderation

#### Infrastructure/Utility (7 files at root)
- `workflow.rb` - Workflow orchestration
- `async.rb` - Async execution
- `cache_helper.rb` - Caching utilities
- `redactor.rb` - Data redaction
- `circuit_breaker.rb` - Circuit breaker pattern
- `budget_tracker.rb` - Budget tracking
- `alert_manager.rb` - Alert management
- `attempt_tracker.rb` - Attempt tracking
- `execution_logger_job.rb` - Logging job
- `image_pipeline.rb` - Image pipeline orchestration

---

## Target Structure

```
lib/ruby_llm/agents/
├── core/                      # Core framework and infrastructure
│   ├── base.rb               # Base agent class
│   ├── configuration.rb
│   ├── errors.rb
│   ├── version.rb
│   ├── deprecations.rb
│   ├── inflections.rb
│   ├── instrumentation.rb
│   ├── resolved_config.rb
│   ├── llm_tenant.rb
│   └── base/                 # Agent base modules
│       ├── dsl.rb
│       ├── execution.rb
│       ├── caching.rb
│       ├── cost_calculation.rb
│       ├── moderation_dsl.rb
│       ├── moderation_execution.rb
│       ├── reliability_dsl.rb
│       ├── reliability_execution.rb
│       ├── response_building.rb
│       └── tool_tracking.rb
│
├── results/                   # All result objects
│   ├── base.rb               # Base result (renamed from result.rb)
│   ├── embedding_result.rb
│   ├── moderation_result.rb
│   ├── transcription_result.rb
│   ├── speech_result.rb
│   ├── image_generation_result.rb
│   ├── image_variation_result.rb
│   ├── image_edit_result.rb
│   ├── image_transform_result.rb
│   ├── image_upscale_result.rb
│   ├── image_analysis_result.rb
│   ├── background_removal_result.rb
│   └── image_pipeline_result.rb
│
├── image/                     # Image agents
│   ├── generator.rb          # Main agent
│   ├── generator/            # Supporting modules
│   │   ├── dsl.rb
│   │   ├── execution.rb
│   │   ├── active_storage_support.rb
│   │   ├── content_policy.rb
│   │   ├── pricing.rb
│   │   └── templates.rb
│   │
│   ├── analyzer.rb
│   ├── analyzer/
│   │   ├── dsl.rb
│   │   └── execution.rb
│   │
│   ├── editor.rb
│   ├── editor/
│   │   ├── dsl.rb
│   │   └── execution.rb
│   │
│   ├── transformer.rb
│   ├── transformer/
│   │   ├── dsl.rb
│   │   └── execution.rb
│   │
│   ├── upscaler.rb
│   ├── upscaler/
│   │   ├── dsl.rb
│   │   └── execution.rb
│   │
│   ├── variator.rb
│   ├── variator/
│   │   ├── dsl.rb
│   │   └── execution.rb
│   │
│   ├── background_remover.rb
│   ├── background_remover/
│   │   ├── dsl.rb
│   │   └── execution.rb
│   │
│   ├── pipeline.rb
│   ├── pipeline/
│   │   ├── dsl.rb
│   │   └── execution.rb
│   │
│   └── concerns/             # Shared image concerns
│       ├── operation_dsl.rb
│       └── operation_execution.rb
│
├── audio/                     # Audio agents
│   ├── speaker.rb
│   ├── speaker/
│   │   ├── dsl.rb
│   │   └── execution.rb
│   │
│   ├── transcriber.rb
│   └── transcriber/
│       ├── dsl.rb
│       └── execution.rb
│
├── text/                      # Text processing agents
│   ├── embedder.rb
│   ├── embedder/
│   │   ├── dsl.rb
│   │   └── execution.rb
│   │
│   ├── moderator.rb
│   └── moderator/            # (if it has dsl/execution, otherwise just the file)
│
├── infrastructure/            # Reliability, budget, async
│   ├── circuit_breaker.rb
│   ├── budget_tracker.rb
│   ├── alert_manager.rb
│   ├── attempt_tracker.rb
│   ├── cache_helper.rb
│   ├── redactor.rb
│   ├── execution_logger_job.rb
│   │
│   ├── budget/
│   │   ├── budget_query.rb
│   │   ├── config_resolver.rb
│   │   ├── forecaster.rb
│   │   └── spend_recorder.rb
│   │
│   └── reliability/
│       ├── breaker_manager.rb
│       ├── execution_constraints.rb
│       ├── executor.rb
│       ├── fallback_routing.rb
│       └── retry_strategy.rb
│
├── workflow/                  # Workflow orchestration (already grouped)
│   ├── orchestrator.rb       # Main entry point (renamed from workflow.rb)
│   ├── async.rb
│   ├── async_executor.rb
│   ├── instrumentation.rb
│   ├── parallel.rb
│   ├── pipeline.rb
│   ├── result.rb
│   ├── router.rb
│   └── thread_pool.rb
│
└── rails/                     # Rails-specific code
    └── engine.rb
```

---

## Trade-offs Analysis

| Aspect | Flat (Current) | Grouped (Target) |
|--------|----------------|------------------|
| Simple requires | ✓ | ✗ Longer paths |
| Easy grep/find | ✓ | ✓ Still easy with patterns |
| Scales at 60+ files | ✗ Noisy | ✓ Clear groupings |
| See related items | ✗ Hard | ✓ Obvious |
| Add new agents | ✗ Where does it go? | ✓ Clear categories |
| Namespacing | ✗ All in one | ✓ Logical modules |
| Mental model | ✗ Everything flat | ✓ Domain-based |

---

## Implementation Plan

### Phase 1: Create New Directory Structure (Non-Breaking)

**Goal:** Create new directories and copy files without breaking existing requires.

#### Step 1.1: Create Directory Structure
```bash
mkdir -p lib/ruby_llm/agents/{core,results,image,audio,text,infrastructure,workflow,rails}
mkdir -p lib/ruby_llm/agents/core/base
mkdir -p lib/ruby_llm/agents/image/{generator,analyzer,editor,transformer,upscaler,variator,background_remover,pipeline,concerns}
mkdir -p lib/ruby_llm/agents/audio/{speaker,transcriber}
mkdir -p lib/ruby_llm/agents/text/{embedder,moderator}
mkdir -p lib/ruby_llm/agents/infrastructure/{budget,reliability}
```

#### Step 1.2: Move Core Files
```ruby
# Files to move to core/
base.rb → core/base.rb
configuration.rb → core/configuration.rb
errors.rb → core/errors.rb
version.rb → core/version.rb
deprecations.rb → core/deprecations.rb
inflections.rb → core/inflections.rb
instrumentation.rb → core/instrumentation.rb
resolved_config.rb → core/resolved_config.rb
llm_tenant.rb → core/llm_tenant.rb
base/*.rb → core/base/*.rb
```

#### Step 1.3: Move Result Files
```ruby
# Files to move to results/
result.rb → results/base.rb
*_result.rb → results/*_result.rb
```

#### Step 1.4: Move Image Agent Files
```ruby
# Files to move to image/
image_generator.rb → image/generator.rb
image_generator/*.rb → image/generator/*.rb
image_analyzer.rb → image/analyzer.rb
image_analyzer/*.rb → image/analyzer/*.rb
# ... same pattern for all image agents
concerns/image_*.rb → image/concerns/*.rb
```

#### Step 1.5: Move Audio Agent Files
```ruby
# Files to move to audio/
speaker.rb → audio/speaker.rb
speaker/*.rb → audio/speaker/*.rb
transcriber.rb → audio/transcriber.rb
transcriber/*.rb → audio/transcriber/*.rb
```

#### Step 1.6: Move Text Agent Files
```ruby
# Files to move to text/
embedder.rb → text/embedder.rb
embedder/*.rb → text/embedder/*.rb
moderator.rb → text/moderator.rb
```

#### Step 1.7: Move Infrastructure Files
```ruby
# Files to move to infrastructure/
circuit_breaker.rb → infrastructure/circuit_breaker.rb
budget_tracker.rb → infrastructure/budget_tracker.rb
alert_manager.rb → infrastructure/alert_manager.rb
attempt_tracker.rb → infrastructure/attempt_tracker.rb
cache_helper.rb → infrastructure/cache_helper.rb
redactor.rb → infrastructure/redactor.rb
execution_logger_job.rb → infrastructure/execution_logger_job.rb
budget/*.rb → infrastructure/budget/*.rb
reliability/*.rb → infrastructure/reliability/*.rb
```

#### Step 1.8: Move Workflow Files
```ruby
# Files to move/reorganize in workflow/
workflow.rb → workflow/orchestrator.rb
async.rb → workflow/async.rb
# workflow/*.rb already in place
```

#### Step 1.9: Move Rails Files
```ruby
engine.rb → rails/engine.rb
```

---

### Phase 2: Update Require Paths

#### Step 2.1: Update Main Entry Point

Update `lib/ruby_llm/agents.rb` to require from new paths:

```ruby
# lib/ruby_llm/agents.rb

# Core
require_relative "agents/core/version"
require_relative "agents/core/configuration"
require_relative "agents/core/errors"
require_relative "agents/core/deprecations"
require_relative "agents/core/instrumentation"
require_relative "agents/core/resolved_config"
require_relative "agents/core/llm_tenant"

# Core base modules
require_relative "agents/core/base/dsl"
require_relative "agents/core/base/execution"
require_relative "agents/core/base/caching"
# ... etc

require_relative "agents/core/base"

# Results
require_relative "agents/results/base"
require_relative "agents/results/embedding_result"
require_relative "agents/results/moderation_result"
# ... etc

# Infrastructure
require_relative "agents/infrastructure/circuit_breaker"
require_relative "agents/infrastructure/budget_tracker"
# ... etc

# Image agents
require_relative "agents/image/concerns/operation_dsl"
require_relative "agents/image/concerns/operation_execution"
require_relative "agents/image/generator"
require_relative "agents/image/analyzer"
# ... etc

# Audio agents
require_relative "agents/audio/speaker"
require_relative "agents/audio/transcriber"

# Text agents
require_relative "agents/text/embedder"
require_relative "agents/text/moderator"

# Workflow
require_relative "agents/workflow/orchestrator"
require_relative "agents/workflow/async"
# ... etc

# Rails integration (conditional)
if defined?(Rails)
  require_relative "agents/rails/engine"
end
```

#### Step 2.2: Create Compatibility Layer (Deprecation Period)

Create forwarding files at old locations:

```ruby
# lib/ruby_llm/agents/image_generator.rb (compatibility shim)
require_relative "image/generator"

warn "[DEPRECATION] RubyLLM::Agents::ImageGenerator path changed. " \
     "Use 'ruby_llm/agents/image/generator' instead. " \
     "This shim will be removed in v1.0."

# Alias for backward compatibility
module RubyLLM
  module Agents
    ImageGenerator = Image::Generator unless defined?(ImageGenerator)
  end
end
```

---

### Phase 3: Update Module Namespacing

#### Current Namespacing
```ruby
module RubyLLM
  module Agents
    class ImageGenerator < Base
    end
  end
end
```

#### New Namespacing Option A (Nested Modules)
```ruby
module RubyLLM
  module Agents
    module Image
      class Generator < Base
      end
    end
  end
end

# Usage: RubyLLM::Agents::Image::Generator
```

#### New Namespacing Option B (Keep Flat, Just Reorganize Files)
```ruby
module RubyLLM
  module Agents
    class ImageGenerator < Base  # Same class name
    end
  end
end

# Usage: RubyLLM::Agents::ImageGenerator (unchanged)
```

**Recommendation:** Option B for this phase - reorganize files without changing namespaces to minimize breaking changes. Option A can be considered for v2.0.

---

### Phase 4: Update Internal References

#### Step 4.1: Update require_relative calls in all files
Each file needs its internal requires updated:

```ruby
# Before (in image_generator.rb)
require_relative "base"
require_relative "image_generator/dsl"

# After (in image/generator.rb)
require_relative "../core/base"
require_relative "generator/dsl"
```

#### Step 4.2: Update autoload declarations (if any)

#### Step 4.3: Update spec file locations
```
spec/ruby_llm/agents/
├── core/
│   └── base_spec.rb
├── results/
│   └── *_spec.rb
├── image/
│   ├── generator_spec.rb
│   ├── analyzer_spec.rb
│   └── ...
├── audio/
│   ├── speaker_spec.rb
│   └── transcriber_spec.rb
├── text/
│   ├── embedder_spec.rb
│   └── moderator_spec.rb
└── ...
```

---

### Phase 5: Update Generators

Update Rails generators to reflect new paths (optional if keeping flat namespace):

```ruby
# lib/generators/ruby_llm_agents/image_generator/image_generator_generator.rb
# Templates reference new internal structure but generate same user-facing code
```

---

### Phase 6: Documentation Updates

- [ ] Update README with new structure diagram
- [ ] Update CHANGELOG with migration notes
- [ ] Update any architecture documentation
- [ ] Add deprecation warnings documentation

---

## File Mapping Reference

### Complete Old → New Mapping

| Old Path | New Path |
|----------|----------|
| `base.rb` | `core/base.rb` |
| `configuration.rb` | `core/configuration.rb` |
| `errors.rb` | `core/errors.rb` |
| `version.rb` | `core/version.rb` |
| `deprecations.rb` | `core/deprecations.rb` |
| `inflections.rb` | `core/inflections.rb` |
| `instrumentation.rb` | `core/instrumentation.rb` |
| `resolved_config.rb` | `core/resolved_config.rb` |
| `llm_tenant.rb` | `core/llm_tenant.rb` |
| `base/*.rb` | `core/base/*.rb` |
| `result.rb` | `results/base.rb` |
| `*_result.rb` | `results/*_result.rb` |
| `image_generator.rb` | `image/generator.rb` |
| `image_generator/*.rb` | `image/generator/*.rb` |
| `image_analyzer.rb` | `image/analyzer.rb` |
| `image_analyzer/*.rb` | `image/analyzer/*.rb` |
| `image_editor.rb` | `image/editor.rb` |
| `image_editor/*.rb` | `image/editor/*.rb` |
| `image_transformer.rb` | `image/transformer.rb` |
| `image_transformer/*.rb` | `image/transformer/*.rb` |
| `image_upscaler.rb` | `image/upscaler.rb` |
| `image_upscaler/*.rb` | `image/upscaler/*.rb` |
| `image_variator.rb` | `image/variator.rb` |
| `image_variator/*.rb` | `image/variator/*.rb` |
| `image_pipeline.rb` | `image/pipeline.rb` |
| `image_pipeline/*.rb` | `image/pipeline/*.rb` |
| `background_remover.rb` | `image/background_remover.rb` |
| `background_remover/*.rb` | `image/background_remover/*.rb` |
| `concerns/image_*.rb` | `image/concerns/*.rb` |
| `speaker.rb` | `audio/speaker.rb` |
| `speaker/*.rb` | `audio/speaker/*.rb` |
| `transcriber.rb` | `audio/transcriber.rb` |
| `transcriber/*.rb` | `audio/transcriber/*.rb` |
| `embedder.rb` | `text/embedder.rb` |
| `embedder/*.rb` | `text/embedder/*.rb` |
| `moderator.rb` | `text/moderator.rb` |
| `circuit_breaker.rb` | `infrastructure/circuit_breaker.rb` |
| `budget_tracker.rb` | `infrastructure/budget_tracker.rb` |
| `alert_manager.rb` | `infrastructure/alert_manager.rb` |
| `attempt_tracker.rb` | `infrastructure/attempt_tracker.rb` |
| `cache_helper.rb` | `infrastructure/cache_helper.rb` |
| `redactor.rb` | `infrastructure/redactor.rb` |
| `execution_logger_job.rb` | `infrastructure/execution_logger_job.rb` |
| `budget/*.rb` | `infrastructure/budget/*.rb` |
| `reliability/*.rb` | `infrastructure/reliability/*.rb` |
| `workflow.rb` | `workflow/orchestrator.rb` |
| `async.rb` | `workflow/async.rb` |
| `workflow/*.rb` | `workflow/*.rb` (already there) |
| `engine.rb` | `rails/engine.rb` |

---

## Rollback Plan

If issues arise, the restructure can be rolled back by:

1. Reverting the file moves (git history)
2. Removing compatibility shims
3. Restoring original `agents.rb` requires

---

## Success Criteria

- [ ] All existing tests pass without modification
- [ ] No breaking changes to public API
- [ ] Deprecation warnings for old paths
- [ ] CI/CD pipeline passes
- [ ] Example app works without changes
- [ ] Documentation updated

---

## Timeline Suggestion

1. **Phase 1-2**: Core restructure and require updates (1-2 days)
2. **Phase 3**: Compatibility layer (0.5 day)
3. **Phase 4**: Internal reference updates (1 day)
4. **Phase 5**: Generator updates (0.5 day)
5. **Phase 6**: Documentation (0.5 day)
6. **Testing & QA**: (1-2 days)

---

## Open Questions

1. **Namespace change?** Should we introduce `RubyLLM::Agents::Image::Generator` or keep `RubyLLM::Agents::ImageGenerator`?
   - Recommendation: Keep existing names for v0.x, consider namespacing for v1.0

2. **Deprecation period?** How long should compatibility shims exist?
   - Recommendation: At least 2 minor versions or 3 months

3. **Spec file locations?** Should spec files mirror the new structure?
   - Recommendation: Yes, for consistency

4. **Rails engine location?** Should `engine.rb` be in `rails/` or stay at root?
   - Recommendation: Move to `rails/` for consistency
