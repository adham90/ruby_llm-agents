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
    let(:mock_http) { instance_double(Net::HTTP) }
    let(:mock_response) { instance_double(Net::HTTPResponse) }

    before do
      allow(Net::HTTP).to receive(:new).and_return(mock_http)
      allow(mock_http).to receive(:use_ssl=)
      allow(mock_http).to receive(:open_timeout=)
      allow(mock_http).to receive(:read_timeout=)
    end

    context "with webhook" do
      let(:notifier) { described_class.new(webhook_url: "https://hooks.slack.com/services/xxx") }

      it "sends notification via webhook" do
        allow(mock_response).to receive(:code).and_return("200")
        allow(mock_response).to receive(:body).and_return("ok")
        allow(mock_http).to receive(:request).and_return(mock_response)

        result = notifier.notify(approval, "Please approve this request")

        expect(result).to be true
        expect(mock_http).to have_received(:request) do |request|
          expect(request).to be_a(Net::HTTP::Post)
          body = JSON.parse(request.body)
          expect(body["text"]).to eq("Please approve this request")
          expect(body["blocks"]).to be_an(Array)
        end
      end

      it "returns false on HTTP error" do
        allow(mock_response).to receive(:code).and_return("500")
        allow(mock_response).to receive(:body).and_return("error")
        allow(mock_http).to receive(:request).and_return(mock_response)

        result = notifier.notify(approval, "Please approve")

        expect(result).to be false
      end
    end

    context "with API token" do
      let(:notifier) { described_class.new(api_token: "xoxb-token", channel: "#approvals") }

      it "sends notification via Slack API" do
        allow(mock_response).to receive(:code).and_return("200")
        allow(mock_response).to receive(:body).and_return({ ok: true }.to_json)
        allow(mock_http).to receive(:request).and_return(mock_response)

        result = notifier.notify(approval, "Please approve this request")

        expect(result).to be true
        expect(mock_http).to have_received(:request) do |request|
          expect(request["Authorization"]).to eq("Bearer xoxb-token")
        end
      end

      it "includes channel in payload" do
        allow(mock_response).to receive(:code).and_return("200")
        allow(mock_response).to receive(:body).and_return({ ok: true }.to_json)
        allow(mock_http).to receive(:request).and_return(mock_response)

        notifier.notify(approval, "Please approve")

        expect(mock_http).to have_received(:request) do |request|
          body = JSON.parse(request.body)
          expect(body["channel"]).to eq("#approvals")
        end
      end

      it "returns false when API returns ok: false" do
        allow(mock_response).to receive(:code).and_return("200")
        allow(mock_response).to receive(:body).and_return({ ok: false, error: "channel_not_found" }.to_json)
        allow(mock_http).to receive(:request).and_return(mock_response)

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
        allow(mock_http).to receive(:request).and_raise(Errno::ECONNREFUSED)

        result = notifier.notify(approval, "Please approve")

        expect(result).to be false
      end
    end
  end

  describe "message blocks" do
    let(:notifier) { described_class.new(webhook_url: "https://hooks.slack.com/services/xxx") }
    let(:mock_http) { instance_double(Net::HTTP) }
    let(:mock_response) { instance_double(Net::HTTPResponse) }

    before do
      allow(Net::HTTP).to receive(:new).and_return(mock_http)
      allow(mock_http).to receive(:use_ssl=)
      allow(mock_http).to receive(:open_timeout=)
      allow(mock_http).to receive(:read_timeout=)
      allow(mock_response).to receive(:code).and_return("200")
      allow(mock_response).to receive(:body).and_return("ok")
      allow(mock_http).to receive(:request).and_return(mock_response)
    end

    it "builds blocks with approval details" do
      notifier.notify(approval, "Please approve")

      expect(mock_http).to have_received(:request) do |request|
        body = JSON.parse(request.body)
        blocks = body["blocks"]

        header = blocks.find { |b| b["type"] == "header" }
        expect(header["text"]["text"]).to include("manager_approval")

        section = blocks.find { |b| b["type"] == "section" && b["fields"] }
        fields_text = section["fields"].map { |f| f["text"] }.join(" ")
        expect(fields_text).to include("OrderApprovalWorkflow")
        expect(fields_text).to include("order-123")
      end
    end
  end
end
