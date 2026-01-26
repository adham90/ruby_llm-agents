# frozen_string_literal: true

require "rails_helper"

RSpec.describe RubyLLM::Agents::Workflow::WaitResult do
  describe "#initialize" do
    it "creates a wait result with required attributes" do
      result = described_class.new(
        type: :delay,
        status: :success,
        waited_duration: 5.0
      )

      expect(result.type).to eq(:delay)
      expect(result.status).to eq(:success)
      expect(result.waited_duration).to eq(5.0)
      expect(result.metadata).to eq({})
    end

    it "accepts metadata" do
      result = described_class.new(
        type: :approval,
        status: :approved,
        waited_duration: 60.0,
        metadata: { approval_id: "abc123" }
      )

      expect(result.metadata[:approval_id]).to eq("abc123")
    end
  end

  describe ".success" do
    it "creates a success result" do
      result = described_class.success(:delay, 5.0)

      expect(result.type).to eq(:delay)
      expect(result.status).to eq(:success)
      expect(result.waited_duration).to eq(5.0)
      expect(result.success?).to be true
    end

    it "accepts additional metadata" do
      result = described_class.success(:schedule, 10.0, target_time: Time.now)

      expect(result.metadata[:target_time]).to be_present
    end
  end

  describe ".timeout" do
    it "creates a timeout result with action" do
      result = described_class.timeout(:until, 60.0, :fail)

      expect(result.type).to eq(:until)
      expect(result.status).to eq(:timeout)
      expect(result.waited_duration).to eq(60.0)
      expect(result.timeout?).to be true
      expect(result.timeout_action).to eq(:fail)
    end

    it "accepts additional metadata" do
      result = described_class.timeout(:approval, 3600.0, :escalate, escalated_to: :supervisor)

      expect(result.metadata[:escalated_to]).to eq(:supervisor)
      expect(result.metadata[:action_taken]).to eq(:escalate)
    end
  end

  describe ".skipped" do
    it "creates a skipped result" do
      result = described_class.skipped(:delay, reason: "Condition not met")

      expect(result.type).to eq(:delay)
      expect(result.status).to eq(:skipped)
      expect(result.waited_duration).to eq(0)
      expect(result.skipped?).to be true
      expect(result.metadata[:reason]).to eq("Condition not met")
    end

    it "handles missing reason" do
      result = described_class.skipped(:delay)

      expect(result.metadata).to eq({})
    end
  end

  describe ".approved" do
    it "creates an approved result" do
      result = described_class.approved("approval-123", "user@example.com", 1800.0)

      expect(result.type).to eq(:approval)
      expect(result.status).to eq(:approved)
      expect(result.waited_duration).to eq(1800.0)
      expect(result.approved?).to be true
      expect(result.approval_id).to eq("approval-123")
      expect(result.actor).to eq("user@example.com")
    end

    it "accepts additional metadata" do
      result = described_class.approved(
        "approval-123",
        "user@example.com",
        1800.0,
        comment: "Looks good"
      )

      expect(result.metadata[:comment]).to eq("Looks good")
    end
  end

  describe ".rejected" do
    it "creates a rejected result" do
      result = described_class.rejected(
        "approval-123",
        "manager@example.com",
        900.0,
        reason: "Budget exceeded"
      )

      expect(result.type).to eq(:approval)
      expect(result.status).to eq(:rejected)
      expect(result.rejected?).to be true
      expect(result.actor).to eq("manager@example.com")
      expect(result.rejection_reason).to eq("Budget exceeded")
    end
  end

  describe "status predicates" do
    it "#success? returns true for success or approved" do
      expect(described_class.success(:delay, 5.0).success?).to be true
      expect(described_class.approved("id", "user", 60.0).success?).to be true
      expect(described_class.timeout(:until, 60.0, :fail).success?).to be false
    end

    it "#timeout? returns true for timeout status" do
      expect(described_class.timeout(:until, 60.0, :fail).timeout?).to be true
      expect(described_class.success(:delay, 5.0).timeout?).to be false
    end

    it "#skipped? returns true for skipped status" do
      expect(described_class.skipped(:delay).skipped?).to be true
      expect(described_class.success(:delay, 5.0).skipped?).to be false
    end

    it "#approved? returns true for approved status" do
      expect(described_class.approved("id", "user", 60.0).approved?).to be true
      expect(described_class.success(:delay, 5.0).approved?).to be false
    end

    it "#rejected? returns true for rejected status" do
      expect(described_class.rejected("id", "user", 60.0).rejected?).to be true
      expect(described_class.approved("id", "user", 60.0).rejected?).to be false
    end
  end

  describe "#should_continue?" do
    it "returns true for success" do
      expect(described_class.success(:delay, 5.0).should_continue?).to be true
    end

    it "returns true for approved" do
      expect(described_class.approved("id", "user", 60.0).should_continue?).to be true
    end

    it "returns true for skipped" do
      expect(described_class.skipped(:delay).should_continue?).to be true
    end

    it "returns true for timeout with :continue action" do
      expect(described_class.timeout(:until, 60.0, :continue).should_continue?).to be true
    end

    it "returns false for timeout with :fail action" do
      expect(described_class.timeout(:until, 60.0, :fail).should_continue?).to be false
    end

    it "returns false for rejected" do
      expect(described_class.rejected("id", "user", 60.0).should_continue?).to be false
    end
  end

  describe "#should_skip_next?" do
    it "returns true for timeout with :skip_next action" do
      expect(described_class.timeout(:until, 60.0, :skip_next).should_skip_next?).to be true
    end

    it "returns false for timeout with other actions" do
      expect(described_class.timeout(:until, 60.0, :fail).should_skip_next?).to be false
      expect(described_class.timeout(:until, 60.0, :continue).should_skip_next?).to be false
    end

    it "returns false for non-timeout results" do
      expect(described_class.success(:delay, 5.0).should_skip_next?).to be false
    end
  end

  describe "#timeout_action" do
    it "returns the action taken on timeout" do
      result = described_class.timeout(:until, 60.0, :escalate)
      expect(result.timeout_action).to eq(:escalate)
    end

    it "returns nil for non-timeout results" do
      result = described_class.success(:delay, 5.0)
      expect(result.timeout_action).to be_nil
    end
  end

  describe "#approval_id" do
    it "returns the approval ID" do
      result = described_class.approved("approval-123", "user", 60.0)
      expect(result.approval_id).to eq("approval-123")
    end

    it "returns nil for non-approval results" do
      result = described_class.success(:delay, 5.0)
      expect(result.approval_id).to be_nil
    end
  end

  describe "#actor" do
    it "returns approved_by for approved results" do
      result = described_class.approved("id", "approver@example.com", 60.0)
      expect(result.actor).to eq("approver@example.com")
    end

    it "returns rejected_by for rejected results" do
      result = described_class.rejected("id", "manager@example.com", 60.0)
      expect(result.actor).to eq("manager@example.com")
    end

    it "returns nil for non-approval results" do
      result = described_class.success(:delay, 5.0)
      expect(result.actor).to be_nil
    end
  end

  describe "#rejection_reason" do
    it "returns the rejection reason" do
      result = described_class.rejected("id", "user", 60.0, reason: "Not approved")
      expect(result.rejection_reason).to eq("Not approved")
    end

    it "returns nil when no reason" do
      result = described_class.rejected("id", "user", 60.0)
      expect(result.rejection_reason).to be_nil
    end
  end

  describe "#to_h" do
    it "returns hash representation" do
      result = described_class.approved("approval-123", "user@example.com", 1800.0)

      hash = result.to_h

      expect(hash[:type]).to eq(:approval)
      expect(hash[:status]).to eq(:approved)
      expect(hash[:waited_duration]).to eq(1800.0)
      expect(hash[:metadata][:approval_id]).to eq("approval-123")
      expect(hash[:metadata][:approved_by]).to eq("user@example.com")
    end
  end
end
