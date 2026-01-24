# Plan: Wait/Delay Steps for Workflows

## Overview

Add comprehensive wait/delay functionality to the workflow DSL, enabling workflows to pause execution for fixed durations, wait for conditions, throttle API calls, schedule execution, and support human-in-the-loop approval patterns.

## Features

### 1. Simple Delay (`wait`)
Fixed-duration pause in workflow execution.

```ruby
class OrderWorkflow < RubyLLM::Agents::Workflow
  step :create_order, OrderAgent

  wait 5.seconds

  step :send_confirmation, EmailAgent
end
```

**Options:**
- `wait duration` - Pause for specified duration
- `wait duration, if: :condition?` - Conditional wait
- `wait duration, unless: :skip_condition?` - Inverse conditional

### 2. Conditional Wait (`wait_until`)
Poll until a condition is met or timeout occurs.

```ruby
class PaymentWorkflow < RubyLLM::Agents::Workflow
  step :initiate_payment, PaymentAgent

  wait_until -> { payment.status == "confirmed" },
    poll_interval: 5.seconds,
    timeout: 10.minutes,
    on_timeout: :fail

  step :fulfill, FulfillmentAgent
end
```

**Options:**
- `condition` - Lambda/Proc that returns true when ready to proceed
- `poll_interval:` - How often to check condition (default: 1.second)
- `timeout:` - Maximum wait time (default: nil = forever)
- `on_timeout:` - Action when timeout: `:fail`, `:continue`, `:skip_next` (default: :fail)
- `backoff:` - Exponential backoff multiplier (default: nil = fixed interval)
- `max_interval:` - Maximum poll interval when using backoff

### 3. Throttle/Rate Limit
Ensure minimum time between step executions.

```ruby
class BatchProcessor < RubyLLM::Agents::Workflow
  step :fetch_data, FetchAgent, throttle: 1.second
  step :process, ProcessAgent
  step :upload, UploadAgent, throttle: 500.milliseconds
end
```

**Options:**
- `throttle:` - Minimum duration since last execution of this step
- `rate_limit:` - Alternative syntax: `rate_limit: { calls: 10, per: 1.minute }`

### 4. Scheduled Wait (`wait_until time:`)
Wait until a specific time or schedule.

```ruby
class ReportWorkflow < RubyLLM::Agents::Workflow
  step :generate, ReportAgent

  wait_until time: -> { next_weekday_at(9, 0) }

  step :send, EmailAgent
end
```

**Options:**
- `time:` - Lambda returning DateTime, or Time object
- `timezone:` - Timezone for calculations (default: system timezone)

**Helper Methods:**
- `next_weekday_at(hour, minute)` - Next Mon-Fri at specified time
- `next_hour` - Start of next hour
- `tomorrow_at(hour, minute)` - Tomorrow at specified time
- `in_business_hours` - Next available business hour window

### 5. Human-in-the-Loop (`wait_for`)
Pause workflow for human approval or input.

```ruby
class ContentWorkflow < RubyLLM::Agents::Workflow
  step :draft, DraftAgent
  step :review, ReviewAgent

  wait_for :approval,
    notify: [:email, :slack],
    message: -> { "Please review: #{draft.title}" },
    timeout: 24.hours,
    reminder_after: 4.hours,
    escalate_to: :manager_approval

  step :publish, PublishAgent
end
```

**Options:**
- `name` - Identifier for the approval point
- `notify:` - Notification channels (`:email`, `:slack`, `:webhook`, custom)
- `message:` - Custom message (string or lambda)
- `timeout:` - Maximum wait time
- `reminder_after:` - Send reminder after duration
- `reminder_interval:` - Repeat reminders at interval
- `escalate_to:` - Another approval point or handler on timeout
- `on_timeout:` - Action: `:fail`, `:auto_approve`, `:escalate`
- `approvers:` - List of user IDs or roles who can approve

---

## Implementation Plan

### Phase 1: Core Infrastructure

#### 1.1 Create Wait Step Types
**File:** `lib/ruby_llm/agents/workflow/dsl/wait_config.rb`

```ruby
module RubyLLM
  module Agents
    class Workflow
      module DSL
        class WaitConfig
          attr_reader :type, :duration, :options

          TYPES = [:delay, :until, :schedule, :approval].freeze

          def initialize(type:, duration: nil, condition: nil, **options)
            @type = type
            @duration = duration
            @condition = condition
            @options = options
          end

          def delay?
            type == :delay
          end

          def conditional?
            type == :until
          end

          def scheduled?
            type == :schedule
          end

          def approval?
            type == :approval
          end

          def poll_interval
            options[:poll_interval] || 1.second
          end

          def timeout
            options[:timeout]
          end

          def on_timeout
            options[:on_timeout] || :fail
          end
        end
      end
    end
  end
end
```

#### 1.2 Add DSL Methods
**File:** `lib/ruby_llm/agents/workflow/dsl.rb` (extend ClassMethods)

```ruby
# Simple delay
def wait(duration, **options)
  config = WaitConfig.new(type: :delay, duration: duration, **options)
  wait_configs << config
  step_order << config
end

# Conditional wait
def wait_until(condition = nil, time: nil, **options, &block)
  condition ||= block

  if time
    config = WaitConfig.new(type: :schedule, condition: time, **options)
  else
    config = WaitConfig.new(type: :until, condition: condition, **options)
  end

  wait_configs << config
  step_order << config
end

# Human approval
def wait_for(name, **options)
  config = WaitConfig.new(type: :approval, name: name, **options)
  wait_configs << config
  step_order << config
end

def wait_configs
  @wait_configs ||= []
end
```

#### 1.3 Add Throttle Support to Step Config
**File:** `lib/ruby_llm/agents/workflow/dsl/step_config.rb` (extend)

```ruby
def throttle
  options[:throttle]
end

def rate_limit
  options[:rate_limit]
end

def throttled?
  throttle.present? || rate_limit.present?
end
```

### Phase 2: Execution Engine

#### 2.1 Create Wait Executor
**File:** `lib/ruby_llm/agents/workflow/dsl/wait_executor.rb`

```ruby
module RubyLLM
  module Agents
    class Workflow
      module DSL
        class WaitExecutor
          def initialize(wait_config, context)
            @config = wait_config
            @context = context
          end

          def execute
            case @config.type
            when :delay
              execute_delay
            when :until
              execute_until
            when :schedule
              execute_schedule
            when :approval
              execute_approval
            end
          end

          private

          def execute_delay
            duration = resolve_duration(@config.duration)
            sleep_with_interruption(duration)
            WaitResult.success(:delay, duration)
          end

          def execute_until
            started_at = Time.current
            interval = @config.poll_interval
            timeout = @config.timeout

            loop do
              # Check condition
              result = evaluate_condition(@config.condition)
              return WaitResult.success(:until, Time.current - started_at) if result

              # Check timeout
              if timeout && (Time.current - started_at) >= timeout
                return handle_timeout(started_at)
              end

              # Wait before next poll
              sleep_with_interruption(interval)
              interval = apply_backoff(interval) if @config.options[:backoff]
            end
          end

          def execute_schedule
            target_time = evaluate_time(@config.condition)
            wait_duration = target_time - Time.current

            if wait_duration > 0
              sleep_with_interruption(wait_duration)
            end

            WaitResult.success(:schedule, target_time)
          end

          def execute_approval
            # Store approval request
            approval = create_approval_request

            # Send notifications
            send_notifications(approval)

            # Wait for approval or timeout
            wait_for_approval(approval)
          end

          def sleep_with_interruption(duration)
            # Use Async.sleep if available, otherwise Kernel.sleep
            if defined?(Async) && Async::Task.current?
              Async::Task.current.sleep(duration)
            else
              Kernel.sleep(duration)
            end
          end
        end
      end
    end
  end
end
```

#### 2.2 Create Wait Result
**File:** `lib/ruby_llm/agents/workflow/wait_result.rb`

```ruby
module RubyLLM
  module Agents
    class Workflow
      class WaitResult
        attr_reader :type, :status, :waited_duration, :metadata

        def initialize(type:, status:, waited_duration: nil, metadata: {})
          @type = type
          @status = status
          @waited_duration = waited_duration
          @metadata = metadata
        end

        def self.success(type, waited_duration, **metadata)
          new(type: type, status: :success, waited_duration: waited_duration, metadata: metadata)
        end

        def self.timeout(type, waited_duration, action_taken, **metadata)
          new(type: type, status: :timeout, waited_duration: waited_duration,
              metadata: metadata.merge(action_taken: action_taken))
        end

        def self.approved(approval_id, approved_by, waited_duration)
          new(type: :approval, status: :approved, waited_duration: waited_duration,
              metadata: { approval_id: approval_id, approved_by: approved_by })
        end

        def self.rejected(approval_id, rejected_by, waited_duration, reason: nil)
          new(type: :approval, status: :rejected, waited_duration: waited_duration,
              metadata: { approval_id: approval_id, rejected_by: rejected_by, reason: reason })
        end

        def success?
          status == :success || status == :approved
        end

        def timeout?
          status == :timeout
        end

        def approved?
          status == :approved
        end

        def rejected?
          status == :rejected
        end
      end
    end
  end
end
```

#### 2.3 Throttle Manager
**File:** `lib/ruby_llm/agents/workflow/throttle_manager.rb`

```ruby
module RubyLLM
  module Agents
    class Workflow
      class ThrottleManager
        def initialize
          @last_execution = {}
          @mutex = Mutex.new
        end

        def throttle(key, duration)
          @mutex.synchronize do
            last = @last_execution[key]

            if last
              elapsed = Time.current - last
              remaining = duration - elapsed

              if remaining > 0
                sleep(remaining)
              end
            end

            @last_execution[key] = Time.current
          end
        end

        def rate_limit(key, calls:, per:)
          # Token bucket or sliding window implementation
        end
      end
    end
  end
end
```

### Phase 3: Human-in-the-Loop

#### 3.1 Approval Model
**File:** `lib/ruby_llm/agents/workflow/approval.rb`

```ruby
module RubyLLM
  module Agents
    class Workflow
      class Approval
        attr_reader :id, :workflow_id, :name, :status, :created_at
        attr_accessor :approved_by, :approved_at, :rejected_by, :rejected_at, :reason

        def initialize(workflow_id:, name:, metadata: {})
          @id = SecureRandom.uuid
          @workflow_id = workflow_id
          @name = name
          @status = :pending
          @metadata = metadata
          @created_at = Time.current
        end

        def approve!(user_id)
          @status = :approved
          @approved_by = user_id
          @approved_at = Time.current
        end

        def reject!(user_id, reason: nil)
          @status = :rejected
          @rejected_by = user_id
          @rejected_at = Time.current
          @reason = reason
        end

        def pending?
          status == :pending
        end

        def approved?
          status == :approved
        end

        def rejected?
          status == :rejected
        end
      end
    end
  end
end
```

#### 3.2 Approval Store (Abstract)
**File:** `lib/ruby_llm/agents/workflow/approval_store.rb`

```ruby
module RubyLLM
  module Agents
    class Workflow
      class ApprovalStore
        class << self
          def store
            @store ||= default_store
          end

          def store=(store)
            @store = store
          end

          private

          def default_store
            MemoryApprovalStore.new
          end
        end

        def save(approval)
          raise NotImplementedError
        end

        def find(id)
          raise NotImplementedError
        end

        def find_by_workflow(workflow_id)
          raise NotImplementedError
        end

        def pending_for_user(user_id)
          raise NotImplementedError
        end
      end

      class MemoryApprovalStore < ApprovalStore
        def initialize
          @approvals = {}
          @mutex = Mutex.new
        end

        def save(approval)
          @mutex.synchronize { @approvals[approval.id] = approval }
        end

        def find(id)
          @approvals[id]
        end

        def find_by_workflow(workflow_id)
          @approvals.values.select { |a| a.workflow_id == workflow_id }
        end
      end
    end
  end
end
```

#### 3.3 Notification Adapters
**File:** `lib/ruby_llm/agents/workflow/notifiers/base.rb`

```ruby
module RubyLLM
  module Agents
    class Workflow
      module Notifiers
        class Base
          def notify(approval, message)
            raise NotImplementedError
          end

          def remind(approval, message)
            notify(approval, "[Reminder] #{message}")
          end
        end

        class Email < Base
          def notify(approval, message)
            # Use configured mailer
            if defined?(ActionMailer)
              ApprovalMailer.request(approval, message).deliver_later
            end
          end
        end

        class Slack < Base
          def initialize(webhook_url: nil, channel: nil)
            @webhook_url = webhook_url || RubyLLM::Agents.configuration.slack_webhook_url
            @channel = channel
          end

          def notify(approval, message)
            # POST to Slack webhook
          end
        end

        class Webhook < Base
          def initialize(url:, headers: {})
            @url = url
            @headers = headers
          end

          def notify(approval, message)
            # POST to custom webhook
          end
        end
      end
    end
  end
end
```

### Phase 4: ActiveRecord Integration (Optional)

#### 4.1 Approval Migration
**File:** `lib/generators/ruby_llm/agents/templates/create_workflow_approvals.rb`

```ruby
class CreateWorkflowApprovals < ActiveRecord::Migration[7.0]
  def change
    create_table :ruby_llm_agents_workflow_approvals do |t|
      t.string :workflow_id, null: false, index: true
      t.string :workflow_type, null: false
      t.string :name, null: false
      t.string :status, default: 'pending', null: false
      t.string :approved_by
      t.datetime :approved_at
      t.string :rejected_by
      t.datetime :rejected_at
      t.text :reason
      t.json :metadata, default: {}
      t.datetime :expires_at
      t.datetime :reminded_at
      t.timestamps

      t.index [:status, :created_at]
      t.index [:approved_by]
    end
  end
end
```

#### 4.2 ActiveRecord Approval Store
**File:** `lib/ruby_llm/agents/workflow/active_record_approval_store.rb`

```ruby
module RubyLLM
  module Agents
    class Workflow
      class ActiveRecordApprovalStore < ApprovalStore
        def save(approval)
          record = ApprovalRecord.find_or_initialize_by(id: approval.id)
          record.update!(approval.to_h)
          approval
        end

        def find(id)
          record = ApprovalRecord.find_by(id: id)
          record&.to_approval
        end

        def pending_for_user(user_id)
          # Query based on approvers configuration
          ApprovalRecord.pending.where("metadata->>'approvers' LIKE ?", "%#{user_id}%")
        end
      end
    end
  end
end
```

### Phase 5: Dashboard UI

#### 5.1 Update Workflow Diagram
Add visual representation for wait steps:
- **Delay**: Hourglass icon with duration
- **Conditional**: Diamond with clock icon
- **Schedule**: Calendar icon with time
- **Approval**: User icon with pending badge

#### 5.2 Approval Dashboard
New route: `/ruby_llm_agents/approvals`
- List pending approvals
- Approve/reject with optional comment
- View approval history
- Filter by workflow, status, user

#### 5.3 Wait Step Visualization
```erb
<!-- Wait step in diagram -->
<div class="flex flex-col items-center">
  <div class="w-16 h-16 flex items-center justify-center rounded-full
              bg-yellow-100 dark:bg-yellow-900/50 border-2 border-dashed
              border-yellow-400 dark:border-yellow-600">
    <svg class="w-8 h-8 text-yellow-600"><!-- hourglass icon --></svg>
  </div>
  <span class="text-xs text-gray-500 mt-1">Wait 5s</span>
</div>
```

---

## File Structure

```
lib/ruby_llm/agents/workflow/
├── dsl/
│   ├── wait_config.rb          # Wait step configuration
│   ├── wait_executor.rb        # Execute wait logic
│   └── schedule_helpers.rb     # Time calculation helpers
├── wait_result.rb              # Wait execution result
├── throttle_manager.rb         # Rate limiting
├── approval.rb                 # Approval model
├── approval_store.rb           # Abstract storage
├── active_record_approval_store.rb  # AR implementation
└── notifiers/
    ├── base.rb                 # Notifier interface
    ├── email.rb                # Email notifications
    ├── slack.rb                # Slack notifications
    └── webhook.rb              # Custom webhooks

app/views/ruby_llm/agents/
├── workflows/
│   └── _wait_step.html.erb     # Wait step diagram component
└── approvals/
    ├── index.html.erb          # Pending approvals list
    └── show.html.erb           # Approval detail/action
```

---

## Testing Plan

### Unit Tests
- `spec/workflow/dsl/wait_config_spec.rb`
- `spec/workflow/dsl/wait_executor_spec.rb`
- `spec/workflow/throttle_manager_spec.rb`
- `spec/workflow/approval_spec.rb`
- `spec/workflow/approval_store_spec.rb`

### Integration Tests
- `spec/workflow/wait_integration_spec.rb` - Full workflow with waits
- `spec/workflow/approval_integration_spec.rb` - Human approval flow

### Example Test Cases
```ruby
RSpec.describe "Wait steps" do
  it "pauses execution for specified duration" do
    workflow = Class.new(RubyLLM::Agents::Workflow) do
      step :start, StartAgent
      wait 100.milliseconds
      step :finish, FinishAgent
    end

    started_at = Time.current
    result = workflow.call(input: "test")
    elapsed = Time.current - started_at

    expect(elapsed).to be >= 0.1
    expect(result.success?).to be true
  end

  it "waits until condition is met" do
    counter = 0

    workflow = Class.new(RubyLLM::Agents::Workflow) do
      step :start, StartAgent
      wait_until -> { counter >= 3 }, poll_interval: 10.milliseconds
      step :finish, FinishAgent
    end

    Thread.new { 3.times { sleep(0.02); counter += 1 } }

    result = workflow.call(input: "test")
    expect(result.success?).to be true
  end
end
```

---

## Migration Path

1. **Phase 1-2**: Core wait functionality (1-2 days)
2. **Phase 3**: Human-in-the-loop (1-2 days)
3. **Phase 4**: ActiveRecord integration (0.5 days)
4. **Phase 5**: Dashboard UI (1 day)

**Total estimated time: 4-6 days**

---

## Configuration

```ruby
RubyLLM::Agents.configure do |config|
  # Wait defaults
  config.default_poll_interval = 1.second
  config.default_wait_timeout = 1.hour

  # Approval settings
  config.approval_store = :active_record  # or :memory, :redis
  config.approval_expiry = 7.days

  # Notifications
  config.slack_webhook_url = ENV['SLACK_WEBHOOK_URL']
  config.approval_notifiers = [:email, :slack]

  # Throttle defaults
  config.default_throttle = nil
  config.global_rate_limit = { calls: 1000, per: 1.minute }
end
```

---

## Open Questions

1. **Persistence during delays**: Should long waits persist workflow state to database?
2. **Distributed throttling**: Use Redis for cross-process rate limiting?
3. **Approval delegation**: Allow approvers to delegate to others?
4. **Approval groups**: Require N of M approvers?
5. **Conditional approvals**: Auto-approve based on rules (amount < $100)?
