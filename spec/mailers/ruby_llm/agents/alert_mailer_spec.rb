# frozen_string_literal: true

require "rails_helper"

RSpec.describe RubyLLM::Agents::AlertMailer, type: :mailer do
  before do
    RubyLLM::Agents.configure do |config|
      config.alerts = {
        on_events: [:budget_soft_cap, :budget_hard_cap, :breaker_open, :agent_anomaly],
        email_recipients: ["admin@example.com"],
        email_from: "alerts@example.com"
      }
    end
  end

  describe "#alert_notification" do
    let(:event) { :budget_hard_cap }
    let(:payload) { { limit: 100.0, total: 105.0, agent_name: "test_agent" } }
    let(:recipient) { "admin@example.com" }

    subject(:mail) do
      described_class.alert_notification(
        event: event,
        payload: payload,
        recipient: recipient
      )
    end

    it "sends to the specified recipient" do
      expect(mail.to).to eq([recipient])
    end

    it "includes alert title in subject" do
      expect(mail.subject).to eq("[RubyLLM::Agents Alert] Budget Hard Cap Exceeded")
    end

    it "renders both html and text templates" do
      expect(mail.content_type).to include("multipart/alternative")
    end

    describe "HTML body" do
      subject(:html_body) { mail.html_part.body.to_s }

      it "includes the event title" do
        expect(html_body).to include("Budget Hard Cap Exceeded")
      end

      it "includes severity indicator" do
        expect(html_body).to include("Critical")
      end

      it "includes payload details" do
        expect(html_body).to include("Limit")
        expect(html_body).to include("100.0")
        expect(html_body).to include("Total")
        expect(html_body).to include("105.0")
        expect(html_body).to include("Agent Name")
        expect(html_body).to include("test_agent")
      end

      it "includes the event type in footer" do
        expect(html_body).to include("budget_hard_cap")
      end

      it "applies appropriate color for critical events" do
        expect(html_body).to include("#FF0000")
      end
    end

    describe "text body" do
      subject(:text_body) { mail.text_part.body.to_s }

      it "includes the event title" do
        expect(text_body).to include("Budget Hard Cap Exceeded")
      end

      it "includes severity indicator" do
        expect(text_body).to include("Severity: Critical")
      end

      it "includes payload details" do
        expect(text_body).to include("Limit: 100.0")
        expect(text_body).to include("Total: 105.0")
        expect(text_body).to include("Agent Name: test_agent")
      end
    end

    context "with :budget_soft_cap event" do
      let(:event) { :budget_soft_cap }

      it "uses appropriate title" do
        expect(mail.subject).to include("Budget Soft Cap Reached")
      end

      it "shows warning severity" do
        expect(mail.html_part.body.to_s).to include("Warning")
      end

      it "uses orange color" do
        expect(mail.html_part.body.to_s).to include("#FFA500")
      end
    end

    context "with :breaker_open event" do
      let(:event) { :breaker_open }
      let(:payload) { { model: "gpt-4o", reason: "rate_limit" } }

      it "uses appropriate title" do
        expect(mail.subject).to include("Circuit Breaker Opened")
      end

      it "shows critical severity" do
        expect(mail.html_part.body.to_s).to include("Critical")
      end

      it "includes model in payload" do
        expect(mail.html_part.body.to_s).to include("gpt-4o")
      end
    end

    context "with :agent_anomaly event" do
      let(:event) { :agent_anomaly }

      it "uses appropriate title" do
        expect(mail.subject).to include("Agent Anomaly Detected")
      end

      it "shows warning severity" do
        expect(mail.html_part.body.to_s).to include("Warning")
      end
    end

    context "with custom event type" do
      let(:event) { :custom_alert_type }

      it "titleizes the event name" do
        expect(mail.subject).to include("Custom Alert Type")
      end

      it "shows info severity" do
        expect(mail.html_part.body.to_s).to include("Info")
      end

      it "uses blue color" do
        expect(mail.html_part.body.to_s).to include("#0000FF")
      end
    end

    context "with hash values in payload" do
      let(:payload) { { metadata: { key: "value", nested: { deep: true } } } }

      it "serializes hash values to JSON" do
        # JSON is HTML-escaped in the email body
        html_body = mail.html_part.body.to_s
        expect(html_body).to include("Metadata")
        expect(html_body).to include("key")
        expect(html_body).to include("value")
        expect(html_body).to include("nested")
        expect(html_body).to include("deep")
      end
    end

    context "with empty payload" do
      let(:payload) { {} }

      it "still renders successfully" do
        expect { mail.body }.not_to raise_error
      end
    end
  end
end
