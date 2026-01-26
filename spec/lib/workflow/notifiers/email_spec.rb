# frozen_string_literal: true

require "rails_helper"

RSpec.describe RubyLLM::Agents::Workflow::Notifiers::Email do
  let(:approval) do
    RubyLLM::Agents::Workflow::Approval.new(
      workflow_id: "order-123",
      workflow_type: "OrderApprovalWorkflow",
      name: :manager_approval
    )
  end

  after do
    described_class.reset!
  end

  describe ".configure" do
    it "sets class-level configuration" do
      described_class.configure do |config|
        config.from_address = "approvals@example.com"
        config.subject_prefix = "[URGENT]"
      end

      expect(described_class.from_address).to eq("approvals@example.com")
      expect(described_class.subject_prefix).to eq("[URGENT]")
    end
  end

  describe ".reset!" do
    it "clears configuration" do
      described_class.from_address = "test@example.com"
      described_class.reset!

      expect(described_class.mailer_class).to be_nil
      expect(described_class.from_address).to be_nil
      expect(described_class.subject_prefix).to be_nil
    end
  end

  describe "#initialize" do
    it "uses instance options" do
      notifier = described_class.new(
        from: "custom@example.com",
        subject_prefix: "[Custom]"
      )

      expect(notifier.instance_variable_get(:@from_address)).to eq("custom@example.com")
      expect(notifier.instance_variable_get(:@subject_prefix)).to eq("[Custom]")
    end

    it "falls back to class configuration" do
      described_class.from_address = "class@example.com"

      notifier = described_class.new

      expect(notifier.instance_variable_get(:@from_address)).to eq("class@example.com")
    end

    it "uses defaults when not configured" do
      notifier = described_class.new

      expect(notifier.instance_variable_get(:@from_address)).to eq("noreply@example.com")
      expect(notifier.instance_variable_get(:@subject_prefix)).to eq("[Approval Required]")
    end
  end

  describe "#notify" do
    context "with custom mailer class" do
      let(:mock_mailer) do
        Class.new do
          def self.approval_request(approval, message)
            new
          end

          def deliver_later
            true
          end
        end
      end

      let(:notifier) { described_class.new(mailer_class: mock_mailer) }

      it "sends via custom mailer" do
        expect(mock_mailer).to receive(:approval_request)
          .with(approval, "Please approve")
          .and_call_original

        result = notifier.notify(approval, "Please approve")

        expect(result).to be true
      end

      it "uses deliver_later when available" do
        mail = double("mail")
        allow(mock_mailer).to receive(:approval_request).and_return(mail)
        expect(mail).to receive(:deliver_later)

        notifier.notify(approval, "Please approve")
      end

      it "falls back to deliver_now" do
        mail = double("mail")
        allow(mock_mailer).to receive(:approval_request).and_return(mail)
        allow(mail).to receive(:respond_to?).with(:deliver_later).and_return(false)
        allow(mail).to receive(:respond_to?).with(:deliver_now).and_return(true)
        expect(mail).to receive(:deliver_now)

        notifier.notify(approval, "Please approve")
      end

      it "falls back to deliver" do
        mail = double("mail")
        allow(mock_mailer).to receive(:approval_request).and_return(mail)
        allow(mail).to receive(:respond_to?).with(:deliver_later).and_return(false)
        allow(mail).to receive(:respond_to?).with(:deliver_now).and_return(false)
        allow(mail).to receive(:respond_to?).with(:deliver).and_return(true)
        expect(mail).to receive(:deliver)

        notifier.notify(approval, "Please approve")
      end
    end

    context "without mailer class" do
      let(:notifier) { described_class.new }

      it "returns false when no mailer configured" do
        result = notifier.notify(approval, "Please approve")

        expect(result).to be false
      end
    end

    context "when mailer doesn't respond to approval_request" do
      let(:mock_mailer) { Class.new }
      let(:notifier) { described_class.new(mailer_class: mock_mailer) }

      it "returns false" do
        result = notifier.notify(approval, "Please approve")

        expect(result).to be false
      end
    end

    context "on error" do
      let(:mock_mailer) do
        Class.new do
          def self.approval_request(approval, message)
            raise StandardError, "Mail error"
          end
        end
      end

      let(:notifier) { described_class.new(mailer_class: mock_mailer) }

      it "handles errors gracefully" do
        result = notifier.notify(approval, "Please approve")

        expect(result).to be false
      end
    end
  end
end
