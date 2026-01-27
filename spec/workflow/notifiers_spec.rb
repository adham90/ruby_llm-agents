# frozen_string_literal: true

require "rails_helper"

RSpec.describe RubyLLM::Agents::Workflow::Notifiers do
  let(:approval) do
    RubyLLM::Agents::Workflow::Approval.new(
      workflow_id: "order-123",
      workflow_type: "OrderWorkflow",
      name: :manager_approval
    )
  end

  let(:custom_notifier) do
    Class.new(RubyLLM::Agents::Workflow::Notifiers::Base) do
      attr_reader :last_approval, :last_message

      def notify(approval, message)
        @last_approval = approval
        @last_message = message
        true
      end
    end.new
  end

  after do
    described_class.reset!
  end

  describe ".setup" do
    it "yields the Registry for configuration" do
      yielded = nil

      described_class.setup do |config|
        yielded = config
      end

      expect(yielded).to eq(RubyLLM::Agents::Workflow::Notifiers::Registry)
    end

    it "allows registering notifiers through setup block" do
      described_class.setup do |config|
        config.register(:custom, custom_notifier)
      end

      expect(described_class[:custom]).to eq(custom_notifier)
    end
  end

  describe ".register" do
    it "registers a notifier" do
      described_class.register(:custom, custom_notifier)

      expect(described_class[:custom]).to eq(custom_notifier)
    end

    it "accepts symbol name" do
      described_class.register(:test, custom_notifier)

      expect(described_class[:test]).to eq(custom_notifier)
    end

    it "accepts string name" do
      described_class.register("test", custom_notifier)

      expect(described_class[:test]).to eq(custom_notifier)
    end
  end

  describe ".[]" do
    it "returns registered notifier" do
      described_class.register(:custom, custom_notifier)

      expect(described_class[:custom]).to eq(custom_notifier)
    end

    it "returns nil for unregistered notifier" do
      expect(described_class[:unknown]).to be_nil
    end
  end

  describe ".notify" do
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

    it "sends notifications through specified channels" do
      results = described_class.notify(approval, "Please approve", channels: [:email, :slack])

      expect(results[:email]).to be true
      expect(results[:slack]).to be false
    end

    it "returns false for unregistered channels" do
      results = described_class.notify(approval, "Please approve", channels: [:email, :sms])

      expect(results[:email]).to be true
      expect(results[:sms]).to be false
    end

    it "passes approval and message to notifiers" do
      described_class.register(:custom, custom_notifier)

      described_class.notify(approval, "Test message", channels: [:custom])

      expect(custom_notifier.last_approval).to eq(approval)
      expect(custom_notifier.last_message).to eq("Test message")
    end
  end

  describe ".reset!" do
    it "clears all registered notifiers from Registry" do
      described_class.register(:custom, custom_notifier)
      expect(described_class[:custom]).to eq(custom_notifier)

      described_class.reset!

      expect(described_class[:custom]).to be_nil
    end

    it "resets Email notifier configuration" do
      # Configure Email
      RubyLLM::Agents::Workflow::Notifiers::Email.configure do |config|
        config.from_address = "test@example.com"
      end

      described_class.reset!

      # Email configuration should be reset
      expect(RubyLLM::Agents::Workflow::Notifiers::Email.from_address).to be_nil
    end

    it "resets Slack notifier configuration" do
      # Configure Slack
      RubyLLM::Agents::Workflow::Notifiers::Slack.configure do |config|
        config.default_channel = "#test"
      end

      described_class.reset!

      # Slack configuration should be reset
      expect(RubyLLM::Agents::Workflow::Notifiers::Slack.default_channel).to be_nil
    end

    it "resets Webhook notifier configuration" do
      # Configure Webhook
      RubyLLM::Agents::Workflow::Notifiers::Webhook.configure do |config|
        config.default_headers = { "X-Test" => "value" }
      end

      described_class.reset!

      # Webhook configuration should be reset (default_headers is set to nil)
      expect(RubyLLM::Agents::Workflow::Notifiers::Webhook.default_headers).to be_nil
    end
  end

  describe "integration with individual notifiers" do
    it "works with Email notifier" do
      email = RubyLLM::Agents::Workflow::Notifiers::Email.new
      described_class.register(:email, email)

      expect(described_class[:email]).to eq(email)
    end

    it "works with Slack notifier" do
      slack = RubyLLM::Agents::Workflow::Notifiers::Slack.new(webhook_url: "https://hooks.slack.com/test")
      described_class.register(:slack, slack)

      expect(described_class[:slack]).to eq(slack)
    end

    it "works with Webhook notifier" do
      webhook = RubyLLM::Agents::Workflow::Notifiers::Webhook.new(url: "https://example.com/webhook")
      described_class.register(:webhook, webhook)

      expect(described_class[:webhook]).to eq(webhook)
    end
  end
end
