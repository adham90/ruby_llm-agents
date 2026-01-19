# frozen_string_literal: true

require "rails_helper"

RSpec.describe RubyLLM::Agents::AlertManager do
  before do
    RubyLLM::Agents.reset_configuration!
  end

  describe ".notify" do
    context "when alerts disabled" do
      before do
        allow(RubyLLM::Agents.configuration).to receive(:alerts_enabled?).and_return(false)
      end

      it "does nothing" do
        expect(Net::HTTP).not_to receive(:new)
        described_class.notify(:budget_soft_cap, { amount: 100 })
      end
    end

    context "when event not in configured events" do
      before do
        RubyLLM::Agents.configure do |config|
          config.alerts = {
            on_events: [:budget_soft_cap],
            webhook_url: "https://example.com/webhook"
          }
        end
      end

      it "does nothing for unconfigured events" do
        expect(Net::HTTP).not_to receive(:new)
        described_class.notify(:breaker_open, { model: "gpt-4o" })
      end
    end

    context "with Slack webhook configured" do
      let(:http_double) { instance_double(Net::HTTP) }
      let(:response_double) { instance_double(Net::HTTPSuccess, code: "200", body: "ok") }

      before do
        RubyLLM::Agents.configure do |config|
          config.alerts = {
            on_events: [:budget_soft_cap, :breaker_open],
            slack_webhook_url: "https://hooks.slack.com/services/test"
          }
        end

        allow(Net::HTTP).to receive(:new).with("hooks.slack.com", 443).and_return(http_double)
        allow(http_double).to receive(:use_ssl=)
        allow(http_double).to receive(:open_timeout=)
        allow(http_double).to receive(:read_timeout=)
        allow(http_double).to receive(:request).and_return(response_double)
        allow(response_double).to receive(:is_a?).with(Net::HTTPSuccess).and_return(true)
      end

      it "sends to Slack webhook" do
        expect(http_double).to receive(:request) do |request|
          expect(request).to be_a(Net::HTTP::Post)
          expect(request["Content-Type"]).to eq("application/json")
          response_double
        end

        described_class.notify(:budget_soft_cap, { amount: 100, limit: 50 })
      end

      it "formats payload for Slack with attachments" do
        captured_body = nil
        allow(http_double).to receive(:request) do |request|
          captured_body = JSON.parse(request.body)
          response_double
        end

        described_class.notify(:budget_soft_cap, { amount: 100 })

        expect(captured_body).to have_key("attachments")
        expect(captured_body["attachments"]).to be_an(Array)
      end
    end

    context "with generic webhook configured" do
      let(:http_double) { instance_double(Net::HTTP) }
      let(:response_double) { instance_double(Net::HTTPSuccess, code: "200", body: "ok") }

      before do
        RubyLLM::Agents.configure do |config|
          config.alerts = {
            on_events: [:budget_soft_cap],
            webhook_url: "https://example.com/webhook"
          }
        end

        allow(Net::HTTP).to receive(:new).with("example.com", 443).and_return(http_double)
        allow(http_double).to receive(:use_ssl=)
        allow(http_double).to receive(:open_timeout=)
        allow(http_double).to receive(:read_timeout=)
        allow(http_double).to receive(:request).and_return(response_double)
        allow(response_double).to receive(:is_a?).with(Net::HTTPSuccess).and_return(true)
      end

      it "sends JSON payload with event" do
        captured_body = nil
        allow(http_double).to receive(:request) do |request|
          captured_body = JSON.parse(request.body)
          response_double
        end

        described_class.notify(:budget_soft_cap, { amount: 100 })

        expect(captured_body["event"]).to eq("budget_soft_cap")
        expect(captured_body["amount"]).to eq(100)
      end
    end

    context "with custom proc configured" do
      let(:received_events) { [] }

      before do
        events_array = received_events
        RubyLLM::Agents.configure do |config|
          config.alerts = {
            on_events: [:budget_soft_cap],
            custom: ->(event, payload) { events_array << [event, payload] }
          }
        end
      end

      it "calls custom proc with event and payload" do
        described_class.notify(:budget_soft_cap, { amount: 100 })

        expect(received_events.length).to eq(1)
        expect(received_events[0][0]).to eq(:budget_soft_cap)
        expect(received_events[0][1][:amount]).to eq(100)
      end
    end

    context "error handling" do
      before do
        RubyLLM::Agents.configure do |config|
          config.alerts = {
            on_events: [:budget_soft_cap],
            custom: ->(_event, _payload) { raise StandardError, "Custom handler error" }
          }
        end
      end

      it "logs errors from custom handlers but does not raise" do
        expect(Rails.logger).to receive(:warn).with(/Custom alert failed/)
        expect { described_class.notify(:budget_soft_cap, {}) }.not_to raise_error
      end
    end

    context "with non-success HTTP response" do
      let(:http_double) { instance_double(Net::HTTP) }
      let(:response_double) { instance_double(Net::HTTPBadRequest, code: "400", body: "Bad Request") }

      before do
        RubyLLM::Agents.configure do |config|
          config.alerts = {
            on_events: [:budget_soft_cap],
            webhook_url: "https://example.com/webhook"
          }
        end

        allow(Net::HTTP).to receive(:new).with("example.com", 443).and_return(http_double)
        allow(http_double).to receive(:use_ssl=)
        allow(http_double).to receive(:open_timeout=)
        allow(http_double).to receive(:read_timeout=)
        allow(http_double).to receive(:request).and_return(response_double)
        allow(response_double).to receive(:is_a?).with(Net::HTTPSuccess).and_return(false)
      end

      it "logs warning for non-success responses" do
        expect(Rails.logger).to receive(:warn).with(/Webhook returned 400/)
        described_class.notify(:budget_soft_cap, { amount: 100 })
      end
    end
  end
end
