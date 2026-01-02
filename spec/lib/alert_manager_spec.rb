# frozen_string_literal: true

require "rails_helper"

RSpec.describe RubyLLM::Agents::AlertManager do
  before do
    RubyLLM::Agents.reset_configuration!
    # Reset the cached HTTP client between tests
    described_class.instance_variable_set(:@http_client, nil)
  end

  describe ".notify" do
    context "when alerts disabled" do
      before do
        allow(RubyLLM::Agents.configuration).to receive(:alerts_enabled?).and_return(false)
      end

      it "does nothing" do
        # Should not make any HTTP calls
        expect(Faraday).not_to receive(:new)
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
        # Create a stubs adapter to verify no requests are made
        stubs = Faraday::Adapter::Test::Stubs.new
        faraday = Faraday.new { |f| f.adapter(:test, stubs) }
        allow(described_class).to receive(:http_client).and_return(faraday)

        described_class.notify(:breaker_open, { model: "gpt-4o" })

        # Verify no unexpected requests
        stubs.verify_stubbed_calls
      end
    end

    context "with Slack webhook configured" do
      let(:stubs) { Faraday::Adapter::Test::Stubs.new }
      let(:faraday) { Faraday.new { |f| f.adapter(:test, stubs) } }

      before do
        RubyLLM::Agents.configure do |config|
          config.alerts = {
            on_events: [:budget_soft_cap, :breaker_open],
            slack_webhook_url: "https://hooks.slack.com/services/test"
          }
        end

        allow(described_class).to receive(:http_client).and_return(faraday)
      end

      it "sends to Slack webhook" do
        stubs.post("https://hooks.slack.com/services/test") do |env|
          expect(env.request_headers["Content-Type"]).to eq("application/json")
          [200, {}, "ok"]
        end

        described_class.notify(:budget_soft_cap, { amount: 100, limit: 50 })

        stubs.verify_stubbed_calls
      end

      it "formats payload for Slack with attachments" do
        captured_body = nil
        stubs.post("https://hooks.slack.com/services/test") do |env|
          captured_body = JSON.parse(env.body)
          [200, {}, "ok"]
        end

        described_class.notify(:budget_soft_cap, { amount: 100 })

        expect(captured_body).to have_key("attachments")
        expect(captured_body["attachments"]).to be_an(Array)
      end
    end

    context "with generic webhook configured" do
      let(:stubs) { Faraday::Adapter::Test::Stubs.new }
      let(:faraday) { Faraday.new { |f| f.adapter(:test, stubs) } }

      before do
        RubyLLM::Agents.configure do |config|
          config.alerts = {
            on_events: [:budget_soft_cap],
            webhook_url: "https://example.com/webhook"
          }
        end

        allow(described_class).to receive(:http_client).and_return(faraday)
      end

      it "sends JSON payload with event" do
        captured_body = nil
        stubs.post("https://example.com/webhook") do |env|
          captured_body = JSON.parse(env.body)
          [200, {}, "ok"]
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
  end
end
