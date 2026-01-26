# frozen_string_literal: true

require "rails_helper"

RSpec.describe RubyLLM::Agents::Workflow::Notifiers::Webhook do
  let(:approval) do
    RubyLLM::Agents::Workflow::Approval.new(
      workflow_id: "order-123",
      workflow_type: "OrderApprovalWorkflow",
      name: :manager_approval,
      approvers: ["manager@example.com"],
      metadata: { order_total: 5000 }
    )
  end

  after do
    described_class.reset!
  end

  describe ".configure" do
    it "sets class-level configuration" do
      described_class.configure do |config|
        config.default_url = "https://api.example.com/approvals"
        config.default_headers = { "X-API-Key" => "secret" }
        config.timeout = 30
      end

      expect(described_class.default_url).to eq("https://api.example.com/approvals")
      expect(described_class.default_headers).to eq({ "X-API-Key" => "secret" })
      expect(described_class.timeout).to eq(30)
    end
  end

  describe ".reset!" do
    it "clears configuration" do
      described_class.default_url = "https://api.example.com"
      described_class.reset!

      expect(described_class.default_url).to be_nil
      expect(described_class.default_headers).to be_nil
      expect(described_class.timeout).to be_nil
    end
  end

  describe "#initialize" do
    it "uses instance options" do
      notifier = described_class.new(
        url: "https://custom.example.com",
        headers: { "Authorization" => "Bearer token" },
        timeout: 60
      )

      expect(notifier.instance_variable_get(:@url)).to eq("https://custom.example.com")
      expect(notifier.instance_variable_get(:@headers)).to include("Authorization" => "Bearer token")
      expect(notifier.instance_variable_get(:@timeout)).to eq(60)
    end

    it "falls back to class configuration" do
      described_class.default_url = "https://class.example.com"
      described_class.default_headers = { "X-Class" => "header" }

      notifier = described_class.new

      expect(notifier.instance_variable_get(:@url)).to eq("https://class.example.com")
      expect(notifier.instance_variable_get(:@headers)).to include("X-Class" => "header")
    end

    it "merges instance headers with class headers" do
      described_class.default_headers = { "X-Class" => "class-value" }

      notifier = described_class.new(headers: { "X-Instance" => "instance-value" })

      headers = notifier.instance_variable_get(:@headers)
      expect(headers["X-Class"]).to eq("class-value")
      expect(headers["X-Instance"]).to eq("instance-value")
    end

    it "uses default timeout of 10" do
      notifier = described_class.new(url: "https://example.com")
      expect(notifier.instance_variable_get(:@timeout)).to eq(10)
    end
  end

  describe "#notify" do
    let(:notifier) { described_class.new(url: "https://api.example.com/approvals") }
    let(:mock_http) { instance_double(Net::HTTP) }
    let(:mock_response) { instance_double(Net::HTTPResponse) }

    before do
      allow(Net::HTTP).to receive(:new).and_return(mock_http)
      allow(mock_http).to receive(:use_ssl=)
      allow(mock_http).to receive(:open_timeout=)
      allow(mock_http).to receive(:read_timeout=)
    end

    context "successful request" do
      before do
        allow(mock_response).to receive(:code).and_return("200")
        allow(mock_response).to receive(:body).and_return("OK")
        allow(mock_http).to receive(:request).and_return(mock_response)
      end

      it "sends POST request with approval data" do
        result = notifier.notify(approval, "Please approve this request")

        expect(result).to be true
        expect(mock_http).to have_received(:request) do |request|
          expect(request).to be_a(Net::HTTP::Post)
        end
      end

      it "includes all approval data in payload" do
        notifier.notify(approval, "Please approve")

        expect(mock_http).to have_received(:request) do |request|
          body = JSON.parse(request.body)

          expect(body["event"]).to eq("approval_requested")
          expect(body["message"]).to eq("Please approve")
          expect(body["timestamp"]).to be_present

          approval_data = body["approval"]
          expect(approval_data["id"]).to eq(approval.id)
          expect(approval_data["workflow_id"]).to eq("order-123")
          expect(approval_data["workflow_type"]).to eq("OrderApprovalWorkflow")
          expect(approval_data["name"]).to eq("manager_approval")
          expect(approval_data["status"]).to eq("pending")
          expect(approval_data["approvers"]).to eq(["manager@example.com"])
          expect(approval_data["metadata"]["order_total"]).to eq(5000)
        end
      end

      it "sets Content-Type header to JSON" do
        notifier.notify(approval, "Please approve")

        expect(mock_http).to have_received(:request) do |request|
          expect(request["Content-Type"]).to eq("application/json")
        end
      end

      it "includes custom headers" do
        custom_notifier = described_class.new(
          url: "https://api.example.com/approvals",
          headers: { "Authorization" => "Bearer token123" }
        )

        custom_notifier.notify(approval, "Please approve")

        expect(mock_http).to have_received(:request) do |request|
          expect(request["Authorization"]).to eq("Bearer token123")
        end
      end
    end

    context "response status codes" do
      it "returns true for 200" do
        allow(mock_response).to receive(:code).and_return("200")
        allow(mock_http).to receive(:request).and_return(mock_response)

        expect(notifier.notify(approval, "test")).to be true
      end

      it "returns true for 201" do
        allow(mock_response).to receive(:code).and_return("201")
        allow(mock_http).to receive(:request).and_return(mock_response)

        expect(notifier.notify(approval, "test")).to be true
      end

      it "returns true for 204" do
        allow(mock_response).to receive(:code).and_return("204")
        allow(mock_http).to receive(:request).and_return(mock_response)

        expect(notifier.notify(approval, "test")).to be true
      end

      it "returns false for 400" do
        allow(mock_response).to receive(:code).and_return("400")
        allow(mock_http).to receive(:request).and_return(mock_response)

        expect(notifier.notify(approval, "test")).to be false
      end

      it "returns false for 500" do
        allow(mock_response).to receive(:code).and_return("500")
        allow(mock_http).to receive(:request).and_return(mock_response)

        expect(notifier.notify(approval, "test")).to be false
      end
    end

    context "without URL" do
      let(:notifier) { described_class.new }

      it "returns false" do
        expect(notifier.notify(approval, "test")).to be false
      end
    end

    context "on error" do
      it "handles connection errors" do
        allow(mock_http).to receive(:request).and_raise(Errno::ECONNREFUSED)

        result = notifier.notify(approval, "test")

        expect(result).to be false
      end

      it "handles timeout errors" do
        allow(mock_http).to receive(:request).and_raise(Net::ReadTimeout)

        result = notifier.notify(approval, "test")

        expect(result).to be false
      end
    end
  end

  describe "HTTPS support" do
    let(:mock_http) { instance_double(Net::HTTP) }
    let(:mock_response) { instance_double(Net::HTTPResponse) }

    before do
      allow(Net::HTTP).to receive(:new).and_return(mock_http)
      allow(mock_http).to receive(:open_timeout=)
      allow(mock_http).to receive(:read_timeout=)
      allow(mock_response).to receive(:code).and_return("200")
      allow(mock_http).to receive(:request).and_return(mock_response)
    end

    it "uses SSL for https URLs" do
      allow(mock_http).to receive(:use_ssl=)

      notifier = described_class.new(url: "https://secure.example.com/approvals")
      notifier.notify(approval, "test")

      expect(mock_http).to have_received(:use_ssl=).with(true)
    end

    it "does not use SSL for http URLs" do
      allow(mock_http).to receive(:use_ssl=)

      notifier = described_class.new(url: "http://insecure.example.com/approvals")
      notifier.notify(approval, "test")

      expect(mock_http).to have_received(:use_ssl=).with(false)
    end
  end
end
