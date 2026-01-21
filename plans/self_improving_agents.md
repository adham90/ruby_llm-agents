# Self-Improving Agents Implementation Plan

## Overview

Build a system where agents can self-improve their prompts based on execution history. An "Improvement Agent" analyzes recent executions against user-defined success criteria and suggests prompt changes, which can be applied manually or automatically.

## DSL Design

```ruby
class CustomerSupportAgent < RubyLLM::Agent
  model "claude-sonnet"

  # Initial template - gets stored in DB and versioned
  # Supports {{variable}} interpolation from agent params
  system_prompt <<~PROMPT
    You are a helpful support agent for {{company_name}}.

    Customer context:
    - Name: {{customer_name}}
    - Plan: {{customer_plan}}
    - Account age: {{account_age}}

    Help them with their questions professionally and concisely.
  PROMPT

  self_improving do
    enabled true
    approval :manual  # or :auto
    frequency :daily  # or after_executions: 100

    # Required when enabled
    success_criteria <<~TEXT
      A successful execution:
      - Directly answers the customer's question
      - Provides actionable steps, not vague advice
      - Doesn't ask unnecessary clarifying questions
      - Resolves the issue in one response when possible

      A failed execution:
      - Customer had to ask follow-up questions for clarification
      - Response was generic or didn't address the specific issue
      - Gave incorrect information
      - Was overly verbose without being helpful
    TEXT

    # Required when enabled
    optimize_for <<~TEXT
      - Reduce back-and-forth by being more comprehensive upfront
      - Match the tone to the customer's tone
      - Include relevant links/resources proactively
    TEXT
  end

  # Define how to resolve template variables
  # Can come from params, methods, or context
  prompt_variables do
    variable :company_name, from: :config  # From agent config
    variable :customer_name, from: :params  # From runtime params
    variable :customer_plan, from: :params
    variable :account_age, from: :method    # From agent method
  end

  def account_age
    customer = params[:customer]
    "#{((Time.current - customer.created_at) / 1.day).round} days"
  end
end

# Usage at runtime
agent = CustomerSupportAgent.new(
  config: { company_name: "Acme Corp" }
)

agent.run(
  task: "How do I reset my password?",
  params: {
    customer_name: "John Doe",
    customer_plan: "Pro",
    customer: current_customer  # For method-based variables
  }
)
```

### Validation Rules

- When `enabled true`, both `success_criteria` and `optimize_for` are **required**
- Raise `ArgumentError` if either is missing when self-improvement is enabled

---

## Dynamic System Prompt Architecture

### Key Concept: Template vs Runtime Prompt

```
┌─────────────────────────────────────────────────────────────────┐
│                    Prompt Flow                                   │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  1. DSL defines initial template                                │
│     ┌─────────────────────────────────────────────────────┐     │
│     │ system_prompt "You help {{customer_name}} with..."  │     │
│     └─────────────────────────────────────────────────────┘     │
│                           │                                      │
│                           ▼                                      │
│  2. Stored in DB as PromptVersion (template with {{vars}})      │
│     ┌─────────────────────────────────────────────────────┐     │
│     │ prompt_versions.system_prompt (still has {{vars}})  │     │
│     └─────────────────────────────────────────────────────┘     │
│                           │                                      │
│                           ▼                                      │
│  3. At runtime, interpolate variables                           │
│     ┌─────────────────────────────────────────────────────┐     │
│     │ "You help John Doe with..." (resolved)              │     │
│     └─────────────────────────────────────────────────────┘     │
│                           │                                      │
│                           ▼                                      │
│  4. Improvement agent sees template (with {{vars}})             │
│     - Suggests changes to template, preserving {{vars}}         │
│     - Can add/modify text around variables                      │
│     - Cannot change variable names (those are code contracts)   │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

### Why This Matters

1. **Improvement agent edits the template**, not resolved values
2. **Variables are preserved** - the agent learns to use them better
3. **Same prompt version works** for different customers/contexts
4. **Execution logs store both** template version AND resolved values for debugging

### Template Variable Sources

| Source | Description | Example |
|--------|-------------|---------|
| `:params` | Passed at runtime via `agent.run(params: {})` | `customer_name` |
| `:config` | Set once when agent is instantiated | `company_name` |
| `:method` | Computed by agent method at runtime | `account_age` |
| `:context` | From execution context (tenant, user, etc.) | `tenant_name` |

### Variable Resolution Order

```ruby
# Priority: params > config > method > context > default
def resolve_variable(name)
  params[name] ||
    config[name] ||
    (respond_to?(name) ? send(name) : nil) ||
    context[name] ||
    variable_defaults[name]
end
```

---

## Template Interpolation Service

```ruby
# lib/ruby_llm/agents/prompt_interpolator.rb
module RubyLLM
  module Agents
    class PromptInterpolator
      VARIABLE_PATTERN = /\{\{(\w+)\}\}/

      def initialize(agent)
        @agent = agent
      end

      # Interpolate template with current context
      def interpolate(template, params: {}, context: {})
        template.gsub(VARIABLE_PATTERN) do |match|
          var_name = $1.to_sym
          resolve_variable(var_name, params: params, context: context)
        end
      end

      # Extract all variable names from a template
      def self.extract_variables(template)
        template.scan(VARIABLE_PATTERN).flatten.map(&:to_sym).uniq
      end

      # Validate that all required variables can be resolved
      def validate_variables(template, params: {}, context: {})
        variables = self.class.extract_variables(template)
        missing = variables.reject { |v| can_resolve?(v, params: params, context: context) }

        if missing.any?
          raise ArgumentError, "Missing template variables: #{missing.join(', ')}"
        end
      end

      private

      def resolve_variable(name, params:, context:)
        # 1. Check runtime params
        return params[name].to_s if params.key?(name)

        # 2. Check agent config
        return @agent.config[name].to_s if @agent.config&.key?(name)

        # 3. Check agent method
        if @agent.respond_to?(name, true)
          return @agent.send(name).to_s
        end

        # 4. Check context (tenant, user, etc.)
        return context[name].to_s if context.key?(name)

        # 5. Check defaults from DSL
        default = @agent.class.variable_defaults[name]
        return default.to_s if default

        # 6. Leave placeholder if not found (or raise?)
        "{{#{name}}}"
      end

      def can_resolve?(name, params:, context:)
        params.key?(name) ||
          @agent.config&.key?(name) ||
          @agent.respond_to?(name, true) ||
          context.key?(name) ||
          @agent.class.variable_defaults.key?(name)
      end
    end
  end
end
```

### DSL for Variables

```ruby
# lib/ruby_llm/agents/dsl/prompt_variables_config.rb
module RubyLLM
  module Agents
    module DSL
      class PromptVariablesConfig
        attr_reader :variables

        def initialize
          @variables = {}
        end

        def variable(name, from: :params, default: nil, required: true)
          @variables[name.to_sym] = {
            source: from,
            default: default,
            required: required
          }
        end

        def to_h
          @variables
        end
      end
    end
  end
end
```

### Update Agent Base Class for Variables

```ruby
# Additions to Agent base class
module RubyLLM
  module Agents
    class Agent
      class << self
        def prompt_variables(&block)
          @prompt_variables_config = DSL::PromptVariablesConfig.new
          @prompt_variables_config.instance_eval(&block) if block_given?
          @prompt_variables_config
        end

        def variable_definitions
          @prompt_variables_config&.to_h || {}
        end

        def variable_defaults
          variable_definitions.transform_values { |v| v[:default] }
        end
      end

      attr_reader :config

      def initialize(config: {})
        @config = config
        @interpolator = PromptInterpolator.new(self)
      end

      # Get the resolved system prompt for this execution
      def resolved_system_prompt(params: {}, context: {})
        template = active_system_prompt  # From DB or class
        @interpolator.interpolate(template, params: params, context: context)
      end
    end
  end
end
```

---

## Database Schema

### 1. Add columns to `agent_definitions`

```ruby
# Migration: add_self_improving_to_agent_definitions.rb
class AddSelfImprovingToAgentDefinitions < ActiveRecord::Migration[7.0]
  def change
    add_column :agent_definitions, :self_improve_enabled, :boolean, default: false
    add_column :agent_definitions, :self_improve_approval, :string, default: "manual"
    add_column :agent_definitions, :self_improve_frequency, :string, default: "daily"
    add_column :agent_definitions, :success_criteria, :text
    add_column :agent_definitions, :optimize_for, :text
    add_column :agent_definitions, :current_prompt_version_id, :bigint

    add_index :agent_definitions, :self_improve_enabled
  end
end
```

### 2. Create `prompt_versions` table

Stores version history of prompts with ability to rollback.

```ruby
# Migration: create_prompt_versions.rb
class CreatePromptVersions < ActiveRecord::Migration[7.0]
  def change
    create_table :prompt_versions do |t|
      t.references :agent_definition, null: false, foreign_key: true
      t.references :parent_version, foreign_key: { to_table: :prompt_versions }
      t.references :approved_by, foreign_key: { to_table: :users }

      t.text :system_prompt, null: false
      t.integer :version_number, null: false
      t.string :status, default: "draft"  # draft, active, rolled_back
      t.string :created_by, default: "human"  # human, improvement_agent
      t.text :change_reason
      t.text :change_summary  # What was changed from parent

      t.timestamps
    end

    add_index :prompt_versions, [:agent_definition_id, :version_number], unique: true
    add_index :prompt_versions, [:agent_definition_id, :status]
  end
end
```

### 3. Create `improvement_suggestions` table

Stores suggestions from the improvement agent.

```ruby
# Migration: create_improvement_suggestions.rb
class CreateImprovementSuggestions < ActiveRecord::Migration[7.0]
  def change
    create_table :improvement_suggestions do |t|
      t.references :agent_definition, null: false, foreign_key: true
      t.references :based_on_version, null: false, foreign_key: { to_table: :prompt_versions }
      t.references :resulting_version, foreign_key: { to_table: :prompt_versions }
      t.references :reviewed_by, foreign_key: { to_table: :users }

      t.text :suggested_prompt, null: false
      t.text :reasoning, null: false  # Why the agent suggests this
      t.text :patterns_observed  # What patterns it found in executions
      t.string :confidence, default: "medium"  # high, medium, low
      t.string :status, default: "pending"  # pending, approved, rejected
      t.integer :executions_analyzed, default: 0
      t.datetime :reviewed_at
      t.text :rejection_reason

      t.timestamps
    end

    add_index :improvement_suggestions, [:agent_definition_id, :status]
  end
end
```

### 4. Create `improvement_suggestion_executions` join table

Links suggestions to the executions that informed them.

```ruby
# Migration: create_improvement_suggestion_executions.rb
class CreateImprovementSuggestionExecutions < ActiveRecord::Migration[7.0]
  def change
    create_table :improvement_suggestion_executions do |t|
      t.references :improvement_suggestion, null: false, foreign_key: true
      t.references :execution, null: false, foreign_key: true

      t.timestamps
    end

    add_index :improvement_suggestion_executions,
              [:improvement_suggestion_id, :execution_id],
              unique: true,
              name: 'idx_suggestion_executions_unique'
  end
end
```

### 5. Update `executions` for prompt tracking

Track which prompt version was used AND the resolved prompt (for debugging).

```ruby
# Migration: add_prompt_tracking_to_executions.rb
class AddPromptTrackingToExecutions < ActiveRecord::Migration[7.0]
  def change
    add_reference :executions, :prompt_version, foreign_key: true

    # Store the fully resolved prompt that was actually sent to LLM
    # Useful for debugging, but improvement agent uses template
    add_column :executions, :resolved_system_prompt, :text

    # Store the params used for interpolation (for replay/debugging)
    add_column :executions, :interpolation_params, :jsonb, default: {}
  end
end
```

### Why Store Both?

| Field | Purpose |
|-------|---------|
| `prompt_version_id` | Links to template (with `{{vars}}`) |
| `resolved_system_prompt` | What was actually sent to LLM |
| `interpolation_params` | Params used to resolve variables |

**Improvement agent analyzes templates**, not resolved prompts - this way it can suggest changes that work across all customers/contexts.

**Debugging uses resolved prompts** - when investigating a specific execution, you see exactly what the LLM received.

---

## Models

### 1. PromptVersion

```ruby
# app/models/prompt_version.rb
module RubyLLM
  module Agents
    class PromptVersion < ApplicationRecord
      belongs_to :agent_definition
      belongs_to :parent_version, class_name: "PromptVersion", optional: true
      belongs_to :approved_by, class_name: "User", optional: true

      has_many :child_versions, class_name: "PromptVersion", foreign_key: :parent_version_id
      has_many :executions
      has_one :improvement_suggestion, foreign_key: :resulting_version_id

      validates :system_prompt, presence: true
      validates :version_number, presence: true, uniqueness: { scope: :agent_definition_id }
      validates :status, inclusion: { in: %w[draft active rolled_back] }
      validates :created_by, inclusion: { in: %w[human improvement_agent] }

      scope :active, -> { where(status: "active") }
      scope :by_improvement_agent, -> { where(created_by: "improvement_agent") }

      before_validation :set_version_number, on: :create

      def activate!
        transaction do
          agent_definition.prompt_versions.active.update_all(status: "rolled_back")
          update!(status: "active")
          agent_definition.update!(current_prompt_version_id: id)
        end
      end

      def rollback!
        return unless parent_version
        parent_version.activate!
      end

      private

      def set_version_number
        self.version_number ||= (agent_definition.prompt_versions.maximum(:version_number) || 0) + 1
      end
    end
  end
end
```

### 2. ImprovementSuggestion

```ruby
# app/models/improvement_suggestion.rb
module RubyLLM
  module Agents
    class ImprovementSuggestion < ApplicationRecord
      belongs_to :agent_definition
      belongs_to :based_on_version, class_name: "PromptVersion"
      belongs_to :resulting_version, class_name: "PromptVersion", optional: true
      belongs_to :reviewed_by, class_name: "User", optional: true

      has_many :improvement_suggestion_executions
      has_many :analyzed_executions, through: :improvement_suggestion_executions, source: :execution

      validates :suggested_prompt, presence: true
      validates :reasoning, presence: true
      validates :status, inclusion: { in: %w[pending approved rejected] }
      validates :confidence, inclusion: { in: %w[high medium low] }

      scope :pending, -> { where(status: "pending") }
      scope :approved, -> { where(status: "approved") }

      def approve!(user:)
        transaction do
          # Create new prompt version from suggestion
          new_version = agent_definition.prompt_versions.create!(
            system_prompt: suggested_prompt,
            parent_version: based_on_version,
            created_by: "improvement_agent",
            change_reason: reasoning,
            change_summary: generate_change_summary,
            approved_by: user
          )

          update!(
            status: "approved",
            resulting_version: new_version,
            reviewed_by: user,
            reviewed_at: Time.current
          )

          # Activate if auto-approval is on
          new_version.activate! if agent_definition.self_improve_approval == "auto"

          new_version
        end
      end

      def reject!(user:, reason:)
        update!(
          status: "rejected",
          reviewed_by: user,
          reviewed_at: Time.current,
          rejection_reason: reason
        )
      end

      private

      def generate_change_summary
        # Could use LLM to generate a diff summary
        "Prompt updated based on analysis of #{executions_analyzed} executions"
      end
    end
  end
end
```

### 3. Update AgentDefinition

```ruby
# Add to existing AgentDefinition model
module RubyLLM
  module Agents
    class AgentDefinition < ApplicationRecord
      # Existing associations...

      has_many :prompt_versions, dependent: :destroy
      has_many :improvement_suggestions, dependent: :destroy
      belongs_to :current_prompt_version, class_name: "PromptVersion", optional: true

      validates :success_criteria, presence: true, if: :self_improve_enabled?
      validates :optimize_for, presence: true, if: :self_improve_enabled?
      validates :self_improve_approval, inclusion: { in: %w[manual auto] }
      validates :self_improve_frequency, inclusion: { in: %w[daily weekly hourly] },
                allow_blank: true

      # Get the active prompt (versioned or original)
      def active_system_prompt
        current_prompt_version&.system_prompt || system_prompt
      end

      # Create initial version when enabling self-improvement
      def enable_self_improvement!
        return if prompt_versions.any?

        prompt_versions.create!(
          system_prompt: system_prompt,
          status: "active",
          created_by: "human",
          change_reason: "Initial version"
        ).tap do |version|
          update!(current_prompt_version: version)
        end
      end
    end
  end
end
```

---

## Services

### 1. ImprovementAnalyzer

The core service that analyzes executions and generates suggestions.

```ruby
# app/services/ruby_llm/agents/improvement_analyzer.rb
module RubyLLM
  module Agents
    class ImprovementAnalyzer
      SYSTEM_PROMPT = <<~PROMPT
        You are a prompt optimization specialist. Your job is to analyze
        agent executions and suggest improvements to the system prompt.

        You will receive:
        1. The current system prompt TEMPLATE (contains {{variable}} placeholders)
        2. A set of recent executions (input/output pairs with resolved prompts)
        3. The user's description of what success looks like
        4. What the user wants to optimize for

        Analyze the executions against the success criteria. Look for:
        - Patterns in outputs that don't meet success criteria
        - Common failure modes or edge cases not handled
        - Missed opportunities mentioned in optimize_for
        - Unnecessary verbosity or inefficiency
        - Unclear instructions causing inconsistent outputs

        CRITICAL: Template Variable Rules
        - The prompt contains {{variable}} placeholders that get filled at runtime
        - You MUST preserve all existing {{variable}} placeholders exactly as-is
        - You can add text around variables, reorder them, or add context
        - You can suggest USING a variable more effectively
        - You CANNOT rename variables or remove them (they are code contracts)
        - You CANNOT add new {{variables}} (those require code changes)

        Respond with JSON in this exact format:
        {
          "patterns_observed": {
            "working_well": ["pattern 1", "pattern 2"],
            "not_working": ["issue 1", "issue 2"],
            "opportunities": ["opportunity 1"]
          },
          "suggested_prompt": "The full improved system prompt TEMPLATE here (keep {{vars}})",
          "changes_made": [
            {"change": "description of change", "reason": "why this helps"}
          ],
          "reasoning": "Overall explanation of why these changes will improve performance",
          "confidence": "high|medium|low"
        }

        Important:
        - Only suggest changes that address observed patterns
        - Keep the core functionality and tone intact
        - Be specific about what you changed and why
        - PRESERVE ALL {{variable}} PLACEHOLDERS
        - If the current prompt is working well, say so and suggest no changes
      PROMPT

      def initialize(agent_definition, llm_client: nil)
        @agent_definition = agent_definition
        @llm_client = llm_client || default_llm_client
      end

      def analyze(executions_limit: 50)
        executions = recent_executions(limit: executions_limit)
        return nil if executions.empty?

        current_version = @agent_definition.current_prompt_version
        return nil unless current_version

        response = @llm_client.chat(
          model: "claude-sonnet",
          system: SYSTEM_PROMPT,
          messages: [{ role: "user", content: build_analysis_prompt(current_version, executions) }]
        )

        result = JSON.parse(response.content)

        create_suggestion(
          current_version: current_version,
          executions: executions,
          analysis_result: result
        )
      end

      private

      def recent_executions(limit:)
        @agent_definition.executions
          .includes(:prompt_version)
          .order(created_at: :desc)
          .limit(limit)
      end

      def build_analysis_prompt(current_version, executions)
        <<~PROMPT
          ## Current System Prompt

          ```
          #{current_version.system_prompt}
          ```

          ## Success Criteria

          #{@agent_definition.success_criteria}

          ## Optimize For

          #{@agent_definition.optimize_for}

          ## Recent Executions (#{executions.size} total)

          #{format_executions(executions)}

          ---

          Analyze these executions against the success criteria and suggest prompt improvements.
        PROMPT
      end

      def format_executions(executions)
        executions.map.with_index do |exec, i|
          <<~EXEC
            ### Execution #{i + 1}

            **Input:**
            ```
            #{truncate_text(exec.input, 500)}
            ```

            **Output:**
            ```
            #{truncate_text(exec.output, 1000)}
            ```

            **Status:** #{exec.status}
            **Duration:** #{exec.duration_ms}ms
          EXEC
        end.join("\n---\n")
      end

      def truncate_text(text, max_length)
        return text if text.length <= max_length
        "#{text[0...max_length]}... [truncated]"
      end

      def create_suggestion(current_version:, executions:, analysis_result:)
        return nil if analysis_result["suggested_prompt"].blank?
        return nil if analysis_result["suggested_prompt"] == current_version.system_prompt

        suggestion = @agent_definition.improvement_suggestions.create!(
          based_on_version: current_version,
          suggested_prompt: analysis_result["suggested_prompt"],
          reasoning: analysis_result["reasoning"],
          patterns_observed: analysis_result["patterns_observed"].to_json,
          confidence: analysis_result["confidence"],
          executions_analyzed: executions.size
        )

        # Link analyzed executions
        executions.each do |exec|
          suggestion.improvement_suggestion_executions.create!(execution: exec)
        end

        suggestion
      end

      def default_llm_client
        RubyLLM.client
      end
    end
  end
end
```

### 2. ImprovementScheduler

Handles scheduling and running improvement analysis.

```ruby
# app/services/ruby_llm/agents/improvement_scheduler.rb
module RubyLLM
  module Agents
    class ImprovementScheduler
      def self.run_due_analyses
        new.run_due_analyses
      end

      def run_due_analyses
        agents_due_for_analysis.find_each do |agent_definition|
          analyze_agent(agent_definition)
        end
      end

      def analyze_agent(agent_definition)
        return unless agent_definition.self_improve_enabled?

        analyzer = ImprovementAnalyzer.new(agent_definition)
        suggestion = analyzer.analyze

        return unless suggestion

        if agent_definition.self_improve_approval == "auto"
          # Auto-approve high confidence suggestions
          if suggestion.confidence == "high"
            suggestion.approve!(user: system_user)
            suggestion.resulting_version.activate!
          end
        else
          # Notify for manual review
          notify_pending_suggestion(suggestion)
        end

        suggestion
      end

      private

      def agents_due_for_analysis
        AgentDefinition
          .where(self_improve_enabled: true)
          .where(due_for_analysis_condition)
      end

      def due_for_analysis_condition
        # Check based on frequency setting
        # This is simplified - real implementation would track last_analyzed_at
        "1=1"
      end

      def system_user
        # A system user for auto-approvals
        User.find_or_create_by(email: "system@agents.local") do |u|
          u.name = "System"
        end
      end

      def notify_pending_suggestion(suggestion)
        # Hook for notifications (email, slack, etc.)
        Rails.logger.info "Pending improvement suggestion for #{suggestion.agent_definition.name}"
      end
    end
  end
end
```

---

## DSL Implementation

### SelfImprovingConfig

```ruby
# lib/ruby_llm/agents/dsl/self_improving_config.rb
module RubyLLM
  module Agents
    module DSL
      class SelfImprovingConfig
        attr_reader :settings

        def initialize
          @settings = {
            enabled: false,
            approval: :manual,
            frequency: :daily,
            success_criteria: nil,
            optimize_for: nil
          }
        end

        def enabled(value = true)
          @settings[:enabled] = value
        end

        def approval(mode)
          unless %i[manual auto].include?(mode)
            raise ArgumentError, "approval must be :manual or :auto"
          end
          @settings[:approval] = mode
        end

        def frequency(value)
          case value
          when Symbol
            unless %i[daily weekly hourly].include?(value)
              raise ArgumentError, "frequency must be :daily, :weekly, :hourly, or after_executions: N"
            end
            @settings[:frequency] = value.to_s
          when Hash
            if value[:after_executions]
              @settings[:frequency] = "after_executions"
              @settings[:frequency_threshold] = value[:after_executions]
            else
              raise ArgumentError, "Invalid frequency option"
            end
          end
        end

        def success_criteria(text)
          @settings[:success_criteria] = text.strip
        end

        def optimize_for(text)
          @settings[:optimize_for] = text.strip
        end

        def validate!
          return unless @settings[:enabled]

          if @settings[:success_criteria].blank?
            raise ArgumentError, "success_criteria is required when self_improving is enabled"
          end

          if @settings[:optimize_for].blank?
            raise ArgumentError, "optimize_for is required when self_improving is enabled"
          end
        end

        def to_h
          validate!
          @settings
        end
      end
    end
  end
end
```

### Update Agent Base Class

```ruby
# lib/ruby_llm/agents/agent.rb (additions)
module RubyLLM
  module Agents
    class Agent
      class << self
        def self_improving(&block)
          @self_improving_config = DSL::SelfImprovingConfig.new
          @self_improving_config.instance_eval(&block) if block_given?
          @self_improving_config.validate!
          @self_improving_config
        end

        def self_improving_config
          @self_improving_config
        end

        def self_improving_settings
          @self_improving_config&.to_h || {}
        end
      end

      # Instance method to get active prompt (versioned if self-improving)
      def active_system_prompt
        if self.class.self_improving_settings[:enabled] && agent_definition&.current_prompt_version
          agent_definition.current_prompt_version.system_prompt
        else
          self.class.system_prompt
        end
      end
    end
  end
end
```

---

## Background Jobs

### ImprovementAnalysisJob

```ruby
# app/jobs/improvement_analysis_job.rb
module RubyLLM
  module Agents
    class ImprovementAnalysisJob < ApplicationJob
      queue_as :default

      def perform(agent_definition_id = nil)
        if agent_definition_id
          agent = AgentDefinition.find(agent_definition_id)
          ImprovementScheduler.new.analyze_agent(agent)
        else
          ImprovementScheduler.run_due_analyses
        end
      end
    end
  end
end
```

### Schedule with Sidekiq-Cron or Similar

```ruby
# config/initializers/sidekiq_cron.rb
Sidekiq::Cron::Job.create(
  name: 'Self-improvement analysis - daily',
  cron: '0 2 * * *',  # 2 AM daily
  class: 'RubyLLM::Agents::ImprovementAnalysisJob'
)
```

---

## API / Controller (Optional)

For reviewing and approving suggestions:

```ruby
# app/controllers/api/improvement_suggestions_controller.rb
module Api
  class ImprovementSuggestionsController < ApplicationController
    def index
      suggestions = ImprovementSuggestion
        .pending
        .includes(:agent_definition, :based_on_version)
        .order(created_at: :desc)

      render json: suggestions
    end

    def show
      suggestion = ImprovementSuggestion.find(params[:id])
      render json: suggestion, include: [:analyzed_executions, :based_on_version]
    end

    def approve
      suggestion = ImprovementSuggestion.find(params[:id])
      new_version = suggestion.approve!(user: current_user)

      if params[:activate]
        new_version.activate!
      end

      render json: suggestion
    end

    def reject
      suggestion = ImprovementSuggestion.find(params[:id])
      suggestion.reject!(user: current_user, reason: params[:reason])
      render json: suggestion
    end
  end
end
```

---

## Implementation Order

### Phase 1: Database & Models
1. [ ] Create migrations for all new tables
2. [ ] Implement `PromptVersion` model with versioning logic
3. [ ] Implement `ImprovementSuggestion` model
4. [ ] Update `AgentDefinition` with self-improvement fields
5. [ ] Update `Execution` to track prompt version + resolved prompt

### Phase 2: Template Interpolation
6. [ ] Implement `PromptInterpolator` service
7. [ ] Implement `PromptVariablesConfig` DSL class
8. [ ] Add variable resolution (params, config, method, context)
9. [ ] Add validation for required variables
10. [ ] Update execution flow to use resolved prompts

### Phase 3: Self-Improving DSL
11. [ ] Implement `SelfImprovingConfig` DSL class
12. [ ] Integrate DSL into `Agent` base class
13. [ ] Add validation for required fields when enabled
14. [ ] Update agent registration to persist settings to DB

### Phase 4: Improvement Engine
15. [ ] Implement `ImprovementAnalyzer` service
16. [ ] Design and test the improvement agent prompt
17. [ ] Ensure template variables are preserved in suggestions
18. [ ] Implement `ImprovementScheduler` service
19. [ ] Create background job for scheduled analysis

### Phase 5: Approval Workflow
20. [ ] Implement approval/rejection flow
21. [ ] Add activation and rollback logic
22. [ ] Create API endpoints for managing suggestions
23. [ ] Add notifications for pending suggestions

### Phase 6: Testing & Refinement
24. [ ] Write comprehensive tests for interpolation
25. [ ] Write tests for self-improvement flow
26. [ ] Test with real agent executions
27. [ ] Tune the improvement agent prompt
28. [ ] Add monitoring and logging

---

## Open Questions

1. **Rollback triggers**: Should we auto-rollback if error rate spikes after a new prompt version is activated?

2. **Diff visualization**: Should we generate a visual diff between prompt versions for easier review?

3. **Execution sampling**: For high-volume agents, should we sample executions or analyze all?

4. **Multi-tenant prompt versions**: Should each tenant have their own prompt versions, or share globally? Options:
   - Shared: All tenants use same prompt versions (simpler)
   - Per-tenant: Each tenant has own version history (more complex, but allows tenant-specific improvements)
   - Hybrid: Global template + per-tenant overrides

5. **Variable validation**: Should we validate at registration time that all `{{variables}}` in the template have corresponding definitions in `prompt_variables`?

6. **New variable suggestions**: If improvement agent notices a pattern that could benefit from a new variable, how should it communicate this? (Since it can't add new variables itself)

7. **Sensitive data in executions**: The resolved prompts stored in executions may contain PII (customer names, etc.). Do we need encryption or redaction?

8. **A/B testing**: Should we support running multiple prompt versions simultaneously to compare performance before full activation?

---

## Example Usage

### Full Example with Dynamic Variables

```ruby
class CustomerSupportAgent < RubyLLM::Agent
  model "claude-sonnet"

  # Template with {{variables}} - stored in DB, versioned
  system_prompt <<~PROMPT
    You are a helpful customer support agent for {{company_name}}.

    You are helping {{customer_name}}, who is on the {{customer_plan}} plan.
    They have been a customer for {{account_age}}.

    Guidelines:
    - Be friendly, professional, and concise
    - Reference their plan benefits when relevant
    - If they're a long-time customer, acknowledge their loyalty
  PROMPT

  # Define variable sources
  prompt_variables do
    variable :company_name, from: :config
    variable :customer_name, from: :params
    variable :customer_plan, from: :params
    variable :account_age, from: :method  # Computed
  end

  # Method-based variable
  def account_age
    customer = params[:customer]
    days = ((Time.current - customer.created_at) / 1.day).round
    case days
    when 0..30 then "#{days} days (new customer)"
    when 31..365 then "#{(days / 30.0).round} months"
    else "#{(days / 365.0).round} years"
    end
  end

  self_improving do
    enabled true
    approval :manual
    frequency :daily

    success_criteria <<~TEXT
      A successful execution:
      - Directly answers the customer's question
      - Provides actionable steps, not vague advice
      - Personalizes response based on customer context
      - Resolves the issue in one response when possible

      A failed execution:
      - Customer had to ask follow-up questions
      - Response was generic or impersonal
      - Didn't leverage customer context (plan, tenure)
      - Was overly verbose without being helpful
    TEXT

    optimize_for <<~TEXT
      - Use customer's plan info to give relevant answers
      - Acknowledge loyalty for long-time customers
      - Reduce back-and-forth by being comprehensive
      - Match the tone to the customer's tone
    TEXT
  end
end
```

### Runtime Usage

```ruby
# Initialize with config (company-level settings)
agent = CustomerSupportAgent.new(
  config: { company_name: "Acme Corp" }
)

# Run with runtime params (request-specific)
result = agent.run(
  task: "How do I upgrade my plan?",
  params: {
    customer_name: "Jane Smith",
    customer_plan: "Starter",
    customer: Customer.find(123)  # For method-based variables
  }
)

# What actually gets sent to LLM (resolved):
# "You are a helpful customer support agent for Acme Corp.
#
#  You are helping Jane Smith, who is on the Starter plan.
#  They have been a customer for 8 months.
#  ..."
```

### What Gets Stored in Execution

```ruby
execution.prompt_version_id      # -> Links to template version
execution.resolved_system_prompt # -> "You are a helpful... for Acme Corp... Jane Smith..."
execution.interpolation_params   # -> { customer_name: "Jane Smith", customer_plan: "Starter", ... }
```

### Self-Improvement Flow

```ruby
# Register agent (creates initial prompt version in DB)
agent.register!

# After many executions, trigger analysis
RubyLLM::Agents::ImprovementAnalysisJob.perform_now(agent.agent_definition.id)

# Review pending suggestions
suggestions = ImprovementSuggestion.pending.where(agent_definition: agent.agent_definition)

suggestion = suggestions.first
puts suggestion.reasoning
# "Analysis of 50 executions shows that responses to Starter plan
#  customers often don't mention upgrade paths. Suggesting adding
#  a line about mentioning upgrade options when relevant."

puts suggestion.suggested_prompt
# Template with {{vars}} preserved, but improved text around them

# Approve and optionally activate
new_version = suggestion.approve!(user: current_user)
new_version.activate!  # Makes this the active version

# Future executions now use improved template
```

### What the Improvement Agent Sees

```ruby
# It receives the TEMPLATE (with {{vars}}), not resolved values
# This way it can suggest improvements that work for ALL customers

# Input to improvement agent:
# - Template: "You are a helpful support agent for {{company_name}}..."
# - Executions: Shows resolved prompts + inputs + outputs
# - Success criteria: User's text description
# - Optimize for: User's text description

# Output from improvement agent:
# - Suggested template (MUST preserve {{vars}})
# - Reasoning for changes
# - Patterns observed
```
