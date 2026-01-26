# frozen_string_literal: true

require "rails_helper"

RSpec.describe RubyLLM::Agents::Workflow::Notifiers::Base do
  let(:notifier) { described_class.new }

  let(:approval) do
    RubyLLM::Agents::Workflow::Approval.new(
      workflow_id: "order-123",
      workflow_type: "OrderWorkflow",
      name: :manager_approval
    )
  end

  describe "#notify" do
    it "raises NotImplementedError" do
      expect {
        notifier.notify(approval, "Please approve")
      }.to raise_error(NotImplementedError, /must be implemented/)
    end
  end

  describe "#remind" do
    it "calls notify with [Reminder] prefix" do
      custom_notifier = Class.new(described_class) do
        attr_reader :last_message

        def notify(approval, message)
          @last_message = message
          true
        end
      end.new

      custom_notifier.remind(approval, "Please approve")

      expect(custom_notifier.last_message).to eq("[Reminder] Please approve")
    end
  end

  describe "#escalate" do
    it "calls notify with [Escalation] prefix and target" do
      custom_notifier = Class.new(described_class) do
        attr_reader :last_message

        def notify(approval, message)
          @last_message = message
          true
        end
      end.new

      custom_notifier.escalate(approval, "Needs attention", escalate_to: "supervisor")

      expect(custom_notifier.last_message).to eq("[Escalation to supervisor] Needs attention")
    end
  end
end

RSpec.describe RubyLLM::Agents::Workflow::Notifiers::Registry do
  after do
    described_class.reset!
  end

  describe ".register and .get" do
    let(:custom_notifier) do
      Class.new(RubyLLM::Agents::Workflow::Notifiers::Base) do
        def notify(approval, message)
          true
        end
      end.new
    end

    it "registers a notifier" do
      described_class.register(:custom, custom_notifier)

      expect(described_class.get(:custom)).to eq(custom_notifier)
    end

    it "accepts string names" do
      described_class.register("custom", custom_notifier)

      expect(described_class.get(:custom)).to eq(custom_notifier)
    end

    it "returns nil for unregistered notifiers" do
      expect(described_class.get(:unknown)).to be_nil
    end
  end

  describe ".registered?" do
    let(:notifier) do
      Class.new(RubyLLM::Agents::Workflow::Notifiers::Base) do
        def notify(approval, message); true; end
      end.new
    end

    it "returns true for registered notifiers" do
      described_class.register(:test, notifier)
      expect(described_class.registered?(:test)).to be true
    end

    it "returns false for unregistered notifiers" do
      expect(described_class.registered?(:unknown)).to be false
    end
  end

  describe ".notify_all" do
    let(:approval) do
      RubyLLM::Agents::Workflow::Approval.new(
        workflow_id: "order-123",
        workflow_type: "OrderWorkflow",
        name: :approval
      )
    end

    let(:email_notifier) do
      Class.new(RubyLLM::Agents::Workflow::Notifiers::Base) do
        def notify(approval, message)
          true
        end
      end.new
    end

    let(:slack_notifier) do
      Class.new(RubyLLM::Agents::Workflow::Notifiers::Base) do
        def notify(approval, message)
          false
        end
      end.new
    end

    before do
      described_class.register(:email, email_notifier)
      described_class.register(:slack, slack_notifier)
    end

    it "notifies through all specified channels" do
      results = described_class.notify_all(approval, "Please approve", channels: [:email, :slack])

      expect(results[:email]).to be true
      expect(results[:slack]).to be false
    end

    it "returns false for unregistered channels" do
      results = described_class.notify_all(approval, "Please approve", channels: [:email, :sms])

      expect(results[:email]).to be true
      expect(results[:sms]).to be false
    end
  end

  describe ".reset!" do
    it "clears all registered notifiers" do
      notifier = Class.new(RubyLLM::Agents::Workflow::Notifiers::Base) do
        def notify(approval, message); true; end
      end.new

      described_class.register(:test, notifier)
      described_class.reset!

      expect(described_class.registered?(:test)).to be false
    end
  end

  describe ".notifiers" do
    it "returns hash of registered notifiers" do
      expect(described_class.notifiers).to be_a(Hash)
    end
  end
end
