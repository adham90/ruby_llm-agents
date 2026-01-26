# frozen_string_literal: true

require "rails_helper"

RSpec.describe RubyLLM::Agents::Workflow::DSL::WaitExecutor do
  let(:workflow) do
    double("workflow").tap do |w|
      allow(w).to receive(:instance_exec) { |&block| block.call if block }
      allow(w).to receive(:input).and_return(OpenStruct.new({}))
      allow(w).to receive(:object_id).and_return(12345)
      allow(w).to receive(:class).and_return(double(name: "TestWorkflow"))
    end
  end

  let(:approval_store) { RubyLLM::Agents::Workflow::MemoryApprovalStore.new }

  before do
    approval_store.clear!
  end

  describe "#execute" do
    context "when condition not met" do
      it "returns skipped result" do
        config = RubyLLM::Agents::Workflow::DSL::WaitConfig.new(
          type: :delay,
          duration: 5,
          if: -> { false }
        )
        allow(workflow).to receive(:instance_exec).and_return(false)

        executor = described_class.new(config, workflow)
        result = executor.execute

        expect(result.status).to eq(:skipped)
        expect(result.metadata[:reason]).to eq("Condition not met")
      end
    end

    context "delay wait" do
      it "sleeps for the specified duration" do
        config = RubyLLM::Agents::Workflow::DSL::WaitConfig.new(
          type: :delay,
          duration: 0.01
        )

        executor = described_class.new(config, workflow)

        start_time = Time.now
        result = executor.execute
        elapsed = Time.now - start_time

        expect(result.status).to eq(:success)
        expect(result.type).to eq(:delay)
        expect(result.waited_duration).to be_within(0.1).of(0.01)
        expect(elapsed).to be >= 0.01
      end
    end

    context "until wait" do
      it "returns success when condition becomes true" do
        call_count = 0
        config = RubyLLM::Agents::Workflow::DSL::WaitConfig.new(
          type: :until,
          condition: -> {
            call_count += 1
            call_count >= 2
          },
          poll_interval: 0.01
        )

        allow(workflow).to receive(:instance_exec) do |&block|
          block.call
        end

        executor = described_class.new(config, workflow)
        result = executor.execute

        expect(result.status).to eq(:success)
        expect(result.type).to eq(:until)
        expect(call_count).to be >= 2
      end

      it "returns timeout when condition never met" do
        config = RubyLLM::Agents::Workflow::DSL::WaitConfig.new(
          type: :until,
          condition: -> { false },
          poll_interval: 0.01,
          timeout: 0.05
        )

        allow(workflow).to receive(:instance_exec).and_return(false)

        executor = described_class.new(config, workflow)
        result = executor.execute

        expect(result.status).to eq(:timeout)
        expect(result.timeout_action).to eq(:fail)
      end

      it "applies exponential backoff when configured" do
        call_count = 0
        config = RubyLLM::Agents::Workflow::DSL::WaitConfig.new(
          type: :until,
          condition: -> {
            call_count += 1
            call_count >= 3
          },
          poll_interval: 0.01,
          backoff: 2,
          max_interval: 0.1
        )

        allow(workflow).to receive(:instance_exec) do |&block|
          block.call
        end

        executor = described_class.new(config, workflow)
        result = executor.execute

        expect(result.status).to eq(:success)
        expect(call_count).to be >= 3
      end
    end

    context "schedule wait" do
      it "waits until scheduled time" do
        target_time = Time.now + 0.02
        config = RubyLLM::Agents::Workflow::DSL::WaitConfig.new(
          type: :schedule,
          condition: -> { target_time }
        )

        allow(workflow).to receive(:instance_exec).and_return(target_time)

        executor = described_class.new(config, workflow)

        start_time = Time.now
        result = executor.execute
        elapsed = Time.now - start_time

        expect(result.status).to eq(:success)
        expect(result.type).to eq(:schedule)
        expect(elapsed).to be >= 0.01
        expect(result.metadata[:target_time]).to eq(target_time)
      end

      it "does not wait if target time is in the past" do
        target_time = Time.now - 1
        config = RubyLLM::Agents::Workflow::DSL::WaitConfig.new(
          type: :schedule,
          condition: -> { target_time }
        )

        allow(workflow).to receive(:instance_exec).and_return(target_time)

        executor = described_class.new(config, workflow)
        result = executor.execute

        expect(result.status).to eq(:success)
        expect(result.waited_duration).to eq(0)
      end

      it "raises error when condition doesn't return Time" do
        config = RubyLLM::Agents::Workflow::DSL::WaitConfig.new(
          type: :schedule,
          condition: -> { "not a time" }
        )

        allow(workflow).to receive(:instance_exec).and_return("not a time")

        executor = described_class.new(config, workflow)

        expect { executor.execute }.to raise_error(ArgumentError, /must return a Time/)
      end
    end

    context "approval wait" do
      it "returns approved when approval is granted" do
        config = RubyLLM::Agents::Workflow::DSL::WaitConfig.new(
          type: :approval,
          name: :manager_approval,
          poll_interval: 0.01
        )

        executor = described_class.new(config, workflow, approval_store: approval_store)

        # Simulate approval in a thread
        Thread.new do
          sleep 0.02
          approvals = approval_store.all_pending
          approvals.first&.approve!("manager@example.com")
          approval_store.save(approvals.first) if approvals.first
        end

        result = executor.execute

        expect(result.status).to eq(:approved)
        expect(result.metadata[:approved_by]).to eq("manager@example.com")
      end

      it "returns rejected when approval is denied" do
        config = RubyLLM::Agents::Workflow::DSL::WaitConfig.new(
          type: :approval,
          name: :manager_approval,
          poll_interval: 0.01
        )

        executor = described_class.new(config, workflow, approval_store: approval_store)

        Thread.new do
          sleep 0.02
          approvals = approval_store.all_pending
          approvals.first&.reject!("manager@example.com", reason: "Not approved")
          approval_store.save(approvals.first) if approvals.first
        end

        result = executor.execute

        expect(result.status).to eq(:rejected)
        expect(result.rejection_reason).to eq("Not approved")
      end

      it "returns timeout when approval expires" do
        config = RubyLLM::Agents::Workflow::DSL::WaitConfig.new(
          type: :approval,
          name: :manager_approval,
          poll_interval: 0.01,
          timeout: 0.03
        )

        executor = described_class.new(config, workflow, approval_store: approval_store)
        result = executor.execute

        expect(result.status).to eq(:timeout)
        expect(result.type).to eq(:approval)
      end
    end

    context "timeout actions" do
      it "returns :continue action when on_timeout is :continue" do
        config = RubyLLM::Agents::Workflow::DSL::WaitConfig.new(
          type: :until,
          condition: -> { false },
          poll_interval: 0.01,
          timeout: 0.02,
          on_timeout: :continue
        )

        allow(workflow).to receive(:instance_exec).and_return(false)

        executor = described_class.new(config, workflow)
        result = executor.execute

        expect(result.timeout?).to be true
        expect(result.timeout_action).to eq(:continue)
        expect(result.should_continue?).to be true
      end

      it "returns :skip_next action when on_timeout is :skip_next" do
        config = RubyLLM::Agents::Workflow::DSL::WaitConfig.new(
          type: :until,
          condition: -> { false },
          poll_interval: 0.01,
          timeout: 0.02,
          on_timeout: :skip_next
        )

        allow(workflow).to receive(:instance_exec).and_return(false)

        executor = described_class.new(config, workflow)
        result = executor.execute

        expect(result.timeout_action).to eq(:skip_next)
        expect(result.should_skip_next?).to be true
      end

      it "handles escalation on timeout" do
        config = RubyLLM::Agents::Workflow::DSL::WaitConfig.new(
          type: :until,
          condition: -> { false },
          poll_interval: 0.01,
          timeout: 0.02,
          on_timeout: :escalate,
          escalate_to: :supervisor
        )

        allow(workflow).to receive(:instance_exec).and_return(false)

        executor = described_class.new(config, workflow)
        result = executor.execute

        expect(result.timeout_action).to eq(:escalate)
        expect(result.metadata[:escalated_to]).to eq(:supervisor)
      end
    end
  end

  describe "condition evaluation" do
    it "evaluates symbol conditions" do
      config = RubyLLM::Agents::Workflow::DSL::WaitConfig.new(
        type: :until,
        condition: :check_condition,
        poll_interval: 0.01
      )

      call_count = 0
      allow(workflow).to receive(:check_condition) do
        call_count += 1
        call_count >= 2
      end

      executor = described_class.new(config, workflow)
      result = executor.execute

      expect(result.status).to eq(:success)
    end
  end
end
