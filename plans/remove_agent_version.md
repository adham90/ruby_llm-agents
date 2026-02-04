# Plan: Remove `version` DSL Method

## Goal
Remove the `version` DSL method from agents to simplify the API surface.

## Background
The `version` DSL was originally intended for cache invalidation (bump version to invalidate cached responses). In practice:
- Cache invalidation is better handled by content-based cache keys
- The `agent_version` field in execution records adds little value
- Users who need traceability can use `execution_metadata` with Git SHA

## Scope
- Remove `version` DSL method from all agent types
- Remove `agent_version` from execution records and instrumentation
- Remove `by_version` scope and analytics methods
- Update docs, examples, generators, and tests
- Add migration note to CHANGELOG

---

## Detailed Plan

### 1. Remove DSL methods

#### 1.1 Base DSL (`lib/ruby_llm/agents/dsl/base.rb`)
- Delete `version` method (lines 46-49)
- Remove from example in module docs (line 19)
- Remove YARD example (line 45)

#### 1.2 Image Operation DSL (`lib/ruby_llm/agents/image/concerns/image_operation_dsl.rb`)
- Delete `version` method (line 29)

#### 1.3 Image Pipeline DSL (`lib/ruby_llm/agents/image/pipeline/dsl.rb`)
- Delete `version` method (line 110)
- Remove from example in module docs (line 17)

#### 1.4 Main DSL module (`lib/ruby_llm/agents/dsl.rb`)
- Remove `version "2.0"` from example (line 25)

### 2. Remove from cache key generation

#### 2.1 Base Agent (`lib/ruby_llm/agents/base_agent.rb`)
- Remove `self.class.version` from cache key (line 296)
- Remove from example docs (line 18)

#### 2.2 Text Embedder (`lib/ruby_llm/agents/text/embedder.rb`)
- Remove `self.class.version` from cache key (line 260)

#### 2.3 Audio Transcriber (`lib/ruby_llm/agents/audio/transcriber.rb`)
- Remove `self.class.version` from cache key (line 358)

#### 2.4 Audio Speaker (`lib/ruby_llm/agents/audio/speaker.rb`)
- Remove `self.class.version` from cache key (line 356)

#### 2.5 Image Generator (`lib/ruby_llm/agents/image/generator.rb`)
- Remove `self.class.version` from cache key (line 278)

#### 2.6 Image operations (execution files)
- `lib/ruby_llm/agents/image/editor/execution.rb` (line 168)
- `lib/ruby_llm/agents/image/upscaler/execution.rb` (line 189)
- `lib/ruby_llm/agents/image/pipeline/execution.rb` (line 252)
- `lib/ruby_llm/agents/image/variator/execution.rb` (line 159)
- `lib/ruby_llm/agents/image/transformer/execution.rb` (line 183)
- `lib/ruby_llm/agents/image/background_remover/execution.rb` (line 206)
- `lib/ruby_llm/agents/image/analyzer/execution.rb` (line 368)

### 3. Remove from instrumentation

#### 3.1 Core Instrumentation (`lib/ruby_llm/agents/core/instrumentation.rb`)
- Remove `agent_version: self.class.version` from `create_running_execution` (line 243)
- Remove from `legacy_log_execution` (line 502)
- Remove from `record_cache_hit_execution` (line 858)

#### 3.2 Pipeline Instrumentation (`lib/ruby_llm/agents/pipeline/middleware/instrumentation.rb`)
- Remove `agent_version: config(:version, "1.0")` (lines 191, 318)

### 4. Remove from execution model

#### 4.1 Execution model (`app/models/ruby_llm/agents/execution.rb`)
- Remove `@!attribute [rw] agent_version` docs (line 11)
- Remove `validates :agent_version, presence: true` (line 88)

#### 4.2 Execution scopes (`app/models/ruby_llm/agents/execution/scopes.rb`)
- Remove `by_version` scope (line 92)
- Remove YARD docs for `by_version` (line 82)

#### 4.3 Execution analytics (`app/models/ruby_llm/agents/execution/analytics.rb`)
- Update `compare_versions` method - remove or deprecate (lines 94-95)
- Remove `version_trend_data` method (line 118+)

### 5. Remove from controllers

#### 5.1 Agents controller (`app/controllers/ruby_llm/agents/agents_controller.rb`)
- Remove `agent_version` from version filtering (lines 121, 124, 164)

#### 5.2 Executions controller (`app/controllers/ruby_llm/agents/executions_controller.rb`)
- Remove `agent_version` from CSV_COLUMNS (line 19)
- Remove from CSV export (line 101)

#### 5.3 Sortable concern (`app/controllers/concerns/ruby_llm/agents/sortable.rb`)
- Remove `"agent_version"` from ALLOWED_SORT_COLUMNS (line 25)

### 6. Remove from views

#### 6.1 Execution partial (`app/views/ruby_llm/agents/executions/_execution.html.erb`)
- Remove `v<%= execution.agent_version %>` (line 15)

#### 6.2 Execution show (`app/views/ruby_llm/agents/executions/show.html.erb`)
- Remove version display (lines 61, 91, 860, 1127)

#### 6.3 Execution list (`app/views/ruby_llm/agents/executions/_list.html.erb`)
- Remove version column header (line 25)
- Remove version display (line 89)

### 7. Update generators

#### 7.1 Migration template (`lib/generators/ruby_llm_agents/templates/migration.rb.tt`)
- Remove `t.string :agent_version, null: false, default: "1.0"` (line 8)

#### 7.2 Agent template (`lib/generators/ruby_llm_agents/templates/agent.rb.tt`)
- Remove `version "1.0"` (line 17)

#### 7.3 Image pipeline template (`lib/generators/ruby_llm_agents/templates/image_pipeline.rb.tt`)
- Remove `version "1.0"` (line 40)

#### 7.4 Application image pipeline template (`lib/generators/ruby_llm_agents/templates/application_image_pipeline.rb.tt`)
- Remove version comment (line 50)

#### 7.5 Skills AGENTS.md template (`lib/generators/ruby_llm_agents/templates/skills/AGENTS.md.tt`)
- Remove `version "1.0"` example (line 18)
- Remove version from DSL table (line 63)

#### 7.6 Skills IMAGE_PIPELINES.md template (`lib/generators/ruby_llm_agents/templates/skills/IMAGE_PIPELINES.md.tt`)
- Remove `version "1.0"` (line 132)

### 8. Update example app

#### 8.1 Example migration (`example/db/migrate/20260102231924_create_ruby_llm_agents_executions.rb`)
- Remove `agent_version` column (line 8)
- Remove index on `agent_type, agent_version` (line 90)

#### 8.2 Example schema (`example/db/schema.rb`)
- Remove `agent_version` column (line 33)
- Remove index (line 89)

#### 8.3 Example seeds (`example/db/seeds.rb`)
- Remove `agent_version: '1.0'` from all seed records (lines 21, 987, 1021, 1052, 1084, 1124, 1297)

#### 8.4 Example agents
- `example/app/agents/application_agent.rb` - remove version comment (line 17)
- `example/app/agents/images/application_image_analyzer.rb` (line 16)
- `example/app/agents/audio/application_speaker.rb` (line 20)
- `example/app/agents/images/application_background_remover.rb` (line 15)
- `example/app/agents/audio/application_transcriber.rb` (line 16)
- `example/app/agents/images/application_image_generator.rb` (line 18)
- `example/app/agents/images/application_image_pipeline.rb` (line 49)
- `example/app/agents/embedders/application_embedder.rb` (line 17)

### 9. Update wiki docs

- `wiki/Database-Queries.md` - remove `agent_version` from schema table (line 18), remove `by_version` example (line 88)
- `wiki/Caching.md` - remove version examples (lines 92, 98, 163, 330)
- `wiki/API-Reference.md` - remove `version "1.0"` (line 32), remove `by_version` (line 304)
- `wiki/Best-Practices.md` - remove version example (line 38)
- `wiki/Agent-DSL.md` - remove version examples (lines 61, 506)
- `wiki/Thinking.md` - remove `version "1.0"` (line 222)
- `wiki/First-Agent.md` - remove version examples (lines 29, 116)
- `wiki/Audio.md` - remove version examples (lines 68, 241)
- `wiki/Troubleshooting.md` - remove version example (line 166)
- `wiki/Image-Generation.md` - remove version examples (lines 117, 1554, 1720, 1731, 1803, 1833, 1867)
- `wiki/Getting-Started.md` - remove `version "1.0"` (line 85)
- `wiki/Execution-Tracking.md` - remove `by_version` example (line 227)

### 10. Update specs

#### 10.1 Test schema/support files
- `spec/support/schema_builder.rb` - remove `agent_version` column (line 21), remove index (line 64)
- `spec/support/migration_test_data.rb` - remove `agent_version` from all test data
- `spec/dummy/db/schema.rb` - remove `agent_version` (line 10)
- `spec/dummy/app/agents/test_agent.rb` - remove `version "1.0"` (line 7)

#### 10.2 Factories
- `spec/factories/executions.rb` - remove `agent_version { "1.0" }` (line 6)

#### 10.3 Model specs
- `spec/models/execution_spec.rb` - remove `by_version` spec (lines 159-165)
- `spec/models/tenant_spec.rb` - remove all `agent_version: "1.0"` occurrences
- `spec/models/tenant_budget_backward_compat_spec.rb` - remove `agent_version` (line 124)
- `spec/models/tenant_resettable_spec.rb` - remove `agent_version` (lines 100, 105)
- `spec/models/execution/analytics_spec.rb` - remove/update version tests (lines 99-100)

#### 10.4 Instrumentation specs
- `spec/lib/instrumentation_spec.rb` - remove version assertions (lines 14, 1185, 1277, 1374, 1562)
- `spec/jobs/execution_logger_job_spec.rb` - remove `agent_version` (line 11)

#### 10.5 Agent specs (remove `version` DSL usage)
- `spec/lib/base_agent_spec.rb` (lines 26, 175, 366, 385)
- `spec/lib/base_agent_execution_spec.rb` (line 15)
- `spec/agents/base_spec.rb` (line 34)
- `spec/agents/tenant_integration_spec.rb` (lines 37, 69)
- `spec/lib/embedder_spec.rb` (lines 124, 471)
- `spec/lib/transcriber_spec.rb` (lines 134, 539)
- `spec/lib/speaker_spec.rb` (lines 229, 531)
- `spec/concerns/llm_tenant_spec.rb` - remove all `agent_version` occurrences

#### 10.6 Image agent specs
- `spec/agents/image_analyzer_spec.rb` (line 16)
- `spec/agents/image_pipeline_spec.rb` (lines 63, 249)
- `spec/agents/background_remover_spec.rb` (line 18)
- `spec/agents/image_upscaler_spec.rb` (line 14)
- `spec/agents/image_variator_spec.rb` (line 13)
- `spec/lib/image/concerns/image_operation_dsl_spec.rb` (lines 36, 95)
- `spec/lib/image/pipeline_execution_spec.rb` (lines 13, 26, 39)
- `spec/lib/image/upscaler_execution_spec.rb` (line 13)
- `spec/lib/image/variator_execution_spec.rb` (line 13)
- `spec/lib/image/editor/dsl_spec.rb` (line 50)
- `spec/lib/image/background_remover_execution_spec.rb` (line 13)
- `spec/lib/image/upscaler/dsl_spec.rb` (line 114)
- `spec/lib/image/transformer_execution_spec.rb` (line 13)
- `spec/lib/image/editor_execution_spec.rb` (line 13)
- `spec/lib/image/analyzer_execution_spec.rb` (line 13)
- `spec/lib/image_generator/active_storage_support_spec.rb` (line 12)

#### 10.7 Generator specs
- `spec/generators/agent_generator_spec.rb` - remove version expectation (line 27)

### 11. Update other files

#### 11.1 Core base docs (`lib/ruby_llm/agents/core/base.rb`)
- Remove `version "1.0"` from example (line 16)

#### 11.2 Cache middleware (`lib/ruby_llm/agents/pipeline/middleware/cache.rb`)
- Remove version comment (line 29)

#### 11.3 Plans
- `plans/ideal_database_schema.md` - remove `agent_version` (line 17)
- `plans/10_router_agent.md` - remove `version "1.0"` (line 24)

---

## 12. CHANGELOG entry

```markdown
### Removed

- **Breaking:** Removed `version` DSL method from all agent types. This method was originally intended for cache invalidation but added complexity without significant benefit.

  **Migration:** If you need traceability, use `execution_metadata` instead:

  ```ruby
  class ApplicationAgent < RubyLLM::Agents::BaseAgent
    def execution_metadata
      {
        git_sha: ENV['GIT_SHA'] || `git rev-parse --short HEAD 2>/dev/null`.strip.presence,
        deploy_version: ENV['DEPLOY_VERSION']
      }.compact
    end
  end
  ```

  For cache invalidation, the cache key now uses content-based hashing. To manually invalidate caches, clear your Rails cache or use a cache namespace.

- Removed `agent_version` column from executions table. Existing data will remain but new executions won't populate this field.
- Removed `by_version` scope from `Execution` model.
- Removed version filtering from dashboard.
```

---

## 13. Database migration note for users

Add to upgrade generator or release notes:

```ruby
# Optional: Remove agent_version column (safe to leave in place)
class RemoveAgentVersionFromExecutions < ActiveRecord::Migration[7.0]
  def change
    safety_assured do
      remove_index :ruby_llm_agents_executions, [:agent_type, :agent_version], if_exists: true
      remove_column :ruby_llm_agents_executions, :agent_version, :string
    end
  end
end
```
