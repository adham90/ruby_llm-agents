# frozen_string_literal: true

require "rails_helper"

RSpec.describe RubyLLM::Agents::Workflow::Approval do
  describe "#initialize" do
    it "creates an approval with required attributes" do
      approval = described_class.new(
        workflow_id: "order-123",
        workflow_type: "OrderApprovalWorkflow",
        name: :manager_approval
      )

      expect(approval.workflow_id).to eq("order-123")
      expect(approval.workflow_type).to eq("OrderApprovalWorkflow")
      expect(approval.name).to eq(:manager_approval)
      expect(approval.status).to eq(:pending)
      expect(approval.id).to be_present
      expect(approval.created_at).to be_present
    end

    it "accepts optional attributes" do
      expires_at = Time.now + 1.hour
      approval = described_class.new(
        workflow_id: "order-123",
        workflow_type: "OrderWorkflow",
        name: :approval,
        approvers: ["user1", "user2"],
        expires_at: expires_at,
        metadata: { order_total: 5000 }
      )

      expect(approval.approvers).to eq(["user1", "user2"])
      expect(approval.expires_at).to eq(expires_at)
      expect(approval.metadata[:order_total]).to eq(5000)
    end

    it "generates a unique id" do
      approval1 = described_class.new(
        workflow_id: "order-1",
        workflow_type: "OrderWorkflow",
        name: :approval
      )
      approval2 = described_class.new(
        workflow_id: "order-2",
        workflow_type: "OrderWorkflow",
        name: :approval
      )

      expect(approval1.id).not_to eq(approval2.id)
    end
  end

  describe "#approve!" do
    let(:approval) do
      described_class.new(
        workflow_id: "order-123",
        workflow_type: "OrderWorkflow",
        name: :manager_approval
      )
    end

    it "transitions to approved status" do
      approval.approve!("manager@example.com")

      expect(approval.status).to eq(:approved)
      expect(approval.approved_by).to eq("manager@example.com")
      expect(approval.approved_at).to be_present
    end

    it "accepts optional comment" do
      approval.approve!("manager@example.com", comment: "Looks good")

      expect(approval.metadata[:approval_comment]).to eq("Looks good")
    end

    it "raises error if not pending" do
      approval.approve!("manager@example.com")

      expect {
        approval.approve!("another@example.com")
      }.to raise_error(described_class::InvalidStateError, /Cannot approve/)
    end
  end

  describe "#reject!" do
    let(:approval) do
      described_class.new(
        workflow_id: "order-123",
        workflow_type: "OrderWorkflow",
        name: :manager_approval
      )
    end

    it "transitions to rejected status" do
      approval.reject!("manager@example.com", reason: "Budget exceeded")

      expect(approval.status).to eq(:rejected)
      expect(approval.rejected_by).to eq("manager@example.com")
      expect(approval.rejected_at).to be_present
      expect(approval.reason).to eq("Budget exceeded")
    end

    it "accepts rejection without reason" do
      approval.reject!("manager@example.com")

      expect(approval.status).to eq(:rejected)
      expect(approval.reason).to be_nil
    end

    it "raises error if not pending" do
      approval.reject!("manager@example.com")

      expect {
        approval.reject!("another@example.com")
      }.to raise_error(described_class::InvalidStateError, /Cannot reject/)
    end
  end

  describe "#expire!" do
    let(:approval) do
      described_class.new(
        workflow_id: "order-123",
        workflow_type: "OrderWorkflow",
        name: :manager_approval
      )
    end

    it "transitions to expired status" do
      approval.expire!

      expect(approval.status).to eq(:expired)
      expect(approval.expired?).to be true
    end

    it "raises error if not pending" do
      approval.approve!("manager@example.com")

      expect {
        approval.expire!
      }.to raise_error(described_class::InvalidStateError, /Cannot expire/)
    end
  end

  describe "status predicates" do
    let(:approval) do
      described_class.new(
        workflow_id: "order-123",
        workflow_type: "OrderWorkflow",
        name: :approval
      )
    end

    it "#pending? returns true for pending status" do
      expect(approval.pending?).to be true
      expect(approval.approved?).to be false
      expect(approval.rejected?).to be false
      expect(approval.expired?).to be false
    end

    it "#approved? returns true after approval" do
      approval.approve!("user")
      expect(approval.approved?).to be true
      expect(approval.pending?).to be false
    end

    it "#rejected? returns true after rejection" do
      approval.reject!("user")
      expect(approval.rejected?).to be true
      expect(approval.pending?).to be false
    end

    it "#expired? returns true after expiration" do
      approval.expire!
      expect(approval.expired?).to be true
      expect(approval.pending?).to be false
    end
  end

  describe "#timed_out?" do
    it "returns false when no expires_at" do
      approval = described_class.new(
        workflow_id: "order-123",
        workflow_type: "OrderWorkflow",
        name: :approval
      )

      expect(approval.timed_out?).to be false
    end

    it "returns false when not yet expired" do
      approval = described_class.new(
        workflow_id: "order-123",
        workflow_type: "OrderWorkflow",
        name: :approval,
        expires_at: Time.now + 1.hour
      )

      expect(approval.timed_out?).to be false
    end

    it "returns true when past expires_at and still pending" do
      approval = described_class.new(
        workflow_id: "order-123",
        workflow_type: "OrderWorkflow",
        name: :approval,
        expires_at: Time.now - 1.hour
      )

      expect(approval.timed_out?).to be true
    end

    it "returns false when approved even if past expires_at" do
      approval = described_class.new(
        workflow_id: "order-123",
        workflow_type: "OrderWorkflow",
        name: :approval,
        expires_at: Time.now - 1.hour
      )
      # Force status change without validation
      approval.instance_variable_set(:@status, :approved)

      expect(approval.timed_out?).to be false
    end
  end

  describe "#can_approve?" do
    it "returns true when no approvers specified" do
      approval = described_class.new(
        workflow_id: "order-123",
        workflow_type: "OrderWorkflow",
        name: :approval
      )

      expect(approval.can_approve?("anyone@example.com")).to be true
    end

    it "returns true when user is in approvers list" do
      approval = described_class.new(
        workflow_id: "order-123",
        workflow_type: "OrderWorkflow",
        name: :approval,
        approvers: ["manager@example.com", "admin@example.com"]
      )

      expect(approval.can_approve?("manager@example.com")).to be true
    end

    it "returns false when user is not in approvers list" do
      approval = described_class.new(
        workflow_id: "order-123",
        workflow_type: "OrderWorkflow",
        name: :approval,
        approvers: ["manager@example.com"]
      )

      expect(approval.can_approve?("other@example.com")).to be false
    end
  end

  describe "#age" do
    it "returns seconds since creation" do
      approval = described_class.new(
        workflow_id: "order-123",
        workflow_type: "OrderWorkflow",
        name: :approval
      )

      # Allow for a small time difference
      expect(approval.age).to be >= 0
      expect(approval.age).to be < 1
    end
  end

  describe "#time_until_expiry" do
    it "returns nil when no expires_at" do
      approval = described_class.new(
        workflow_id: "order-123",
        workflow_type: "OrderWorkflow",
        name: :approval
      )

      expect(approval.time_until_expiry).to be_nil
    end

    it "returns seconds until expiry" do
      approval = described_class.new(
        workflow_id: "order-123",
        workflow_type: "OrderWorkflow",
        name: :approval,
        expires_at: Time.now + 3600
      )

      expect(approval.time_until_expiry).to be_within(5).of(3600)
    end
  end

  describe "#mark_reminded! and #should_remind?" do
    let(:approval) do
      described_class.new(
        workflow_id: "order-123",
        workflow_type: "OrderWorkflow",
        name: :approval
      )
    end

    it "#mark_reminded! sets reminded_at" do
      expect(approval.reminded_at).to be_nil
      approval.mark_reminded!
      expect(approval.reminded_at).to be_present
    end

    context "#should_remind?" do
      it "returns false when not pending" do
        approval.approve!("user")
        expect(approval.should_remind?(0)).to be false
      end

      it "returns false when age is less than reminder_after" do
        expect(approval.should_remind?(3600)).to be false
      end

      it "returns true when age exceeds reminder_after and not reminded" do
        # Simulate old creation time
        approval.instance_variable_set(:@created_at, Time.now - 3700)
        expect(approval.should_remind?(3600)).to be true
      end

      it "returns false after first reminder without interval" do
        approval.instance_variable_set(:@created_at, Time.now - 3700)
        approval.mark_reminded!
        expect(approval.should_remind?(3600)).to be false
      end

      it "returns true when reminder_interval has passed" do
        approval.instance_variable_set(:@created_at, Time.now - 7200)
        approval.instance_variable_set(:@reminded_at, Time.now - 3700)
        expect(approval.should_remind?(3600, reminder_interval: 3600)).to be true
      end
    end
  end

  describe "#to_h" do
    it "returns hash representation" do
      expires_at = Time.now + 1.hour
      approval = described_class.new(
        workflow_id: "order-123",
        workflow_type: "OrderApprovalWorkflow",
        name: :manager_approval,
        approvers: ["manager@example.com"],
        expires_at: expires_at,
        metadata: { order_total: 5000 }
      )

      hash = approval.to_h

      expect(hash[:id]).to eq(approval.id)
      expect(hash[:workflow_id]).to eq("order-123")
      expect(hash[:workflow_type]).to eq("OrderApprovalWorkflow")
      expect(hash[:name]).to eq(:manager_approval)
      expect(hash[:status]).to eq(:pending)
      expect(hash[:approvers]).to eq(["manager@example.com"])
      expect(hash[:expires_at]).to eq(expires_at)
      expect(hash[:metadata][:order_total]).to eq(5000)
      expect(hash[:created_at]).to be_present
    end

    it "excludes nil values" do
      approval = described_class.new(
        workflow_id: "order-123",
        workflow_type: "OrderWorkflow",
        name: :approval
      )

      hash = approval.to_h

      expect(hash).not_to have_key(:approved_by)
      expect(hash).not_to have_key(:approved_at)
      expect(hash).not_to have_key(:rejected_by)
      expect(hash).not_to have_key(:rejected_at)
      expect(hash).not_to have_key(:reason)
    end
  end
end
