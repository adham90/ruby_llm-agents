# Plan: Remove Agent Version From DSL

## Goal
Remove the agent-level `version` DSL feature to simplify the API surface, while preserving traceability via Git or custom metadata.

## Scope Decisions
- Remove `version` DSL method and any references in code, docs, and generators.
- Remove any persistence of `agent_version` in execution records (if present).
- Provide a short migration note suggesting Git commit tracking or a custom `metadata` field.

## Detailed Plan

### 1. Inventory references
- Search for:
  - `version` DSL method definition and usage in `lib/ruby_llm/agents/dsl/*`
  - Execution tracking fields storing agent version
  - Dashboard/UI references to version
  - Docs and examples mentioning `version`

### 2. Remove DSL support
- Delete `version` DSL method and any supporting accessors.
- Remove any default config related to version.
- Ensure class-level inheritance doesn’t expose `version` anymore.

### 3. Remove persistence and model fields
- Remove `agent_version` (or similar) from execution attributes and logging payloads.
- If migrations/templates add version columns, remove those templates and notes.

### 4. Update docs and examples
- Remove `version "1.0"` from README examples.
- Add a short note: use Git SHA, deploy version, or custom metadata for traceability.

### 5. Update tests
- Remove specs that assert `version` exists or is logged.
- Update any fixtures referencing version.

### 6. Add upgrade note
- Document breaking change in `CHANGELOG.md`.
- Provide a migration snippet to store Git SHA in metadata if needed.

## Open Questions
- Do we want to replace it with a generic `metadata` DSL (lightweight)?
- Should we add a helper for automatically attaching Git SHA (optional)?
