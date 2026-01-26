# Workflow Structure Viewer UI Overhaul

## Overview

Enhance the workflow structure viewer to display all DSL features with improved visual design, making it both a functional dashboard and documentation for workflow capabilities.

---

## Current State Analysis

### Data Extraction Gaps (Controller)

The controller (`workflows_controller.rb`) currently extracts limited step metadata:

| Field | Currently Extracted | Available in DSL |
|-------|---------------------|------------------|
| name, agent, description | ✓ | ✓ |
| optional, timeout | ✓ | ✓ |
| routing, parallel, parallel_group | ✓ | ✓ |
| retry_config | ✗ | ✓ |
| fallbacks | ✗ | ✓ |
| if_condition | ✗ | ✓ |
| unless_condition | ✗ | ✓ |
| input_mapper | ✗ | ✓ |
| pick_fields, pick_from | ✗ | ✓ |
| default_value | ✗ | ✓ |
| routes (full config) | ✗ | ✓ |
| custom_block | ✗ | ✓ |
| lifecycle_hooks | ✗ | ✓ |

### UI Gaps (View)

- No lifecycle hooks visualization
- Routes shown as text, not visual branches
- Missing badges for retry, conditions, fallbacks, defaults
- No hover/click details
- No collapsible sections
- Input mappings not indicated

---

## Implementation Plan

### Phase 1: Controller Data Extraction

**File:** `app/controllers/ruby_llm/agents/workflows_controller.rb`

#### 1.1 Enhance `extract_dsl_steps` method

Add extraction for all StepConfig properties:

```ruby
def extract_dsl_steps(klass)
  return [] unless klass.respond_to?(:step_metadata) && klass.respond_to?(:step_configs)

  step_configs = klass.step_configs

  klass.step_metadata.map do |meta|
    config = step_configs[meta[:name]]
    step_hash = {
      name: meta[:name],
      agent: meta[:agent],
      description: meta[:description],
      ui_label: meta[:ui_label],
      optional: meta[:optional],
      timeout: meta[:timeout],
      routing: meta[:routing],
      parallel: meta[:parallel],
      parallel_group: meta[:parallel_group],
      custom_block: config&.custom_block?
    }

    if config
      step_hash.merge!(
        retry_config: extract_retry_config(config),
        fallbacks: config.fallbacks.map(&:name),
        if_condition: describe_condition(config.if_condition),
        unless_condition: describe_condition(config.unless_condition),
        has_input_mapper: config.input_mapper.present?,
        pick_fields: config.pick_fields,
        pick_from: config.pick_from,
        default_value: config.default_value,
        routes: extract_routes(config)
      )
    end

    step_hash.compact
  end
end
```

#### 1.2 Add helper methods

```ruby
def extract_retry_config(config)
  retry_cfg = config.retry_config
  return nil unless retry_cfg && retry_cfg[:max].to_i > 0

  {
    max: retry_cfg[:max],
    backoff: retry_cfg[:backoff],
    delay: retry_cfg[:delay]
  }
end

def describe_condition(condition)
  return nil if condition.nil?

  case condition
  when Symbol then condition.to_s
  when Proc then "lambda"
  else condition.to_s
  end
end

def extract_routes(config)
  return nil unless config.routing? && config.block

  builder = RubyLLM::Agents::Workflow::DSL::RouteBuilder.new
  config.block.call(builder)

  routes = builder.routes.map do |name, route_config|
    {
      name: name.to_s,
      agent: route_config[:agent]&.name,
      timeout: route_config[:options][:timeout],
      fallback: Array(route_config[:options][:fallback]).first&.then { |f| f.respond_to?(:name) ? f.name : f.to_s },
      has_input_mapper: route_config[:options][:input].present?,
      if_condition: describe_condition(route_config[:options][:if]),
      default: false
    }.compact
  end

  if builder.default
    routes << {
      name: "default",
      agent: builder.default[:agent]&.name,
      default: true
    }.compact
  end

  routes
rescue StandardError
  nil
end
```

#### 1.3 Add lifecycle hooks extraction

```ruby
def extract_lifecycle_hooks(klass)
  return {} unless klass.respond_to?(:lifecycle_hooks)

  hooks = klass.lifecycle_hooks
  {
    before_workflow: hooks[:before_workflow]&.size || 0,
    after_workflow: hooks[:after_workflow]&.size || 0,
    on_step_error: hooks[:on_step_error]&.size || 0
  }
end
```

#### 1.4 Update `load_unified_workflow_config`

```ruby
def load_unified_workflow_config
  @parallel_groups = []
  @input_schema_fields = {}
  @lifecycle_hooks = {}

  @steps = extract_dsl_steps(@workflow_class)
  @parallel_groups = extract_parallel_groups(@workflow_class)
  @lifecycle_hooks = extract_lifecycle_hooks(@workflow_class)

  @config[:steps_count] = @steps.size
  @config[:parallel_groups_count] = @parallel_groups.size
  @config[:has_routing] = @steps.any? { |s| s[:routing] }
  @config[:has_conditions] = @steps.any? { |s| s[:if_condition] || s[:unless_condition] }
  @config[:has_retries] = @steps.any? { |s| s[:retry_config] }
  @config[:has_fallbacks] = @steps.any? { |s| s[:fallbacks]&.any? }
  @config[:has_lifecycle_hooks] = @lifecycle_hooks.values.any? { |v| v > 0 }
  @config[:has_input_schema] = @workflow_class.respond_to?(:input_schema) && @workflow_class.input_schema.present?

  if @config[:has_input_schema]
    @input_schema_fields = @workflow_class.input_schema.fields.transform_values(&:to_h)
  end
end
```

---

### Phase 2: View Overhaul

**File:** `app/views/ruby_llm/agents/workflows/_workflow_diagram.html.erb`

#### 2.1 Lifecycle Hooks Banner

Add at the top of the diagram, before the Start node:

```erb
<% if lifecycle_hooks[:before_workflow] > 0 || lifecycle_hooks[:after_workflow] > 0 || lifecycle_hooks[:on_step_error] > 0 %>
  <div class="flex items-center justify-center gap-4 mb-4 pb-4 border-b border-gray-200 dark:border-gray-700">
    <% if lifecycle_hooks[:before_workflow] > 0 %>
      <div class="flex items-center gap-2 px-3 py-1.5 rounded-lg bg-emerald-50 dark:bg-emerald-900/30 border border-emerald-200 dark:border-emerald-800">
        <svg class="w-4 h-4 text-emerald-500"><!-- play icon --></svg>
        <span class="text-xs font-medium text-emerald-700 dark:text-emerald-300">before_workflow</span>
      </div>
    <% end %>
    <% if lifecycle_hooks[:after_workflow] > 0 %>
      <div class="flex items-center gap-2 px-3 py-1.5 rounded-lg bg-sky-50 dark:bg-sky-900/30 border border-sky-200 dark:border-sky-800">
        <svg class="w-4 h-4 text-sky-500"><!-- flag icon --></svg>
        <span class="text-xs font-medium text-sky-700 dark:text-sky-300">after_workflow</span>
      </div>
    <% end %>
    <% if lifecycle_hooks[:on_step_error] > 0 %>
      <div class="flex items-center gap-2 px-3 py-1.5 rounded-lg bg-rose-50 dark:bg-rose-900/30 border border-rose-200 dark:border-rose-800">
        <svg class="w-4 h-4 text-rose-500"><!-- alert icon --></svg>
        <span class="text-xs font-medium text-rose-700 dark:text-rose-300">on_step_error</span>
      </div>
    <% end %>
  </div>
<% end %>
```

#### 2.2 Enhanced Step Node Component

Replace current step node with enhanced version showing all badges:

```erb
<div class="flex flex-col items-center group relative">
  <!-- Main Step Card -->
  <div class="relative w-36 min-h-[5rem] flex flex-col items-center justify-center rounded-xl border-2 <%= border_color %> <%= bg_color %> <%= step[:optional] ? 'border-dashed' : '' %> shadow-lg p-3 transition-all hover:shadow-xl hover:scale-105">

    <!-- Corner Badges -->
    <% if step[:routing] %>
      <div class="absolute -top-2 -right-2 w-6 h-6 bg-amber-400 rounded rotate-45 flex items-center justify-center shadow">
        <svg class="w-3 h-3 text-white -rotate-45"><!-- route icon --></svg>
      </div>
    <% end %>

    <% if step[:custom_block] %>
      <div class="absolute -top-2 -left-2 w-6 h-6 bg-violet-500 rounded-full flex items-center justify-center shadow">
        <svg class="w-3 h-3 text-white"><!-- code icon --></svg>
      </div>
    <% end %>

    <!-- Step Name -->
    <span class="text-sm font-bold <%= text_color %> text-center leading-tight">
      <%= step[:name].to_s.titleize %>
    </span>

    <!-- Agent Name -->
    <% if step[:agent].present? %>
      <span class="text-[10px] text-gray-500 dark:text-gray-400 mt-1 truncate max-w-32">
        <%= step[:agent].to_s.gsub(/Agent$/, '') %>
      </span>
    <% elsif step[:custom_block] %>
      <span class="text-[10px] text-violet-500 dark:text-violet-400 mt-1 italic">(block)</span>
    <% end %>

    <!-- Inline Badges Row -->
    <div class="flex flex-wrap items-center justify-center gap-1 mt-2">
      <% if step[:retry_config] %>
        <span class="inline-flex items-center px-1.5 py-0.5 rounded text-[9px] font-medium bg-orange-100 dark:bg-orange-900/50 text-orange-600 dark:text-orange-300" title="Retry: <%= step[:retry_config][:max] %>x <%= step[:retry_config][:backoff] %>">
          🔄 <%= step[:retry_config][:max] %>×
        </span>
      <% end %>

      <% if step[:if_condition] %>
        <span class="inline-flex items-center px-1.5 py-0.5 rounded text-[9px] font-medium bg-cyan-100 dark:bg-cyan-900/50 text-cyan-600 dark:text-cyan-300" title="if: <%= step[:if_condition] %>">
          ⚡ if
        </span>
      <% end %>

      <% if step[:unless_condition] %>
        <span class="inline-flex items-center px-1.5 py-0.5 rounded text-[9px] font-medium bg-pink-100 dark:bg-pink-900/50 text-pink-600 dark:text-pink-300" title="unless: <%= step[:unless_condition] %>">
          ⚡ unless
        </span>
      <% end %>

      <% if step[:fallbacks]&.any? %>
        <span class="inline-flex items-center px-1.5 py-0.5 rounded text-[9px] font-medium bg-yellow-100 dark:bg-yellow-900/50 text-yellow-600 dark:text-yellow-300" title="Fallback: <%= step[:fallbacks].join(', ') %>">
          🔀
        </span>
      <% end %>

      <% if step[:has_input_mapper] || step[:pick_fields] %>
        <span class="inline-flex items-center px-1.5 py-0.5 rounded text-[9px] font-medium bg-indigo-100 dark:bg-indigo-900/50 text-indigo-600 dark:text-indigo-300" title="Custom input mapping">
          📥
        </span>
      <% end %>

      <% if step[:default_value] %>
        <span class="inline-flex items-center px-1.5 py-0.5 rounded text-[9px] font-medium bg-gray-100 dark:bg-gray-700 text-gray-600 dark:text-gray-300" title="Default: <%= step[:default_value].inspect %>">
          📋
        </span>
      <% end %>
    </div>
  </div>

  <!-- Below-card indicators -->
  <% if step[:optional] %>
    <span class="text-[10px] text-gray-400 dark:text-gray-500 mt-1 italic">(optional)</span>
  <% end %>
  <% if step[:timeout] %>
    <span class="text-[10px] text-blue-500 dark:text-blue-400 mt-0.5">⏱ <%= step[:timeout] %>s</span>
  <% end %>

  <!-- Hover Tooltip -->
  <div class="absolute bottom-full left-1/2 -translate-x-1/2 mb-2 hidden group-hover:block z-50">
    <div class="bg-gray-900 dark:bg-gray-100 text-white dark:text-gray-900 text-xs rounded-lg px-3 py-2 shadow-xl max-w-xs">
      <p class="font-bold"><%= step[:name] %></p>
      <% if step[:description] %>
        <p class="mt-1 opacity-80"><%= step[:description] %></p>
      <% end %>
      <% if step[:retry_config] %>
        <p class="mt-1">Retry: <%= step[:retry_config][:max] %>× with <%= step[:retry_config][:backoff] %> backoff</p>
      <% end %>
      <% if step[:if_condition] %>
        <p class="mt-1">Condition: if <%= step[:if_condition] %></p>
      <% end %>
      <% if step[:fallbacks]&.any? %>
        <p class="mt-1">Fallback: <%= step[:fallbacks].join(' → ') %></p>
      <% end %>
    </div>
  </div>
</div>
```

#### 2.3 Visual Route Branching

Replace text-based routes with visual branching diagram:

```erb
<% if step[:routing] && step[:routes].present? %>
  <!-- Route Branch Visualization -->
  <div class="flex flex-col items-start ml-4">
    <% step[:routes].each_with_index do |route, idx| %>
      <div class="flex items-center gap-2 <%= idx > 0 ? 'mt-1' : '' %>">
        <!-- Branch line -->
        <div class="flex items-center">
          <div class="w-4 h-px bg-amber-300 dark:bg-amber-600"></div>
          <div class="w-2 h-2 rounded-full <%= route[:default] ? 'bg-gray-400' : 'bg-amber-400' %>"></div>
          <div class="w-4 h-px bg-amber-300 dark:bg-amber-600"></div>
        </div>

        <!-- Route card -->
        <div class="flex items-center gap-2 px-2 py-1 rounded-lg <%= route[:default] ? 'bg-gray-100 dark:bg-gray-800' : 'bg-amber-50 dark:bg-amber-900/30' %> border <%= route[:default] ? 'border-gray-200 dark:border-gray-700' : 'border-amber-200 dark:border-amber-800' %>">
          <span class="text-xs font-medium <%= route[:default] ? 'text-gray-600 dark:text-gray-400' : 'text-amber-700 dark:text-amber-300' %>">
            <%= route[:name] %>
          </span>
          <span class="text-gray-400">→</span>
          <span class="text-xs text-gray-600 dark:text-gray-400">
            <%= route[:agent]&.gsub(/Agent$/, '') || '(none)' %>
          </span>

          <!-- Route badges -->
          <% if route[:fallback] %>
            <span class="text-[9px] px-1 py-0.5 rounded bg-yellow-100 dark:bg-yellow-900/50 text-yellow-600" title="Fallback: <%= route[:fallback] %>">🔀</span>
          <% end %>
          <% if route[:if_condition] %>
            <span class="text-[9px] px-1 py-0.5 rounded bg-cyan-100 dark:bg-cyan-900/50 text-cyan-600" title="if: <%= route[:if_condition] %>">⚡</span>
          <% end %>
          <% if route[:timeout] %>
            <span class="text-[9px] px-1 py-0.5 rounded bg-blue-100 dark:bg-blue-900/50 text-blue-600">⏱ <%= route[:timeout] %>s</span>
          <% end %>
        </div>
      </div>
    <% end %>
  </div>
<% end %>
```

#### 2.4 Collapsible Parallel Groups

Wrap parallel groups in collapsible container using Alpine.js:

```erb
<div x-data="{ expanded: true }" class="flex flex-col items-center">
  <div class="relative border-2 border-dashed border-purple-400 rounded-2xl p-4 bg-gradient-to-br from-purple-50/80 to-violet-50/80 dark:from-purple-900/30 dark:to-violet-900/30">

    <!-- Collapsible header -->
    <button @click="expanded = !expanded" class="absolute -top-3 left-1/2 -translate-x-1/2 bg-purple-500 text-white rounded-full px-3 py-1 shadow-lg flex items-center gap-1 hover:bg-purple-600 transition-colors">
      <svg class="w-3 h-3" fill="currentColor" viewBox="0 0 20 20"><!-- puzzle icon --></svg>
      <span class="text-[10px] font-bold uppercase">Parallel</span>
      <svg class="w-3 h-3 transition-transform" :class="expanded ? 'rotate-180' : ''" fill="none" stroke="currentColor" viewBox="0 0 24 24">
        <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M19 9l-7 7-7-7"/>
      </svg>
    </button>

    <!-- Collapsible content -->
    <div x-show="expanded" x-collapse class="flex items-stretch gap-3 mt-2">
      <!-- parallel steps here -->
    </div>

    <!-- Collapsed summary -->
    <div x-show="!expanded" class="text-center py-2">
      <span class="text-xs text-purple-600 dark:text-purple-400">
        <%= item[:steps].size %> parallel steps
      </span>
    </div>

    <!-- Group options -->
    <% if item[:group] %>
      <div class="flex items-center justify-center gap-2 mt-2 text-[9px] text-purple-600 dark:text-purple-400">
        <% if item[:group][:fail_fast] %>
          <span class="bg-purple-200 dark:bg-purple-800 px-1.5 py-0.5 rounded font-medium">fail_fast</span>
        <% end %>
        <% if item[:group][:timeout] %>
          <span class="bg-purple-200 dark:bg-purple-800 px-1.5 py-0.5 rounded font-medium">⏱ <%= item[:group][:timeout] %>s</span>
        <% end %>
        <% if item[:group][:concurrency] %>
          <span class="bg-purple-200 dark:bg-purple-800 px-1.5 py-0.5 rounded font-medium">max: <%= item[:group][:concurrency] %></span>
        <% end %>
      </div>
    <% end %>
  </div>
</div>
```

#### 2.5 Enhanced Legend

Update legend to include all new badge types:

```erb
<div class="flex flex-wrap items-center justify-center gap-4 py-3 border-t border-gray-100 dark:border-gray-700 text-xs text-gray-500 dark:text-gray-400">
  <!-- Existing -->
  <div class="flex items-center gap-1.5">
    <div class="w-4 h-4 rounded border-2 border-indigo-300 bg-indigo-50"></div>
    <span>Sequential</span>
  </div>
  <div class="flex items-center gap-1.5">
    <div class="w-4 h-4 rounded border-2 border-dashed border-purple-400 bg-purple-50"></div>
    <span>Parallel</span>
  </div>
  <div class="flex items-center gap-1.5">
    <div class="w-4 h-4 rounded border-2 border-amber-400 bg-amber-50"></div>
    <span>Routing</span>
  </div>

  <!-- New -->
  <div class="flex items-center gap-1.5">
    <span class="px-1.5 py-0.5 rounded text-[9px] bg-orange-100 text-orange-600">🔄</span>
    <span>Retry</span>
  </div>
  <div class="flex items-center gap-1.5">
    <span class="px-1.5 py-0.5 rounded text-[9px] bg-cyan-100 text-cyan-600">⚡</span>
    <span>Conditional</span>
  </div>
  <div class="flex items-center gap-1.5">
    <span class="px-1.5 py-0.5 rounded text-[9px] bg-yellow-100 text-yellow-600">🔀</span>
    <span>Fallback</span>
  </div>
  <div class="flex items-center gap-1.5">
    <span class="px-1.5 py-0.5 rounded text-[9px] bg-indigo-100 text-indigo-600">📥</span>
    <span>Input Mapping</span>
  </div>
  <div class="flex items-center gap-1.5">
    <span class="px-1.5 py-0.5 rounded text-[9px] bg-violet-100 text-violet-600">{ }</span>
    <span>Block Step</span>
  </div>
</div>
```

#### 2.6 Enhanced Step Details Table

Update the Step Details section with all new fields:

```erb
<div class="space-y-2">
  <% steps.each_with_index do |step, index| %>
    <div class="flex items-start gap-3 py-3 px-4 rounded-lg bg-gray-50 dark:bg-gray-900/50 border border-gray-100 dark:border-gray-800">
      <!-- Step number -->
      <span class="w-7 h-7 flex items-center justify-center rounded-full <%= badge_bg %> border <%= badge_border %> text-xs font-bold <%= badge_text %> flex-shrink-0">
        <%= index + 1 %>
      </span>

      <div class="flex-1 min-w-0">
        <!-- Header row -->
        <div class="flex items-center flex-wrap gap-2">
          <span class="font-semibold text-gray-800 dark:text-gray-200">
            <%= step[:name].to_s.titleize %>
          </span>

          <% if step[:agent].present? %>
            <span class="text-gray-400">→</span>
            <code class="text-sm font-mono text-gray-600 dark:text-gray-400 bg-gray-100 dark:bg-gray-800 px-2 py-0.5 rounded">
              <%= step[:agent] %>
            </code>
          <% elsif step[:custom_block] %>
            <span class="text-gray-400">→</span>
            <code class="text-sm font-mono text-violet-600 dark:text-violet-400 bg-violet-100 dark:bg-violet-900/50 px-2 py-0.5 rounded">
              (block)
            </code>
          <% end %>

          <!-- All badges -->
          <% if step[:routing] %>
            <span class="badge bg-amber-100 text-amber-700">routing</span>
          <% end %>
          <% if step[:parallel_group] %>
            <span class="badge bg-purple-100 text-purple-700">parallel</span>
          <% end %>
          <% if step[:optional] %>
            <span class="badge bg-gray-100 text-gray-600">optional</span>
          <% end %>
          <% if step[:timeout] %>
            <span class="badge bg-blue-100 text-blue-700">⏱ <%= step[:timeout] %>s</span>
          <% end %>
          <% if step[:retry_config] %>
            <span class="badge bg-orange-100 text-orange-700">retry: <%= step[:retry_config][:max] %>× <%= step[:retry_config][:backoff] %></span>
          <% end %>
          <% if step[:if_condition] %>
            <span class="badge bg-cyan-100 text-cyan-700">if: <%= step[:if_condition] %></span>
          <% end %>
          <% if step[:unless_condition] %>
            <span class="badge bg-pink-100 text-pink-700">unless: <%= step[:unless_condition] %></span>
          <% end %>
          <% if step[:fallbacks]&.any? %>
            <span class="badge bg-yellow-100 text-yellow-700">fallback: <%= step[:fallbacks].join(' → ') %></span>
          <% end %>
          <% if step[:default_value] %>
            <span class="badge bg-gray-100 text-gray-600">default: <%= step[:default_value].inspect.truncate(30) %></span>
          <% end %>
          <% if step[:pick_fields] %>
            <span class="badge bg-indigo-100 text-indigo-700">pick: <%= step[:pick_fields].join(', ') %><%= step[:pick_from] ? " from :#{step[:pick_from]}" : '' %></span>
          <% end %>
        </div>

        <!-- Description -->
        <% if step[:description].present? %>
          <p class="text-sm text-gray-500 dark:text-gray-400 mt-1"><%= step[:description] %></p>
        <% end %>

        <!-- Routes detail (for routing steps) -->
        <% if step[:routes].present? %>
          <div class="mt-2 pl-4 border-l-2 border-amber-200 dark:border-amber-800">
            <p class="text-xs text-gray-500 mb-1">Routes:</p>
            <div class="flex flex-wrap gap-2">
              <% step[:routes].each do |route| %>
                <div class="text-xs px-2 py-1 rounded <%= route[:default] ? 'bg-gray-100 text-gray-600' : 'bg-amber-50 text-amber-700' %>">
                  <span class="font-medium"><%= route[:name] %></span>
                  → <%= route[:agent]&.gsub(/Agent$/, '') || '?' %>
                  <% if route[:fallback] %><span class="text-yellow-600 ml-1">🔀 <%= route[:fallback].gsub(/Agent$/, '') %></span><% end %>
                  <% if route[:if_condition] %><span class="text-cyan-600 ml-1">⚡</span><% end %>
                  <% if route[:timeout] %><span class="text-blue-600 ml-1">⏱ <%= route[:timeout] %>s</span><% end %>
                </div>
              <% end %>
            </div>
          </div>
        <% end %>
      </div>
    </div>
  <% end %>
</div>
```

---

### Phase 3: Show View Updates

**File:** `app/views/ruby_llm/agents/workflows/show.html.erb`

#### 3.1 Pass lifecycle hooks to partial

```erb
<%= render 'workflow_diagram',
  steps: @steps,
  parallel_groups: @parallel_groups,
  input_schema_fields: @input_schema_fields,
  lifecycle_hooks: @lifecycle_hooks %>
```

#### 3.2 Add workflow features summary

In the header section, add a features summary:

```erb
<div class="flex flex-wrap gap-2 mt-2">
  <% if @config[:has_lifecycle_hooks] %>
    <span class="text-xs px-2 py-1 rounded-full bg-emerald-100 dark:bg-emerald-900/50 text-emerald-700 dark:text-emerald-300">
      Lifecycle Hooks
    </span>
  <% end %>
  <% if @config[:has_conditions] %>
    <span class="text-xs px-2 py-1 rounded-full bg-cyan-100 dark:bg-cyan-900/50 text-cyan-700 dark:text-cyan-300">
      Conditional Steps
    </span>
  <% end %>
  <% if @config[:has_retries] %>
    <span class="text-xs px-2 py-1 rounded-full bg-orange-100 dark:bg-orange-900/50 text-orange-700 dark:text-orange-300">
      Retry Logic
    </span>
  <% end %>
  <% if @config[:has_fallbacks] %>
    <span class="text-xs px-2 py-1 rounded-full bg-yellow-100 dark:bg-yellow-900/50 text-yellow-700 dark:text-yellow-300">
      Fallback Agents
    </span>
  <% end %>
</div>
```

---

## Files to Modify

| File | Changes |
|------|---------|
| `app/controllers/ruby_llm/agents/workflows_controller.rb` | Add data extraction methods |
| `app/views/ruby_llm/agents/workflows/_workflow_diagram.html.erb` | Complete UI overhaul |
| `app/views/ruby_llm/agents/workflows/show.html.erb` | Pass new data, add features summary |

---

## Testing Checklist

1. **ContentAnalyzerWorkflow** should display:
   - [ ] before_workflow hook indicator
   - [ ] Parallel group with timeout badge
   - [ ] Optional steps with default values
   - [ ] Conditional step (entities with if:)
   - [ ] Input mapping indicator on keywords step

2. **ContentPipelineWorkflow** should display:
   - [ ] Retry badge on extract step
   - [ ] Custom block step (enrich)
   - [ ] Input mapping indicators
   - [ ] unless condition on format step
   - [ ] pick/from badges
   - [ ] after_workflow hook indicator
   - [ ] on_step_error hook indicator

3. **SupportRouterWorkflow** should display:
   - [ ] Visual route branching
   - [ ] Per-route fallback (technical → GeneralAgent)
   - [ ] Per-route condition (account with if:)
   - [ ] Per-route timeout (billing 2min)
   - [ ] Input mapping indicators on routes

4. **General UI**:
   - [ ] Hover tooltips show full details
   - [ ] Parallel groups can collapse/expand
   - [ ] Legend shows all badge types
   - [ ] Dark mode works correctly
   - [ ] Mobile responsive (horizontal scroll)

---

## Future Enhancements (Out of Scope)

- Real-time execution visualization (steps lighting up)
- Drag-and-drop workflow builder
- Zoom/pan controls for large workflows
- Execution replay visualization
- Workflow version comparison
