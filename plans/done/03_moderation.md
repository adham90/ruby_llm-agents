# Content Moderation Support Implementation Plan

## Overview

Add content moderation support to ruby_llm-agents, allowing agents to automatically check user input and/or LLM output against safety policies before proceeding. This builds on RubyLLM's `RubyLLM.moderate()` API to provide a declarative DSL for configuring moderation at the agent level.

## Why Content Moderation?

Content moderation is essential for production applications:
- **Safety**: Prevent harmful content from being processed or generated
- **Compliance**: Meet content policy requirements for user-facing applications
- **Cost Efficiency**: Reject problematic inputs before expensive LLM calls
- **Auditability**: Track moderation decisions for compliance reporting

## RubyLLM Moderation API

RubyLLM provides moderation via OpenAI's moderation endpoint:

```ruby
result = RubyLLM.moderate("Text to check")
result.flagged?           # => true/false
result.flagged_categories # => [:hate, :violence]
result.category_scores    # => { hate: 0.92, violence: 0.85, ... }
```

**Available Categories**: sexual, hate, harassment, self-harm, sexual/minors, hate/threatening, violence, violence/graphic, self-harm/intent, self-harm/instructions, harassment/threatening

## API Design

### Basic Usage

```ruby
class SafeAssistant < ApplicationAgent
  model 'gpt-4o'

  # Enable input moderation with defaults
  moderation :input

  param :message, required: true

  def user_prompt
    message
  end
end

# Usage
result = SafeAssistant.call(message: "Hello!")
result.content # => "Hi there! How can I help?"

# With flagged content
result = SafeAssistant.call(message: "harmful content here")
result.moderation_flagged?  # => true
result.moderation_result    # => RubyLLM::Moderation object
result.content              # => nil (blocked before LLM call)
result.status               # => :moderation_blocked
```

### Moderate Output

```ruby
class ContentGenerator < ApplicationAgent
  model 'gpt-4o'

  # Check LLM output before returning
  moderation :output

  param :topic, required: true

  def user_prompt
    "Write a story about #{topic}"
  end
end

result = ContentGenerator.call(topic: "adventure")
result.moderation_flagged? # => false if output is clean

# If output contains flagged content
result.status              # => :output_moderation_blocked
result.moderation_result   # => Moderation result for the output
```

### Moderate Both Input and Output

```ruby
class FullyModeratedAgent < ApplicationAgent
  model 'gpt-4o'

  moderation :both  # or moderation :input, :output

  param :message, required: true

  def user_prompt
    message
  end
end
```

### Configuration Options

```ruby
class ConfiguredModerationAgent < ApplicationAgent
  model 'gpt-4o'

  moderation :input,
    model: 'omni-moderation-latest',        # Moderation model to use
    threshold: 0.8,                          # Score threshold (0.0-1.0)
    categories: [:hate, :violence],          # Only check these categories
    on_flagged: :raise,                      # :raise, :block, :warn, :log
    custom_handler: :handle_moderation       # Custom handler method

  param :message, required: true

  def user_prompt
    message
  end

  # Custom handler for flagged content
  def handle_moderation(moderation_result, phase)
    Rails.logger.warn("Content flagged: #{moderation_result.flagged_categories}")
    # Return :continue to proceed anyway, :block to stop
    moderation_result.category_scores.values.max > 0.9 ? :block : :continue
  end
end
```

### Block-based DSL (Alternative)

```ruby
class AdvancedModerationAgent < ApplicationAgent
  model 'gpt-4o'

  moderation do
    input enabled: true, threshold: 0.7
    output enabled: true, threshold: 0.9
    model 'omni-moderation-latest'
    categories :hate, :violence, :harassment
    on_flagged :block
  end

  param :message, required: true

  def user_prompt
    message
  end
end
```

### Runtime Override

```ruby
# Disable moderation for specific call
result = SafeAssistant.call(
  message: "test content",
  moderation: false
)

# Override threshold
result = SafeAssistant.call(
  message: "content",
  moderation: { threshold: 0.95 }
)

# Override action
result = SafeAssistant.call(
  message: "content",
  moderation: { on_flagged: :warn }
)
```

### Standalone Moderation

For cases where you want to moderate without an agent:

```ruby
class ContentModerator < RubyLLM::Agents::Moderator
  model 'omni-moderation-latest'
  threshold 0.8
  categories :hate, :violence
end

result = ContentModerator.call(text: "content to check")
result.flagged?         # => true/false
result.flagged_categories
result.category_scores
result.passed?          # => opposite of flagged?
```

## Implementation Tasks

### 1. Moderation DSL Module (`lib/ruby_llm/agents/base/moderation_dsl.rb`)

```ruby
module RubyLLM
  module Agents
    class Base
      module ModerationDSL
        def moderation(*phases, **options, &block)
          if block_given?
            builder = ModerationBuilder.new
            builder.instance_eval(&block)
            @moderation_config = builder.config
          else
            phases = [:input] if phases.empty?
            @moderation_config = {
              phases: phases.flatten,
              model: options[:model],
              threshold: options[:threshold],
              categories: options[:categories],
              on_flagged: options[:on_flagged] || :block,
              custom_handler: options[:custom_handler]
            }
          end
        end

        def moderation_config
          @moderation_config || inherited_or_default(:moderation_config, nil)
        end

        def moderation_enabled?
          !!moderation_config
        end
      end

      class ModerationBuilder
        attr_reader :config

        def initialize
          @config = { phases: [], on_flagged: :block }
        end

        def input(enabled: true, threshold: nil)
          @config[:phases] << :input if enabled
          @config[:input_threshold] = threshold if threshold
        end

        def output(enabled: true, threshold: nil)
          @config[:phases] << :output if enabled
          @config[:output_threshold] = threshold if threshold
        end

        def model(model_name)
          @config[:model] = model_name
        end

        def threshold(value)
          @config[:threshold] = value
        end

        def categories(*cats)
          @config[:categories] = cats.flatten
        end

        def on_flagged(action)
          @config[:on_flagged] = action
        end
      end
    end
  end
end
```

### 2. Moderation Execution Module (`lib/ruby_llm/agents/base/moderation_execution.rb`)

```ruby
module RubyLLM
  module Agents
    class Base
      module ModerationExecution
        def moderate_input(text)
          return nil unless should_moderate?(:input)

          perform_moderation(text, :input)
        end

        def moderate_output(text)
          return nil unless should_moderate?(:output)

          perform_moderation(text, :output)
        end

        private

        def should_moderate?(phase)
          config = resolved_moderation_config
          return false unless config
          return false if @options[:moderation] == false

          config[:phases].include?(phase)
        end

        def resolved_moderation_config
          runtime_config = @options[:moderation]
          return nil if runtime_config == false

          base_config = self.class.moderation_config
          return nil unless base_config

          if runtime_config.is_a?(Hash)
            base_config.merge(runtime_config)
          else
            base_config
          end
        end

        def perform_moderation(text, phase)
          config = resolved_moderation_config

          result = RubyLLM.moderate(
            text,
            model: config[:model] || default_moderation_model
          )

          @moderation_results ||= {}
          @moderation_results[phase] = result

          if content_flagged?(result, config, phase)
            handle_flagged_content(result, config, phase)
          end

          result
        end

        def content_flagged?(result, config, phase)
          return false unless result.flagged?

          # Check threshold
          threshold = config["#{phase}_threshold".to_sym] || config[:threshold]
          if threshold
            max_score = result.category_scores.values.max
            return false if max_score < threshold
          end

          # Check categories
          if config[:categories]
            flagged = result.flagged_categories.map(&:to_sym)
            allowed = config[:categories].map(&:to_sym)
            return false if (flagged & allowed).empty?
          end

          true
        end

        def handle_flagged_content(result, config, phase)
          # Custom handler
          if config[:custom_handler]
            action = send(config[:custom_handler], result, phase)
            return if action == :continue
          end

          case config[:on_flagged]
          when :raise
            raise ModerationError.new(result, phase)
          when :block
            @moderation_blocked = true
            @moderation_blocked_phase = phase
          when :warn
            Rails.logger.warn("Content flagged in #{phase}: #{result.flagged_categories}")
          when :log
            Rails.logger.info("Content flagged in #{phase}: #{result.flagged_categories}")
          end
        end

        def default_moderation_model
          RubyLLM::Agents.configuration.default_moderation_model || 'omni-moderation-latest'
        end
      end
    end
  end
end
```

### 3. Moderation Error Class (`lib/ruby_llm/agents/errors.rb`)

```ruby
module RubyLLM
  module Agents
    class ModerationError < StandardError
      attr_reader :moderation_result, :phase

      def initialize(moderation_result, phase)
        @moderation_result = moderation_result
        @phase = phase
        super("Content flagged during #{phase} moderation: #{moderation_result.flagged_categories.join(', ')}")
      end

      def flagged_categories
        moderation_result.flagged_categories
      end

      def category_scores
        moderation_result.category_scores
      end
    end
  end
end
```

### 4. Update Base Execution (`lib/ruby_llm/agents/base/execution.rb`)

Add moderation checks to the call flow:

```ruby
def uncached_call
  # Check input moderation BEFORE making LLM call
  if self.class.moderation_enabled?
    input_text = build_moderation_input
    moderate_input(input_text)

    if @moderation_blocked
      return build_moderation_blocked_result(:input)
    end
  end

  # Existing LLM call logic...
  response = execute_llm_call

  # Check output moderation AFTER LLM call
  if self.class.moderation_enabled?
    moderate_output(response.content)

    if @moderation_blocked
      return build_moderation_blocked_result(:output)
    end
  end

  build_result(response)
end

def build_moderation_input
  # Combine user prompt for moderation
  prompt = user_prompt
  prompt.is_a?(Array) ? prompt.map { |p| p[:content] }.join("\n") : prompt.to_s
end

def build_moderation_blocked_result(phase)
  Result.new(
    content: nil,
    status: :"#{phase}_moderation_blocked",
    moderation_flagged: true,
    moderation_result: @moderation_results[phase],
    moderation_phase: phase,
    agent_class: self.class.name,
    model_id: resolved_model,
    input_tokens: 0,
    output_tokens: 0,
    total_cost: moderation_cost
  )
end
```

### 5. Update Result Class (`lib/ruby_llm/agents/result.rb`)

Add moderation attributes:

```ruby
module RubyLLM
  module Agents
    class Result
      attr_reader :moderation_result, :moderation_phase

      def initialize(attributes = {})
        # Existing attributes...
        @moderation_flagged = attributes[:moderation_flagged] || false
        @moderation_result = attributes[:moderation_result]
        @moderation_phase = attributes[:moderation_phase]
      end

      def moderation_flagged?
        @moderation_flagged
      end

      def moderation_passed?
        !@moderation_flagged
      end

      def moderation_categories
        @moderation_result&.flagged_categories || []
      end

      def moderation_scores
        @moderation_result&.category_scores || {}
      end
    end
  end
end
```

### 6. Standalone Moderator Class (`lib/ruby_llm/agents/moderator.rb`)

```ruby
module RubyLLM
  module Agents
    class Moderator
      extend DSL

      class << self
        def model(value = nil)
          @model = value if value
          @model || RubyLLM::Agents.configuration.default_moderation_model || 'omni-moderation-latest'
        end

        def threshold(value = nil)
          @threshold = value if value
          @threshold
        end

        def categories(*cats)
          @categories = cats.flatten if cats.any?
          @categories
        end

        def call(text:, **options)
          new.call(text: text, **options)
        end
      end

      def call(text:, **options)
        model = options[:model] || self.class.model

        result = RubyLLM.moderate(text, model: model)

        ModerationResult.new(
          result: result,
          threshold: options[:threshold] || self.class.threshold,
          categories: options[:categories] || self.class.categories
        )
      end
    end

    class ModerationResult
      attr_reader :raw_result, :threshold, :filter_categories

      def initialize(result:, threshold: nil, categories: nil)
        @raw_result = result
        @threshold = threshold
        @filter_categories = categories
      end

      def flagged?
        return false unless raw_result.flagged?
        return passes_threshold? && passes_category_filter?
      end

      def passed?
        !flagged?
      end

      def flagged_categories
        cats = raw_result.flagged_categories
        cats = cats.select { |c| filter_categories.include?(c.to_sym) } if filter_categories
        cats
      end

      def category_scores
        raw_result.category_scores
      end

      def id
        raw_result.id
      end

      def model
        raw_result.model
      end

      private

      def passes_threshold?
        return true unless threshold
        category_scores.values.max >= threshold
      end

      def passes_category_filter?
        return true unless filter_categories
        (raw_result.flagged_categories.map(&:to_sym) & filter_categories.map(&:to_sym)).any?
      end
    end
  end
end
```

### 7. Configuration Updates (`lib/ruby_llm/agents/configuration.rb`)

```ruby
module RubyLLM
  module Agents
    class Configuration
      # Existing options...

      # Moderation defaults
      attr_accessor :default_moderation_model
      attr_accessor :default_moderation_threshold
      attr_accessor :default_moderation_action  # :block, :raise, :warn, :log
      attr_accessor :track_moderation           # Log moderation to executions table

      def initialize
        # Existing defaults...

        # Moderation defaults
        @default_moderation_model = 'omni-moderation-latest'
        @default_moderation_threshold = nil  # No threshold by default
        @default_moderation_action = :block
        @track_moderation = true
      end
    end
  end
end
```

### 8. Execution Tracking for Moderation

Add moderation tracking to executions:

```ruby
# In moderation_execution.rb
def record_moderation_execution(result, phase)
  return unless RubyLLM::Agents.configuration.track_moderation

  RubyLLM::Agents::Execution.create!(
    agent_type: self.class.name,
    execution_type: 'moderation',
    model_id: result.model,
    input_tokens: estimate_moderation_tokens(result),
    output_tokens: 0,
    total_cost: 0,  # Moderation is typically free or very cheap
    status: result.flagged? ? 'flagged' : 'passed',
    metadata: {
      phase: phase,
      flagged: result.flagged?,
      flagged_categories: result.flagged_categories,
      category_scores: result.category_scores
    },
    tenant_id: @tenant_id
  )
end
```

### 9. Update Includes in Base Class

```ruby
# lib/ruby_llm/agents/base.rb
module RubyLLM
  module Agents
    class Base
      include Instrumentation
      include Caching
      include CostCalculation
      include ToolTracking
      include ResponseBuilding
      include ModerationExecution  # Add moderation
      include Execution
      include ReliabilityExecution
      extend DSL
      extend ModerationDSL  # Add moderation DSL
    end
  end
end
```

### 10. Generator for Migration (`lib/generators/ruby_llm_agents/moderation_generator.rb`)

```ruby
module RubyLlmAgents
  class ModerationGenerator < ::Rails::Generators::Base
    include ::ActiveRecord::Generators::Migration
    source_root File.expand_path("templates", __dir__)

    def create_moderation_migration
      migration_template(
        "add_moderation_to_executions_migration.rb.tt",
        File.join(db_migrate_path, "add_moderation_fields_to_ruby_llm_agents_executions.rb")
      )
    end

    private

    def db_migrate_path
      "db/migrate"
    end
  end
end
```

### 11. Migration Template

```ruby
# templates/add_moderation_to_executions_migration.rb.tt
class AddModerationFieldsToRubyLlmAgentsExecutions < ActiveRecord::Migration[<%= ActiveRecord::Migration.current_version %>]
  def change
    # Add index for execution_type if not exists
    unless index_exists?(:ruby_llm_agents_executions, :execution_type)
      add_index :ruby_llm_agents_executions, :execution_type
    end
  end
end
```

## File Structure

```
lib/ruby_llm/agents/
├── base.rb                           # Updated with moderation includes
├── base/
│   ├── dsl.rb                        # Existing DSL
│   ├── execution.rb                  # Updated with moderation checks
│   ├── moderation_dsl.rb             # NEW: Moderation DSL methods
│   └── moderation_execution.rb       # NEW: Moderation execution logic
├── moderator.rb                      # NEW: Standalone moderator class
├── moderation_result.rb              # NEW: Moderation result wrapper
├── errors.rb                         # Updated with ModerationError
├── result.rb                         # Updated with moderation attributes
└── configuration.rb                  # Updated with moderation config

lib/generators/ruby_llm_agents/
├── moderation_generator.rb           # NEW: Moderation setup generator
└── templates/
    └── add_moderation_migration.rb.tt

spec/
├── moderation_spec.rb                # NEW: Moderation feature tests
├── moderator_spec.rb                 # NEW: Standalone moderator tests
└── moderation/
    ├── dsl_spec.rb
    ├── execution_spec.rb
    └── result_spec.rb

example/app/agents/
└── moderated_agent.rb                # NEW: Example moderated agent
```

## Usage Examples

### Chat Application with Input Moderation

```ruby
class ChatAgent < ApplicationAgent
  model 'gpt-4o'
  moderation :input

  param :user_message, required: true

  def user_prompt
    user_message
  end
end

# Controller
def create
  result = ChatAgent.call(user_message: params[:message])

  if result.moderation_flagged?
    render json: {
      error: "Your message was flagged for: #{result.moderation_categories.join(', ')}"
    }, status: :unprocessable_entity
  else
    render json: { response: result.content }
  end
end
```

### Content Generation with Output Moderation

```ruby
class StoryGenerator < ApplicationAgent
  model 'gpt-4o'
  moderation :output, threshold: 0.7

  param :prompt, required: true

  def system_prompt
    "You are a creative story writer."
  end

  def user_prompt
    "Write a short story about: #{prompt}"
  end
end
```

### Fully Moderated Agent with Custom Handler

```ruby
class FullyModeratedAgent < ApplicationAgent
  model 'gpt-4o'

  moderation :both,
    threshold: 0.6,
    categories: [:hate, :violence, :harassment],
    custom_handler: :review_moderation

  param :message, required: true

  def user_prompt
    message
  end

  private

  def review_moderation(result, phase)
    # Log for review
    ModerationLog.create!(
      content: phase == :input ? message : nil,
      phase: phase,
      categories: result.flagged_categories,
      scores: result.category_scores
    )

    # Block high-severity, warn on medium
    max_score = result.category_scores.values.max
    max_score > 0.8 ? :block : :continue
  end
end
```

### Standalone Moderation for Background Jobs

```ruby
class ContentModerator < RubyLLM::Agents::Moderator
  model 'omni-moderation-latest'
  threshold 0.7
  categories :hate, :violence, :sexual
end

class ModeratePendingContentJob < ApplicationJob
  def perform(content_id)
    content = UserContent.find(content_id)
    result = ContentModerator.call(text: content.body)

    if result.flagged?
      content.update!(
        status: :flagged,
        moderation_categories: result.flagged_categories
      )
    else
      content.update!(status: :approved)
    end
  end
end
```

### Multi-Tenant Moderation

```ruby
class TenantModeratedAgent < ApplicationAgent
  model 'gpt-4o'
  moderation :input

  param :message, required: true

  def user_prompt
    message
  end
end

# Uses tenant's API configuration for moderation
result = TenantModeratedAgent.call(
  message: user_input,
  tenant: current_organization
)
```

## Testing Strategy

### 1. Unit Tests

```ruby
RSpec.describe RubyLLM::Agents::Base::ModerationDSL do
  describe '.moderation' do
    it 'configures input moderation' do
      agent_class = Class.new(RubyLLM::Agents::Base) do
        moderation :input
      end

      expect(agent_class.moderation_config[:phases]).to eq([:input])
    end

    it 'configures with options' do
      agent_class = Class.new(RubyLLM::Agents::Base) do
        moderation :input, threshold: 0.8, categories: [:hate]
      end

      expect(agent_class.moderation_config[:threshold]).to eq(0.8)
      expect(agent_class.moderation_config[:categories]).to eq([:hate])
    end
  end
end
```

### 2. Integration Tests

```ruby
RSpec.describe 'Moderation Integration' do
  let(:agent_class) do
    Class.new(ApplicationAgent) do
      model 'gpt-4o'
      moderation :input

      param :message, required: true

      def user_prompt
        message
      end
    end
  end

  it 'blocks flagged input' do
    allow(RubyLLM).to receive(:moderate).and_return(
      double(flagged?: true, flagged_categories: [:hate], category_scores: { hate: 0.95 })
    )

    result = agent_class.call(message: "flagged content")

    expect(result.moderation_flagged?).to be true
    expect(result.status).to eq(:input_moderation_blocked)
    expect(result.content).to be_nil
  end

  it 'proceeds with clean input' do
    allow(RubyLLM).to receive(:moderate).and_return(
      double(flagged?: false, flagged_categories: [], category_scores: {})
    )
    allow(RubyLLM).to receive(:chat).and_return(
      double(content: "Hello!", input_tokens: 10, output_tokens: 5)
    )

    result = agent_class.call(message: "hello")

    expect(result.moderation_flagged?).to be false
    expect(result.content).to eq("Hello!")
  end
end
```

### 3. Threshold Tests

```ruby
RSpec.describe 'Moderation Thresholds' do
  let(:agent_class) do
    Class.new(ApplicationAgent) do
      moderation :input, threshold: 0.8
    end
  end

  it 'allows content below threshold' do
    allow(RubyLLM).to receive(:moderate).and_return(
      double(flagged?: true, flagged_categories: [:hate], category_scores: { hate: 0.5 })
    )

    # Should proceed because score (0.5) < threshold (0.8)
  end
end
```

## Open Questions

1. **Should moderation results be cached?**
   - Same content always produces same moderation result
   - Could reduce API calls for repeated content
   - **Recommendation**: Add opt-in caching similar to agent response caching

2. **Should we add batch moderation support?**
   - Useful for moderating multiple pieces of content
   - **Recommendation**: Phase 2 feature, focus on per-agent moderation first

3. **Should moderation costs be tracked separately in budgets?**
   - Moderation API calls are typically very cheap but not free
   - **Recommendation**: Track in executions table but don't count toward chat budgets by default

4. **Should we support multiple moderation providers?**
   - Currently only OpenAI provides moderation
   - **Recommendation**: Design for single provider, make extensible for future

5. **Should output moderation re-try with a different prompt if flagged?**
   - Could automatically regenerate if output is flagged
   - **Recommendation**: Add as optional behavior in Phase 2

6. **Should we add pre-built moderation policies?**
   - E.g., `moderation :strict`, `moderation :permissive`
   - **Recommendation**: Keep flexible, document common patterns

## Implementation Order

1. **Phase 1 - Core Moderation** (This plan)
   - ModerationDSL module
   - ModerationExecution module
   - Result updates
   - Configuration updates
   - Basic tests

2. **Phase 2 - Standalone Moderator**
   - Moderator class
   - ModerationResult class
   - Caching support

3. **Phase 3 - Advanced Features**
   - Batch moderation
   - Auto-retry on output flag
   - Custom category definitions
   - Moderation analytics/reporting

## Cost Considerations

OpenAI moderation API is very inexpensive:
- Moderation calls are significantly cheaper than chat completions
- No token limits for moderation (full content can be checked)

Recommendation: Always moderate user input for public-facing applications.
