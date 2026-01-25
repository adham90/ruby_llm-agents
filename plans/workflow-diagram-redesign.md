# Workflow Diagram Redesign Plan

## Goal

Redesign the workflow structure preview to help users **understand workflows at a glance**. Users should immediately grasp what happens, in what order, under what conditions, and how data flows.

---

## Current Problems

1. **Horizontal layout** - Unnatural reading direction, requires scrolling
2. **Cryptic badges** - Icons like `⟳` require memorization
3. **Hidden complexity** - Sub-workflows show only a name, not what's inside
4. **No iteration visibility** - `each:` loops look like regular steps
5. **Cramped parallel groups** - Hard to see concurrent execution
6. **No data flow** - Can't see what goes in/out of each step
7. **Badge overload** - Too many tiny badges compete for attention

---

## Design Principles

1. **Vertical flow** - Top-to-bottom like reading code
2. **Spell it out** - Use words, not just icons
3. **Show what's inside** - Expandable sub-workflows and iterations
4. **Visual hierarchy** - Important info stands out
5. **Consistent visual language** - Same colors/shapes mean same things
6. **Progressive disclosure** - Summary first, details on demand

---

## Visual Language

### Step Types (Border/Background)

| Type | Border | Background | Icon |
|------|--------|------------|------|
| Sequential | `border-slate-300` | `bg-white` | None |
| Sub-workflow | `border-emerald-400` | `bg-emerald-50` | `⬡` |
| Iteration | `border-blue-400` | `bg-blue-50` | `∀` |
| Parallel group | `border-purple-400` | `bg-purple-50` | `⫴` |
| Routing | `border-amber-400` | `bg-amber-50` | `↗` |
| Block (custom) | `border-violet-400` | `bg-violet-50` | `{ }` |

### Status Indicators

| Feature | Display |
|---------|---------|
| Retry | `⟳ Retry 3× on failure` (spelled out) |
| Timeout | `⏱ Timeout: 30s` |
| Conditional | `⚡ if: condition` or `⚡ unless: condition` |
| Optional | Dashed border + `(optional)` label |
| Fallback | `↩ Fallback: AgentName` |

---

## Component Structure

### 1. Workflow Header

```
┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓
┃  WORKFLOW NAME                                         v1.0     ┃
┃  Description of what this workflow does                         ┃
┃                                                                 ┃
┃  ⏱ 2min timeout    💰 $0.50 max    📊 5 steps    ⫴ 1 parallel   ┃
┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛
```

### 2. Start Node

```
                            ┌───────┐
                            │ START │
                            └───┬───┘
                                │
```

### 3. Sequential Step Card

```
┌─────────────────────────────────────────────────────────────────┐
│  1. STEP NAME                                                   │
│  ════════════                                                   │
│  🤖 AgentClassName                                              │
│                                                                 │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │ 📥 Input: field1, field2, field3                         │   │
│  │ 📤 Output: { result, data }                              │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
│  ⟳ Retry 3× on failure    ⏱ Timeout: 30s    ⚡ if: condition   │
└─────────────────────────────────────────────────────────────────┘
```

### 4. Sub-workflow Step (Expandable)

```
╔═════════════════════════════════════════════════════════════════╗
║  2. STEP NAME                                       ⬡ Workflow  ║
║  ════════════                                                   ║
║  📦 SubWorkflowClassName                                        ║
║                                                                 ║
║  ┌ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ┐  ║
║    NESTED WORKFLOW (3 steps)                    [▼ Expand]    ║
║                                                               ║
║    ┌──────────┐     ┌──────────┐     ┌──────────┐            ║
║    │  step 1  │ ──▶ │  step 2  │ ──▶ │  step 3  │            ║
║    └──────────┘     └──────────┘     └──────────┘            ║
║  └ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ┘  ║
║                                                                 ║
║  ┌─────────────────────────────────────────────────────────┐   ║
║  │ 📥 Receives: address, items                              │   ║
║  │ 📤 Returns: { carrier, tracking, cost }                  │   ║
║  │ 💰 Inherits: $0.25 remaining budget                      │   ║
║  │ ⏱ Inherits: 45s remaining timeout                        │   ║
║  └─────────────────────────────────────────────────────────┘   ║
╚═════════════════════════════════════════════════════════════════╝
```

### 5. Iteration Step

```
┌─────────────────────────────────────────────────────────────────┐
│  3. STEP NAME                                       ∀ Iteration │
│  ════════════                                                   │
│  🤖 AgentClassName                                              │
│                                                                 │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │  FOR EACH item IN: input.items                           │   │
│  │                                                          │   │
│  │    ┌─────┐ ┌─────┐ ┌─────┐ ┌─────┐ ┌─────┐              │   │
│  │    │  1  │ │  2  │ │  3  │ │  4  │ │ ... │  → N items   │   │
│  │    └──┬──┘ └──┬──┘ └──┬──┘ └──┬──┘ └─────┘              │   │
│  │       │       │       │       │                          │   │
│  │       └───────┴───┬───┴───────┘                          │   │
│  │                   │                                      │   │
│  │           Run 5 at a time (concurrent)                   │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
│  ✅ continue_on_error    ✗ fail_fast                            │
└─────────────────────────────────────────────────────────────────┘
```

### 6. Parallel Group

```
┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓
┃  4. GROUP NAME                                      ⫴ Parallel  ┃
┃  ═════════════                                                  ┃
┃                                                                 ┃
┃  Runs simultaneously:                                           ┃
┃                                                                 ┃
┃  ┌────────────────┐  ┌────────────────┐  ┌────────────────┐    ┃
┃  │   STEP A       │  │   STEP B       │  │   STEP C       │    ┃
┃  │   AgentA       │  │   AgentB       │  │   AgentC       │    ┃
┃  │   (optional)   │  │                │  │   (optional)   │    ┃
┃  └───────┬────────┘  └───────┬────────┘  └───────┬────────┘    ┃
┃          │                   │                   │              ┃
┃          └───────────────────┼───────────────────┘              ┃
┃                              │                                  ┃
┃                         WAIT FOR ALL                            ┃
┃                                                                 ┃
┃  ⚡ fail_fast: false    ⏱ Timeout: 60s    Max concurrency: 3    ┃
┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛
```

### 7. Routing Step (Decision)

```
┌─────────────────────────────────────────────────────────────────┐
│  5. STEP NAME                                       ↗ Routing   │
│  ════════════                                                   │
│                                                                 │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │  DECIDE based on: classify.type                          │   │
│  │                                                          │   │
│  │                 ┌─────────────┐                          │   │
│  │                 │ What type?  │                          │   │
│  │                 └──────┬──────┘                          │   │
│  │        ┌───────────────┼───────────────┐                 │   │
│  │        ▼               ▼               ▼                 │   │
│  │   ┌─────────┐    ┌─────────┐    ┌─────────┐             │   │
│  │   │:premium │    │:standard│    │:default │             │   │
│  │   │    ↓    │    │    ↓    │    │    ↓    │             │   │
│  │   │ Premium │    │ Standard│    │  Basic  │             │   │
│  │   │  Agent  │    │  Agent  │    │  Agent  │             │   │
│  │   └─────────┘    └─────────┘    └─────────┘             │   │
│  └─────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────┘
```

### 8. Block Step (Custom Code)

```
┌─────────────────────────────────────────────────────────────────┐
│  6. STEP NAME                                       { } Block   │
│  ════════════                                                   │
│  📝 Custom Ruby block                                           │
│                                                                 │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │ Available actions:                                       │   │
│  │   skip!(reason, default: value)  - Skip this step        │   │
│  │   halt!(result: {})              - Stop workflow early   │   │
│  │   fail!(message)                 - Abort with error      │   │
│  └─────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────┘
```

### 9. End Node

```
                                │
                            ┌───┴───┐
                            │  END  │
                            └───────┘
```

### 10. Connecting Lines

```
Sequential:
    │
    ▼

Fork (parallel/routing):
    │
    ├─────────────┬─────────────┐
    │             │             │
    ▼             ▼             ▼

Join:
    │             │             │
    └─────────────┼─────────────┘
                  │
                  ▼
```

---

## Implementation Phases

### Phase 1: Core Vertical Layout
**Files to modify:**
- `app/views/ruby_llm/agents/workflows/_workflow_diagram.html.erb`

**Tasks:**
1. Replace horizontal flex layout with vertical flex layout
2. Create new step card component with vertical design
3. Add proper connecting lines between steps
4. Style start/end nodes

**Estimated effort:** 2-3 hours

---

### Phase 2: Sub-workflow Visualization
**Files to modify:**
- `app/views/ruby_llm/agents/workflows/_workflow_diagram.html.erb`
- `app/controllers/ruby_llm/agents/workflows_controller.rb`

**Tasks:**
1. Add sub-workflow detection in controller (already done in DSL)
2. Create expandable nested workflow preview component
3. Show budget inheritance indicators
4. Add mini horizontal flow inside sub-workflow card

**Estimated effort:** 2-3 hours

---

### Phase 3: Iteration Visualization
**Files to modify:**
- `app/views/ruby_llm/agents/workflows/_workflow_diagram.html.erb`
- `app/controllers/ruby_llm/agents/workflows_controller.rb`

**Tasks:**
1. Add iteration detection in controller (already done in DSL)
2. Create iteration fan-out visualization
3. Show concurrency indicator
4. Display fail_fast/continue_on_error settings

**Estimated effort:** 1-2 hours

---

### Phase 4: Parallel Group Redesign
**Files to modify:**
- `app/views/ruby_llm/agents/workflows/_workflow_diagram.html.erb`

**Tasks:**
1. Redesign parallel group with horizontal internal layout
2. Add fork/join visual connectors
3. Show "WAIT FOR ALL" indicator
4. Style with purple theme

**Estimated effort:** 1-2 hours

---

### Phase 5: Routing Visualization
**Files to modify:**
- `app/views/ruby_llm/agents/workflows/_workflow_diagram.html.erb`

**Tasks:**
1. Create decision diamond component
2. Show branching paths visually
3. Display route conditions
4. Highlight default route

**Estimated effort:** 1-2 hours

---

### Phase 6: Input/Output Display
**Files to modify:**
- `app/views/ruby_llm/agents/workflows/_workflow_diagram.html.erb`
- `app/controllers/ruby_llm/agents/workflows_controller.rb`

**Tasks:**
1. Extract input schema info for each step
2. Show 📥 Input and 📤 Output boxes in each card
3. Display pick: fields when used
4. Show input: lambda summary

**Estimated effort:** 2 hours

---

### Phase 7: Polish & Interactivity
**Files to modify:**
- `app/views/ruby_llm/agents/workflows/_workflow_diagram.html.erb`

**Tasks:**
1. Add expand/collapse for sub-workflows (Alpine.js)
2. Add hover states with more details
3. Add smooth transitions
4. Test dark mode styling
5. Test responsive behavior

**Estimated effort:** 2 hours

---

## File Changes Summary

### Modified Files
| File | Changes |
|------|---------|
| `_workflow_diagram.html.erb` | Complete rewrite with vertical layout |
| `workflows_controller.rb` | Add sub-workflow/iteration metadata extraction |

### New Files (Optional)
| File | Purpose |
|------|---------|
| `_step_card.html.erb` | Reusable step card partial |
| `_sub_workflow_preview.html.erb` | Nested workflow mini-view |
| `_iteration_visualizer.html.erb` | Iteration fan-out component |
| `_parallel_group.html.erb` | Parallel group component |
| `_routing_decision.html.erb` | Routing decision tree |

---

## Testing Checklist

- [ ] Sequential workflow displays correctly
- [ ] Parallel groups show fork/join
- [ ] Routing shows decision tree
- [ ] Sub-workflows show nested preview
- [ ] Iterations show fan-out
- [ ] Recursion shows depth indicator
- [ ] All badges display correctly
- [ ] Dark mode works
- [ ] Mobile responsive
- [ ] Expand/collapse works
- [ ] Hover states work

---

## Example Workflows to Test

1. `ContentPipelineWorkflow` - Sequential + parallel + routing
2. `OrderProcessingWorkflow` - Sub-workflow composition
3. `BatchProcessorWorkflow` - Iteration patterns
4. `TreeProcessorWorkflow` - Recursion
5. `DocumentPipelineWorkflow` - Combined patterns

---

## Success Criteria

A user looking at the diagram should be able to answer:
1. What does this workflow do? (from header)
2. What are the steps? (from step cards)
3. What order do they run? (from vertical flow)
4. What runs in parallel? (from parallel groups)
5. What conditions exist? (from routing/conditionals)
6. What gets repeated? (from iteration)
7. What's nested inside? (from sub-workflow preview)
8. What can fail? (from retry/fallback/optional indicators)
