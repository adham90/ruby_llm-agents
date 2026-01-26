# frozen_string_literal: true

require "rails_helper"

RSpec.describe RubyLLM::Agents::Workflow::ApprovalStore do
  describe ".store" do
    after do
      described_class.reset!
    end

    it "returns the default MemoryApprovalStore" do
      expect(described_class.store).to be_a(RubyLLM::Agents::Workflow::MemoryApprovalStore)
    end

    it "memoizes the store" do
      store1 = described_class.store
      store2 = described_class.store
      expect(store1).to equal(store2)
    end
  end

  describe ".store=" do
    after do
      described_class.reset!
    end

    it "sets a custom store" do
      custom_store = RubyLLM::Agents::Workflow::MemoryApprovalStore.new
      described_class.store = custom_store
      expect(described_class.store).to equal(custom_store)
    end
  end

  describe ".reset!" do
    it "resets to default store" do
      custom_store = RubyLLM::Agents::Workflow::MemoryApprovalStore.new
      described_class.store = custom_store

      described_class.reset!

      expect(described_class.store).not_to equal(custom_store)
      expect(described_class.store).to be_a(RubyLLM::Agents::Workflow::MemoryApprovalStore)
    end
  end

  describe "abstract methods" do
    let(:abstract_store) { described_class.new }

    it "#save raises NotImplementedError" do
      approval = double("approval")
      expect { abstract_store.save(approval) }.to raise_error(NotImplementedError)
    end

    it "#find raises NotImplementedError" do
      expect { abstract_store.find("id") }.to raise_error(NotImplementedError)
    end

    it "#find_by_workflow raises NotImplementedError" do
      expect { abstract_store.find_by_workflow("workflow_id") }.to raise_error(NotImplementedError)
    end

    it "#pending_for_user raises NotImplementedError" do
      expect { abstract_store.pending_for_user("user_id") }.to raise_error(NotImplementedError)
    end

    it "#all_pending raises NotImplementedError" do
      expect { abstract_store.all_pending }.to raise_error(NotImplementedError)
    end

    it "#delete raises NotImplementedError" do
      expect { abstract_store.delete("id") }.to raise_error(NotImplementedError)
    end

    it "#clear! raises NotImplementedError" do
      expect { abstract_store.clear! }.to raise_error(NotImplementedError)
    end
  end
end

RSpec.describe RubyLLM::Agents::Workflow::MemoryApprovalStore do
  let(:store) { described_class.new }

  let(:approval) do
    RubyLLM::Agents::Workflow::Approval.new(
      workflow_id: "order-123",
      workflow_type: "OrderWorkflow",
      name: :manager_approval,
      approvers: ["manager@example.com"]
    )
  end

  before do
    store.clear!
  end

  describe "#save" do
    it "saves an approval" do
      result = store.save(approval)

      expect(result).to eq(approval)
      expect(store.count).to eq(1)
    end

    it "updates an existing approval" do
      store.save(approval)
      approval.approve!("manager@example.com")
      store.save(approval)

      expect(store.count).to eq(1)
      expect(store.find(approval.id).approved?).to be true
    end
  end

  describe "#find" do
    it "returns the approval by id" do
      store.save(approval)

      found = store.find(approval.id)

      expect(found).to eq(approval)
    end

    it "returns nil when not found" do
      expect(store.find("nonexistent")).to be_nil
    end
  end

  describe "#find_by_workflow" do
    it "returns approvals for a workflow" do
      approval2 = RubyLLM::Agents::Workflow::Approval.new(
        workflow_id: "order-123",
        workflow_type: "OrderWorkflow",
        name: :cfo_approval
      )
      approval3 = RubyLLM::Agents::Workflow::Approval.new(
        workflow_id: "order-456",
        workflow_type: "OrderWorkflow",
        name: :manager_approval
      )

      store.save(approval)
      store.save(approval2)
      store.save(approval3)

      found = store.find_by_workflow("order-123")

      expect(found.size).to eq(2)
      expect(found).to include(approval, approval2)
      expect(found).not_to include(approval3)
    end

    it "returns empty array when no approvals found" do
      expect(store.find_by_workflow("nonexistent")).to eq([])
    end
  end

  describe "#pending_for_user" do
    it "returns pending approvals where user can approve" do
      approval2 = RubyLLM::Agents::Workflow::Approval.new(
        workflow_id: "order-456",
        workflow_type: "OrderWorkflow",
        name: :approval,
        approvers: ["admin@example.com"]
      )
      approval3 = RubyLLM::Agents::Workflow::Approval.new(
        workflow_id: "order-789",
        workflow_type: "OrderWorkflow",
        name: :approval
      ) # No approvers = anyone can approve

      store.save(approval)
      store.save(approval2)
      store.save(approval3)

      found = store.pending_for_user("manager@example.com")

      expect(found.size).to eq(2)
      expect(found).to include(approval, approval3)
      expect(found).not_to include(approval2)
    end

    it "excludes non-pending approvals" do
      approval.approve!("manager@example.com")
      store.save(approval)

      found = store.pending_for_user("manager@example.com")

      expect(found).to be_empty
    end
  end

  describe "#all_pending" do
    it "returns all pending approvals" do
      approval2 = RubyLLM::Agents::Workflow::Approval.new(
        workflow_id: "order-456",
        workflow_type: "OrderWorkflow",
        name: :approval
      )
      approval2.approve!("user")

      store.save(approval)
      store.save(approval2)

      pending = store.all_pending

      expect(pending.size).to eq(1)
      expect(pending).to include(approval)
      expect(pending).not_to include(approval2)
    end
  end

  describe "#delete" do
    it "deletes an approval and returns true" do
      store.save(approval)

      result = store.delete(approval.id)

      expect(result).to be true
      expect(store.find(approval.id)).to be_nil
      expect(store.count).to eq(0)
    end

    it "returns false when approval not found" do
      result = store.delete("nonexistent")
      expect(result).to be false
    end
  end

  describe "#clear!" do
    it "removes all approvals" do
      store.save(approval)
      store.save(
        RubyLLM::Agents::Workflow::Approval.new(
          workflow_id: "order-456",
          workflow_type: "OrderWorkflow",
          name: :approval
        )
      )

      store.clear!

      expect(store.count).to eq(0)
    end
  end

  describe "#count" do
    it "returns the number of stored approvals" do
      expect(store.count).to eq(0)

      store.save(approval)
      expect(store.count).to eq(1)

      store.save(
        RubyLLM::Agents::Workflow::Approval.new(
          workflow_id: "order-456",
          workflow_type: "OrderWorkflow",
          name: :approval
        )
      )
      expect(store.count).to eq(2)
    end
  end

  describe "thread safety" do
    it "handles concurrent saves" do
      threads = 10.times.map do |i|
        Thread.new do
          store.save(
            RubyLLM::Agents::Workflow::Approval.new(
              workflow_id: "order-#{i}",
              workflow_type: "OrderWorkflow",
              name: :approval
            )
          )
        end
      end

      threads.each(&:join)

      expect(store.count).to eq(10)
    end

    it "handles concurrent reads and writes" do
      store.save(approval)

      threads = []

      5.times do
        threads << Thread.new { store.find(approval.id) }
        threads << Thread.new { store.all_pending }
      end

      threads.each(&:join)

      expect(store.count).to eq(1)
    end
  end
end
