# Plan: Remove Workflows From ruby_llm-agents

## Goal
Remove the workflow subsystem while keeping the core agent DSL, execution tracking, dashboards, and other non-workflow features intact.

## Scope Decisions
- Remove workflow runtime code, DSL, and helpers.
- Remove workflow generators and templates.
- Remove workflow docs and README references.
- Remove workflow-related config paths and metadata.
- Remove workflow-related tests/specs.
- Keep image pipelines or other non-workflow pipelines only if they do not depend on workflow classes.
- Hard removal (no deprecation warnings) — this is a breaking change for a major version bump.

## Plan

### Phase 1: Audit

1. **Comprehensive inventory of workflow touchpoints**
   - Search for `workflow` references in `lib/`, `app/`, `config/`, `spec/`, and docs.
   - Identify database columns/tables: `workflow_id`, `workflow_type`, `workflow_step`, etc.
   - List ActiveSupport::Notifications, instrumentation hooks, and callbacks related to workflows.
   - Check for service objects, background jobs, or concerns outside `workflow/` that reference workflows.
   - Document all findings before making any changes.

### Phase 2: Code Removal

2. **Remove runtime workflow code**
   - Delete `lib/ruby_llm/agents/workflow/` directory.
   - Delete `lib/ruby_llm/agents/workflow.rb` if present.
   - Remove workflow requires/autoloads from `lib/ruby_llm/agents.rb`.
   - Remove engine hooks that load workflow orchestration.

3. **Remove workflow generators and templates**
   - Delete workflow-related generators (e.g., `application_workflow` templates).
   - Delete workflow migration templates.
   - Remove entries from generator manifests if any.

4. **Remove workflow configuration and routing**
   - Remove `app/workflows` autoload paths from engine configuration.
   - Remove workflow-specific config options and defaults.

5. **Remove instrumentation and callbacks**
   - Remove workflow-related ActiveSupport::Notifications subscribers.
   - Remove workflow lifecycle callbacks from models.
   - Remove any workflow-specific logging or metrics hooks.

6. **Clean up execution metadata and models**
   - Remove workflow-specific columns from migration templates (e.g., `workflow_id`, `workflow_type`, `workflow_step`).
   - Remove workflow-specific logic from execution models.
   - Remove any workflow associations or scopes.

### Phase 3: Tests and Documentation

7. **Update tests/specs**
   - Delete workflow specs and fixtures.
   - Remove workflow factories if using FactoryBot.
   - Update shared helpers that referenced workflows.
   - Run full test suite to catch any missed dependencies.

8. **Update documentation**
   - Remove workflow sections from `README.md`.
   - Remove wiki/guide references to workflows.
   - Add upgrade guide section (see below).

### Phase 4: Release

9. **Provide migration guidance for existing apps**
   - Document SQL to drop workflow tables/columns for apps that have them:
     ```sql
     -- Example cleanup for existing apps
     ALTER TABLE agent_executions DROP COLUMN workflow_id;
     ALTER TABLE agent_executions DROP COLUMN workflow_type;
     ALTER TABLE agent_executions DROP COLUMN workflow_step;
     DROP TABLE workflows;  -- if exists
     ```
   - Note: We do NOT provide a Rails migration — apps should manage their own cleanup.

10. **Final verification**
    - `bundle exec rake` passes.
    - `bundle exec rspec` passes.
    - Manual smoke test of agent execution without workflows.
    - Verify gemspec includes correct file list.

11. **Release prep**
    - Update `CHANGELOG.md` with breaking-change note under a new major version.
    - Bump version (major version bump due to breaking change).
    - Tag release and publish.

## Decisions (Resolved)
| Question | Decision |
|----------|----------|
| Preserve pipeline/orchestration features? | Only if they don't depend on workflow classes. Audit will determine. |
| Soft-deprecate or hard-remove? | Hard-remove. This is a major version bump. |
| Migration/compat layer for existing apps? | No Rails migration. Provide SQL snippets in upgrade guide instead. |
