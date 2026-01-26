# frozen_string_literal: true

require "rails_helper"

RSpec.describe RubyLLM::Agents::Workflow::Notifiers::Slack do
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
        config.webhook_url = "https://hooks.slack.com/services/xxx"
        config.api_token = "xoxb-token"
        config.default_channel = "#approvals"
      end

      expect(described_class.webhook_url).to eq("https://hooks.slack.com/services/xxx")
      expect(described_class.api_token).to eq("xoxb-token")
      expect(described_class.default_channel).to eq("#approvals")
    end
  end

  describe ".reset!" do
    it "clears configuration" do
      described_class.webhook_url = "https://hooks.slack.com/services/xxx"
      described_class.reset!

      expect(described_class.webhook_url).to be_nil
      expect(described_class.api_token).to be_nil
      expect(described_class.default_channel).to be_nil
    end
  end

  describe "#initialize" do
    it "uses instance options" do
      notifier = described_class.new(
        webhook_url: "https://instance-webhook.com",
        api_token: "instance-token",
        channel: "#custom"
      )

      expect(notifier.instance_variable_get(:@webhook_url)).to eq("https://instance-webhook.com")
      expect(notifier.instance_variable_get(:@api_token)).to eq("instance-token")
      expect(notifier.instance_variable_get(:@channel)).to eq("#custom")
    end

    it "falls back to class configuration" do
      described_class.webhook_url = "https://class-webhook.com"
      described_class.default_channel = "#class-channel"

      notifier = described_class.new

      expect(notifier.instance_variable_get(:@webhook_url)).to eq("https://class-webhook.com")
      expect(notifier.instance_variable_get(:@channel)).to eq("#class-channel")
    end
  end

  describe "#notify" do
    context "with webhook" do
      let(:notifier) { described_class.new(webhook_url: "https://hooks.slack.com/services/xxx") }

      it "sends notification via webhook" do
        stub_request(:post, "https://hooks.slack.com/services/xxx")
          .to_return(status: 200, body: "ok")

        result = notifier.notify(approval, "Please approve this request")

        expect(result).to be true
        expect(WebMock).to have_requested(:post, "https://hooks.slack.com/services/xxx")
          .with { |req|
            body = JSON.parse(req.body)
            body["text"] == "Please approve this request" &&
              body["blocks"].any? { |b| b["type"] == "header" }
          }
      end

      it "returns false on HTTP error" do
        stub_request(:post, "https://hooks.slack.com/services/xxx")
          .to_return(status: 500, body: "error")

        result = notifier.notify(approval, "Please approve")

        expect(result).to be false
      end
    end

    context "with API token" do
      let(:notifier) { described_class.new(api_token: "xoxb-token", channel: "#approvals") }

      it "sends notification via Slack API" do
        stub_request(:post, "https://slack.com/api/chat.postMessage")
          .to_return(status: 200, body: { ok: true }.to_json)

        result = notifier.notify(approval, "Please approve this request")

        expect(result).to be true
        expect(WebMock).to have_requested(:post, "https://slack.com/api/chat.postMessage")
          .with(
            headers: { "Authorization" => "Bearer xoxb-token" }
          )
      end

      it "includes channel in payload" do
        stub_request(:post, "https://slack.com/api/chat.postMessage")
          .to_return(status: 200, body: { ok: true }.to_json)

        notifier.notify(approval, "Please approve")

        expect(WebMock).to have_requested(:post, "https://slack.com/api/chat.postMessage")
          .with { |req|
            body = JSON.parse(req.body)
            body["channel"] == "#approvals"
          }
      end

      it "returns false when API returns ok: false" do
        stub_request(:post, "https://slack.com/api/chat.postMessage")
          .to_return(status: 200, body: { ok: false, error: "channel_not_found" }.to_json)

        result = notifier.notify(approval, "Please approve")

        expect(result).to be false
      end
    end

    context "without credentials" do
      let(:notifier) { described_class.new }

      it "logs and returns false" do
        result = notifier.notify(approval, "Please approve")

        expect(result).to be false
      end
    end

    context "on error" do
      let(:notifier) { described_class.new(webhook_url: "https://hooks.slack.com/services/xxx") }

      it "handles network errors gracefully" do
        stub_request(:post, "https://hooks.slack.com/services/xxx")
          .to_raise(Errno::ECONNREFUSED)

        result = notifier.notify(approval, "Please approve")

        expect(result).to be false
      end
    end
  end

  describe "message blocks" do
    let(:notifier) { described_class.new(webhook_url: "https://hooks.slack.com/services/xxx") }

    it "builds blocks with approval details" do
      stub_request(:post, "https://hooks.slack.com/services/xxx")
        .to_return(status: 200, body: "ok")

      notifier.notify(approval, "Please approve")

      expect(WebMock).to have_requested(:post, "https://hooks.slack.com/services/xxx")
        .with { |req|
          body = JSON.parse(req.body)
          blocks = body["blocks"]

          header = blocks.find { |b| b["type"] == "header" }
          expect(header["text"]["text"]).to include("manager_approval")

          section = blocks.find { |b| b["type"] == "section" && b["fields"] }
          fields_text = section["fields"].map { |f| f["text"] }.join(" ")
          expect(fields_text).to include("OrderApprovalWorkflow")
          expect(fields_text).to include("order-123")

          true
        }
    end
  end
end
