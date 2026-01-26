# frozen_string_literal: true

require "rails_helper"

RSpec.describe RubyLLM::Agents::Workflow::DSL::WaitConfig do
  describe "#initialize" do
    it "creates a delay config" do
      config = described_class.new(type: :delay, duration: 5)
      expect(config.type).to eq(:delay)
      expect(config.duration).to eq(5)
    end

    it "creates an until config" do
      condition = -> { true }
      config = described_class.new(type: :until, condition: condition)
      expect(config.type).to eq(:until)
      expect(config.condition).to eq(condition)
    end

    it "creates a schedule config" do
      condition = -> { Time.now + 1.hour }
      config = described_class.new(type: :schedule, condition: condition)
      expect(config.type).to eq(:schedule)
      expect(config.condition).to eq(condition)
    end

    it "creates an approval config" do
      config = described_class.new(type: :approval, name: :manager_approval)
      expect(config.type).to eq(:approval)
      expect(config.name).to eq(:manager_approval)
    end

    it "raises ArgumentError for unknown type" do
      expect {
        described_class.new(type: :unknown)
      }.to raise_error(ArgumentError, /Unknown wait type/)
    end

    it "stores additional options" do
      config = described_class.new(
        type: :delay,
        duration: 5,
        timeout: 30,
        on_timeout: :continue
      )
      expect(config.timeout).to eq(30)
      expect(config.on_timeout).to eq(:continue)
    end
  end

  describe "type predicates" do
    it "#delay? returns true for delay type" do
      config = described_class.new(type: :delay, duration: 5)
      expect(config.delay?).to be true
      expect(config.conditional?).to be false
      expect(config.scheduled?).to be false
      expect(config.approval?).to be false
    end

    it "#conditional? returns true for until type" do
      config = described_class.new(type: :until, condition: -> { true })
      expect(config.conditional?).to be true
      expect(config.delay?).to be false
    end

    it "#scheduled? returns true for schedule type" do
      config = described_class.new(type: :schedule, condition: -> { Time.now })
      expect(config.scheduled?).to be true
    end

    it "#approval? returns true for approval type" do
      config = described_class.new(type: :approval, name: :test)
      expect(config.approval?).to be true
    end
  end

  describe "option accessors" do
    describe "#poll_interval" do
      it "returns configured poll_interval" do
        config = described_class.new(type: :until, condition: -> { true }, poll_interval: 10)
        expect(config.poll_interval).to eq(10)
      end

      it "defaults to 1" do
        config = described_class.new(type: :until, condition: -> { true })
        expect(config.poll_interval).to eq(1)
      end
    end

    describe "#timeout" do
      it "returns configured timeout" do
        config = described_class.new(type: :delay, duration: 5, timeout: 60)
        expect(config.timeout).to eq(60)
      end

      it "returns nil when not configured" do
        config = described_class.new(type: :delay, duration: 5)
        expect(config.timeout).to be_nil
      end
    end

    describe "#on_timeout" do
      it "returns configured on_timeout" do
        config = described_class.new(type: :delay, duration: 5, on_timeout: :continue)
        expect(config.on_timeout).to eq(:continue)
      end

      it "defaults to :fail" do
        config = described_class.new(type: :delay, duration: 5)
        expect(config.on_timeout).to eq(:fail)
      end
    end

    describe "#backoff and #exponential_backoff?" do
      it "returns backoff multiplier when configured" do
        config = described_class.new(type: :until, condition: -> { true }, backoff: 2)
        expect(config.backoff).to eq(2)
        expect(config.exponential_backoff?).to be true
      end

      it "returns nil when not configured" do
        config = described_class.new(type: :until, condition: -> { true })
        expect(config.backoff).to be_nil
        expect(config.exponential_backoff?).to be false
      end
    end

    describe "#max_interval" do
      it "returns configured max_interval" do
        config = described_class.new(type: :until, condition: -> { true }, max_interval: 60)
        expect(config.max_interval).to eq(60)
      end
    end

    describe "#notify_channels" do
      it "returns array of notify channels" do
        config = described_class.new(type: :approval, name: :test, notify: [:email, :slack])
        expect(config.notify_channels).to eq([:email, :slack])
      end

      it "wraps single channel in array" do
        config = described_class.new(type: :approval, name: :test, notify: :email)
        expect(config.notify_channels).to eq([:email])
      end

      it "returns empty array when not configured" do
        config = described_class.new(type: :approval, name: :test)
        expect(config.notify_channels).to eq([])
      end
    end

    describe "#message" do
      it "returns configured message" do
        config = described_class.new(type: :approval, name: :test, message: "Please approve")
        expect(config.message).to eq("Please approve")
      end

      it "returns message proc" do
        message_proc = -> { "Dynamic message" }
        config = described_class.new(type: :approval, name: :test, message: message_proc)
        expect(config.message).to eq(message_proc)
      end
    end

    describe "#approvers" do
      it "returns array of approvers" do
        config = described_class.new(type: :approval, name: :test, approvers: ["user1", "user2"])
        expect(config.approvers).to eq(["user1", "user2"])
      end

      it "wraps single approver in array" do
        config = described_class.new(type: :approval, name: :test, approvers: "user1")
        expect(config.approvers).to eq(["user1"])
      end
    end

    describe "#reminder_after and #reminder_interval" do
      it "returns configured reminder settings" do
        config = described_class.new(
          type: :approval,
          name: :test,
          reminder_after: 3600,
          reminder_interval: 1800
        )
        expect(config.reminder_after).to eq(3600)
        expect(config.reminder_interval).to eq(1800)
      end
    end

    describe "#escalate_to" do
      it "returns configured escalation target" do
        config = described_class.new(type: :approval, name: :test, escalate_to: :supervisor)
        expect(config.escalate_to).to eq(:supervisor)
      end
    end

    describe "#timezone" do
      it "returns configured timezone" do
        config = described_class.new(type: :schedule, condition: -> { Time.now }, timezone: "UTC")
        expect(config.timezone).to eq("UTC")
      end
    end
  end

  describe "#if_condition and #unless_condition" do
    it "returns configured if condition" do
      config = described_class.new(type: :delay, duration: 5, if: :should_wait?)
      expect(config.if_condition).to eq(:should_wait?)
    end

    it "returns configured unless condition" do
      config = described_class.new(type: :delay, duration: 5, unless: :skip_wait?)
      expect(config.unless_condition).to eq(:skip_wait?)
    end
  end

  describe "#should_execute?" do
    let(:workflow) do
      double("workflow").tap do |w|
        allow(w).to receive(:should_wait?).and_return(true)
        allow(w).to receive(:skip_wait?).and_return(false)
      end
    end

    it "returns true when no conditions" do
      config = described_class.new(type: :delay, duration: 5)
      expect(config.should_execute?(workflow)).to be true
    end

    it "evaluates symbol if condition" do
      config = described_class.new(type: :delay, duration: 5, if: :should_wait?)
      expect(config.should_execute?(workflow)).to be true

      allow(workflow).to receive(:should_wait?).and_return(false)
      expect(config.should_execute?(workflow)).to be false
    end

    it "evaluates proc if condition" do
      config = described_class.new(type: :delay, duration: 5, if: -> { true })
      allow(workflow).to receive(:instance_exec).and_return(true)
      expect(config.should_execute?(workflow)).to be true
    end

    it "evaluates unless condition" do
      config = described_class.new(type: :delay, duration: 5, unless: :skip_wait?)
      expect(config.should_execute?(workflow)).to be true

      allow(workflow).to receive(:skip_wait?).and_return(true)
      expect(config.should_execute?(workflow)).to be false
    end

    it "combines if and unless conditions" do
      config = described_class.new(type: :delay, duration: 5, if: :should_wait?, unless: :skip_wait?)
      expect(config.should_execute?(workflow)).to be true

      allow(workflow).to receive(:should_wait?).and_return(false)
      expect(config.should_execute?(workflow)).to be false
    end
  end

  describe "#ui_label" do
    it "returns formatted label for delay" do
      config = described_class.new(type: :delay, duration: 30)
      expect(config.ui_label).to eq("Wait 30s")
    end

    it "returns formatted label for delay in minutes" do
      config = described_class.new(type: :delay, duration: 120)
      expect(config.ui_label).to eq("Wait 2m")
    end

    it "returns formatted label for delay in hours" do
      config = described_class.new(type: :delay, duration: 3600)
      expect(config.ui_label).to eq("Wait 1h")
    end

    it "returns label for until" do
      config = described_class.new(type: :until, condition: -> { true })
      expect(config.ui_label).to eq("Wait until condition")
    end

    it "returns label for schedule" do
      config = described_class.new(type: :schedule, condition: -> { Time.now })
      expect(config.ui_label).to eq("Wait until scheduled time")
    end

    it "returns label for approval with name" do
      config = described_class.new(type: :approval, name: :manager_approval)
      expect(config.ui_label).to eq("Awaiting manager_approval")
    end

    it "returns label for approval without name" do
      config = described_class.new(type: :approval)
      expect(config.ui_label).to eq("Awaiting approval")
    end
  end

  describe "#to_h" do
    it "returns hash representation" do
      config = described_class.new(
        type: :approval,
        name: :manager_approval,
        timeout: 3600,
        notify: [:email, :slack],
        approvers: ["user1"]
      )

      hash = config.to_h

      expect(hash[:type]).to eq(:approval)
      expect(hash[:name]).to eq(:manager_approval)
      expect(hash[:timeout]).to eq(3600)
      expect(hash[:notify]).to eq([:email, :slack])
      expect(hash[:approvers]).to eq(["user1"])
      expect(hash[:ui_label]).to eq("Awaiting manager_approval")
    end

    it "excludes nil values" do
      config = described_class.new(type: :delay, duration: 5)
      hash = config.to_h

      expect(hash).not_to have_key(:backoff)
      expect(hash).not_to have_key(:max_interval)
    end
  end
end
