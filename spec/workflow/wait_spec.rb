# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Workflow Wait Steps" do
  # Mock agent for testing
  let(:mock_result) do
    ->(content) do
      RubyLLM::Agents::Result.new(
        content: content,
        input_tokens: 100,
        output_tokens: 50,
        total_cost: 0.001,
        model_id: "gpt-4o"
      )
    end
  end

  let(:simple_agent) do
    result_builder = mock_result
    Class.new(RubyLLM::Agents::Base) do
      model "gpt-4o"

      define_method(:call) do |&_block|
        result_builder.call({ result: "done" })
      end

      def user_prompt
        "test"
      end
    end
  end

  describe RubyLLM::Agents::Workflow::DSL::WaitConfig do
    describe "initialization" do
      it "creates a delay wait config" do
        config = described_class.new(type: :delay, duration: 5)

        expect(config.delay?).to be true
        expect(config.duration).to eq(5)
        expect(config.type).to eq(:delay)
      end

      it "creates an until wait config" do
        condition = -> { true }
        config = described_class.new(type: :until, condition: condition, poll_interval: 2, timeout: 60)

        expect(config.conditional?).to be true
        expect(config.condition).to eq(condition)
        expect(config.poll_interval).to eq(2)
        expect(config.timeout).to eq(60)
      end

      it "creates a schedule wait config" do
        time_proc = -> { Time.now + 3600 }
        config = described_class.new(type: :schedule, condition: time_proc)

        expect(config.scheduled?).to be true
        expect(config.condition).to eq(time_proc)
      end

      it "creates an approval wait config" do
        config = described_class.new(
          type: :approval,
          name: :manager_approval,
          notify: [:email, :slack],
          timeout: 86400,
          approvers: ["user1", "user2"]
        )

        expect(config.approval?).to be true
        expect(config.name).to eq(:manager_approval)
        expect(config.notify_channels).to eq([:email, :slack])
        expect(config.approvers).to eq(["user1", "user2"])
      end

      it "raises error for unknown wait type" do
        expect {
          described_class.new(type: :unknown)
        }.to raise_error(ArgumentError, /Unknown wait type/)
      end
    end

    describe "#ui_label" do
      it "returns formatted label for delay" do
        config = described_class.new(type: :delay, duration: 5)
        expect(config.ui_label).to eq("Wait 5s")
      end

      it "returns formatted label for longer delays" do
        config = described_class.new(type: :delay, duration: 120)
        expect(config.ui_label).to eq("Wait 2m")
      end

      it "returns formatted label for approval" do
        config = described_class.new(type: :approval, name: :review)
        expect(config.ui_label).to eq("Awaiting review")
      end
    end

    describe "#on_timeout" do
      it "defaults to :fail" do
        config = described_class.new(type: :delay, duration: 5)
        expect(config.on_timeout).to eq(:fail)
      end

      it "can be set to :continue" do
        config = described_class.new(type: :until, condition: -> { true }, on_timeout: :continue)
        expect(config.on_timeout).to eq(:continue)
      end

      it "can be set to :skip_next" do
        config = described_class.new(type: :until, condition: -> { true }, on_timeout: :skip_next)
        expect(config.on_timeout).to eq(:skip_next)
      end
    end
  end

  describe RubyLLM::Agents::Workflow::WaitResult do
    describe ".success" do
      it "creates a success result" do
        result = described_class.success(:delay, 5.0)

        expect(result.success?).to be true
        expect(result.type).to eq(:delay)
        expect(result.waited_duration).to eq(5.0)
        expect(result.should_continue?).to be true
      end
    end

    describe ".timeout" do
      it "creates a timeout result with fail action" do
        result = described_class.timeout(:until, 60.0, :fail)

        expect(result.timeout?).to be true
        expect(result.timeout_action).to eq(:fail)
        expect(result.should_continue?).to be false
      end

      it "creates a timeout result with continue action" do
        result = described_class.timeout(:until, 60.0, :continue)

        expect(result.timeout?).to be true
        expect(result.should_continue?).to be true
      end

      it "creates a timeout result with skip_next action" do
        result = described_class.timeout(:until, 60.0, :skip_next)

        expect(result.should_skip_next?).to be true
      end
    end

    describe ".approved" do
      it "creates an approved result" do
        result = described_class.approved("approval-123", "user@example.com", 3600.0)

        expect(result.approved?).to be true
        expect(result.success?).to be true
        expect(result.approval_id).to eq("approval-123")
        expect(result.actor).to eq("user@example.com")
      end
    end

    describe ".rejected" do
      it "creates a rejected result" do
        result = described_class.rejected("approval-123", "user@example.com", 3600.0, reason: "Budget exceeded")

        expect(result.rejected?).to be true
        expect(result.success?).to be false
        expect(result.rejection_reason).to eq("Budget exceeded")
      end
    end

    describe ".skipped" do
      it "creates a skipped result" do
        result = described_class.skipped(:delay, reason: "Condition not met")

        expect(result.skipped?).to be true
        expect(result.should_continue?).to be true
        expect(result.waited_duration).to eq(0)
      end
    end
  end

  describe RubyLLM::Agents::Workflow::ThrottleManager do
    let(:manager) { described_class.new }

    describe "#throttle" do
      it "does not wait on first call" do
        waited = manager.throttle("test", 0.1)
        expect(waited).to eq(0)
      end

      it "waits on subsequent calls within duration" do
        manager.throttle("test", 0.1)
        started_at = Time.now
        manager.throttle("test", 0.1)
        elapsed = Time.now - started_at

        expect(elapsed).to be >= 0.05 # Allow some tolerance
      end

      it "does not wait if duration has passed" do
        manager.throttle("test", 0.01)
        sleep(0.02)

        started_at = Time.now
        manager.throttle("test", 0.01)
        elapsed = Time.now - started_at

        expect(elapsed).to be < 0.01
      end
    end

    describe "#throttle_remaining" do
      it "returns 0 for first call" do
        remaining = manager.throttle_remaining("test", 1.0)
        expect(remaining).to eq(0)
      end

      it "returns remaining time after call" do
        manager.throttle("test", 1.0)
        remaining = manager.throttle_remaining("test", 1.0)

        expect(remaining).to be > 0
        expect(remaining).to be <= 1.0
      end
    end

    describe "#rate_limit" do
      it "allows calls within limit" do
        3.times do
          waited = manager.rate_limit("test", calls: 10, per: 1.0)
          expect(waited).to eq(0)
        end
      end
    end
  end

  describe RubyLLM::Agents::Workflow::Approval do
    describe "#approve!" do
      it "marks approval as approved" do
        approval = described_class.new(
          workflow_id: "wf-123",
          workflow_type: "TestWorkflow",
          name: :review
        )

        approval.approve!("user@example.com")

        expect(approval.approved?).to be true
        expect(approval.approved_by).to eq("user@example.com")
        expect(approval.approved_at).not_to be_nil
      end

      it "raises error if already processed" do
        approval = described_class.new(
          workflow_id: "wf-123",
          workflow_type: "TestWorkflow",
          name: :review
        )
        approval.approve!("user1")

        expect {
          approval.approve!("user2")
        }.to raise_error(RubyLLM::Agents::Workflow::Approval::InvalidStateError)
      end
    end

    describe "#reject!" do
      it "marks approval as rejected" do
        approval = described_class.new(
          workflow_id: "wf-123",
          workflow_type: "TestWorkflow",
          name: :review
        )

        approval.reject!("user@example.com", reason: "Not ready")

        expect(approval.rejected?).to be true
        expect(approval.rejected_by).to eq("user@example.com")
        expect(approval.reason).to eq("Not ready")
      end
    end

    describe "#can_approve?" do
      it "allows anyone when no approvers specified" do
        approval = described_class.new(
          workflow_id: "wf-123",
          workflow_type: "TestWorkflow",
          name: :review
        )

        expect(approval.can_approve?("anyone")).to be true
      end

      it "restricts to specified approvers" do
        approval = described_class.new(
          workflow_id: "wf-123",
          workflow_type: "TestWorkflow",
          name: :review,
          approvers: ["user1", "user2"]
        )

        expect(approval.can_approve?("user1")).to be true
        expect(approval.can_approve?("user3")).to be false
      end
    end

    describe "#timed_out?" do
      it "returns false when no expiry" do
        approval = described_class.new(
          workflow_id: "wf-123",
          workflow_type: "TestWorkflow",
          name: :review
        )

        expect(approval.timed_out?).to be false
      end

      it "returns true when expired" do
        approval = described_class.new(
          workflow_id: "wf-123",
          workflow_type: "TestWorkflow",
          name: :review,
          expires_at: Time.now - 1
        )

        expect(approval.timed_out?).to be true
      end
    end
  end

  describe RubyLLM::Agents::Workflow::ApprovalStore do
    let(:store) { RubyLLM::Agents::Workflow::MemoryApprovalStore.new }

    describe "#save and #find" do
      it "saves and retrieves approvals" do
        approval = RubyLLM::Agents::Workflow::Approval.new(
          workflow_id: "wf-123",
          workflow_type: "TestWorkflow",
          name: :review
        )

        store.save(approval)
        found = store.find(approval.id)

        expect(found).to eq(approval)
      end
    end

    describe "#find_by_workflow" do
      it "returns approvals for a workflow" do
        approval1 = RubyLLM::Agents::Workflow::Approval.new(
          workflow_id: "wf-123",
          workflow_type: "TestWorkflow",
          name: :review1
        )
        approval2 = RubyLLM::Agents::Workflow::Approval.new(
          workflow_id: "wf-123",
          workflow_type: "TestWorkflow",
          name: :review2
        )
        approval3 = RubyLLM::Agents::Workflow::Approval.new(
          workflow_id: "wf-456",
          workflow_type: "TestWorkflow",
          name: :review3
        )

        store.save(approval1)
        store.save(approval2)
        store.save(approval3)

        found = store.find_by_workflow("wf-123")

        expect(found.size).to eq(2)
        expect(found.map(&:name)).to contain_exactly(:review1, :review2)
      end
    end

    describe "#all_pending" do
      it "returns only pending approvals" do
        approval1 = RubyLLM::Agents::Workflow::Approval.new(
          workflow_id: "wf-123",
          workflow_type: "TestWorkflow",
          name: :pending1
        )
        approval2 = RubyLLM::Agents::Workflow::Approval.new(
          workflow_id: "wf-123",
          workflow_type: "TestWorkflow",
          name: :approved1
        )
        approval2.approve!("user")

        store.save(approval1)
        store.save(approval2)

        pending = store.all_pending

        expect(pending.size).to eq(1)
        expect(pending.first.name).to eq(:pending1)
      end
    end
  end

  describe "workflow with wait DSL" do
    describe "wait step" do
      it "adds wait config to step_order" do
        agent = simple_agent

        workflow = Class.new(RubyLLM::Agents::Workflow) do
          step :before, agent
          wait 0.01
          step :after, agent
        end

        step_order = workflow.step_order
        expect(step_order[0]).to eq(:before)
        expect(step_order[1]).to be_a(RubyLLM::Agents::Workflow::DSL::WaitConfig)
        expect(step_order[2]).to eq(:after)
      end

      it "executes delay wait" do
        agent = simple_agent

        workflow = Class.new(RubyLLM::Agents::Workflow) do
          step :before, agent
          wait 0.05
          step :after, agent
        end

        started_at = Time.now
        result = workflow.call
        elapsed = Time.now - started_at

        expect(result.success?).to be true
        expect(elapsed).to be >= 0.04 # Some tolerance
      end

      it "supports conditional wait" do
        agent = simple_agent

        workflow = Class.new(RubyLLM::Agents::Workflow) do
          step :before, agent
          wait 1.0, if: :should_wait?

          def should_wait?
            false
          end
        end

        started_at = Time.now
        result = workflow.call
        elapsed = Time.now - started_at

        expect(result.success?).to be true
        expect(elapsed).to be < 0.5 # Should skip wait
      end
    end

    describe "wait_until step" do
      it "waits until condition is true" do
        agent = simple_agent
        counter = 0

        workflow = Class.new(RubyLLM::Agents::Workflow) do
          step :before, agent
          wait_until(poll_interval: 0.01, timeout: 1) { counter >= 3 }
          step :after, agent
        end

        Thread.new { 5.times { sleep(0.02); counter += 1 } }

        result = workflow.call
        expect(result.success?).to be true
      end

      it "times out if condition never met" do
        agent = simple_agent

        workflow = Class.new(RubyLLM::Agents::Workflow) do
          step :before, agent
          wait_until(poll_interval: 0.01, timeout: 0.05, on_timeout: :fail) { false }
          step :after, agent
        end

        result = workflow.call
        expect(result.error?).to be true
      end

      it "continues on timeout when configured" do
        agent = simple_agent

        workflow = Class.new(RubyLLM::Agents::Workflow) do
          step :before, agent
          wait_until(poll_interval: 0.01, timeout: 0.05, on_timeout: :continue) { false }
          step :after, agent
        end

        result = workflow.call
        expect(result.success?).to be true
      end
    end

    describe "wait_for step" do
      it "adds approval wait config to step_order" do
        agent = simple_agent

        workflow = Class.new(RubyLLM::Agents::Workflow) do
          step :draft, agent
          wait_for :approval, notify: [:email], timeout: 3600
          step :publish, agent
        end

        step_order = workflow.step_order
        wait_config = step_order[1]

        expect(wait_config).to be_a(RubyLLM::Agents::Workflow::DSL::WaitConfig)
        expect(wait_config.approval?).to be true
        expect(wait_config.name).to eq(:approval)
        expect(wait_config.notify_channels).to eq([:email])
      end
    end

    describe "step_metadata with wait steps" do
      it "includes wait steps in metadata" do
        agent = simple_agent

        workflow = Class.new(RubyLLM::Agents::Workflow) do
          step :before, agent
          wait 5
          step :after, agent
        end

        metadata = workflow.step_metadata
        wait_meta = metadata.find { |m| m[:type] == :wait }

        expect(wait_meta).not_to be_nil
        expect(wait_meta[:wait_type]).to eq(:delay)
        expect(wait_meta[:duration]).to eq(5)
      end
    end
  end

  describe "throttle on steps" do
    it "adds throttle config to step" do
      agent = simple_agent

      workflow = Class.new(RubyLLM::Agents::Workflow) do
        step :fetch, agent, throttle: 0.5
      end

      config = workflow.step_configs[:fetch]

      expect(config.throttle).to eq(0.5)
      expect(config.throttled?).to be true
    end

    it "adds rate_limit config to step" do
      agent = simple_agent

      workflow = Class.new(RubyLLM::Agents::Workflow) do
        step :fetch, agent, rate_limit: { calls: 10, per: 60 }
      end

      config = workflow.step_configs[:fetch]

      expect(config.rate_limit).to eq({ calls: 10, per: 60 })
      expect(config.throttled?).to be true
    end
  end

  describe RubyLLM::Agents::Workflow::DSL::ScheduleHelpers do
    let(:helper_class) do
      Class.new do
        include RubyLLM::Agents::Workflow::DSL::ScheduleHelpers
      end
    end

    let(:helper) { helper_class.new }

    describe "#next_hour" do
      it "returns the start of the next hour" do
        result = helper.next_hour
        now = Time.now

        expect(result.hour).to eq((now.hour + 1) % 24)
        expect(result.min).to eq(0)
        expect(result.sec).to eq(0)
      end
    end

    describe "#tomorrow_at" do
      it "returns tomorrow at the specified time" do
        result = helper.tomorrow_at(9, 30)
        tomorrow = Time.now + 86400

        expect(result.day).to eq(tomorrow.day)
        expect(result.hour).to eq(9)
        expect(result.min).to eq(30)
      end
    end

    describe "#from_now" do
      it "returns time offset from now" do
        before = Time.now
        result = helper.from_now(3600)
        after = Time.now

        expect(result).to be >= before + 3600
        expect(result).to be <= after + 3600
      end
    end
  end
end
