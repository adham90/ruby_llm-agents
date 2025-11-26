# frozen_string_literal: true

require "rails_helper"

RSpec.describe RubyLLM::Agents::ApplicationHelper, type: :helper do
  describe "#highlight_json" do
    it "returns highlighted HTML for valid JSON" do
      json = { "key" => "value" }
      result = helper.highlight_json(json)
      expect(result).to include("key")
      expect(result).to include("value")
    end

    it "handles nested JSON" do
      json = { "outer" => { "inner" => "value" } }
      result = helper.highlight_json(json)
      expect(result).to include("outer")
      expect(result).to include("inner")
    end

    it "handles arrays" do
      json = { "items" => [1, 2, 3] }
      result = helper.highlight_json(json)
      expect(result).to include("items")
    end

    it "handles nil values" do
      json = { "key" => nil }
      result = helper.highlight_json(json)
      expect(result).to include("null")
    end

    it "handles boolean values" do
      json = { "flag" => true, "other" => false }
      result = helper.highlight_json(json)
      expect(result).to include("true")
      expect(result).to include("false")
    end

    it "escapes HTML in string values" do
      json = { "key" => "<script>alert('xss')</script>" }
      result = helper.highlight_json(json)
      expect(result).not_to include("<script>")
      expect(result).to include("&lt;script&gt;")
    end

    it "returns html_safe string" do
      json = { "key" => "value" }
      result = helper.highlight_json(json)
      expect(result).to be_html_safe
    end

    context "with nil input" do
      it "returns empty string" do
        result = helper.highlight_json(nil)
        expect(result).to eq("")
      end
    end

    context "with empty hash" do
      it "returns formatted empty object" do
        result = helper.highlight_json({})
        expect(result).to include("{}")
      end
    end
  end

  describe "#redact_for_display" do
    it "delegates to Redactor.redact" do
      obj = { password: "secret123" }
      expect(RubyLLM::Agents::Redactor).to receive(:redact).with(obj)
      helper.redact_for_display(obj)
    end

    it "redacts sensitive data" do
      obj = { password: "secret123", name: "John" }
      result = helper.redact_for_display(obj)
      expect(result[:password]).to eq("[REDACTED]")
      expect(result[:name]).to eq("John")
    end

    it "handles nested objects" do
      # Note: "key" is a default sensitive field, so api_key will be redacted
      obj = { user: { api_key: "secret-key-123", id: 1 } }
      result = helper.redact_for_display(obj)
      expect(result[:user][:api_key]).to eq("[REDACTED]")
      expect(result[:user][:id]).to eq(1)
    end

    it "handles nil" do
      result = helper.redact_for_display(nil)
      expect(result).to be_nil
    end
  end

  describe "#highlight_json_redacted" do
    it "returns empty string for nil" do
      result = helper.highlight_json_redacted(nil)
      expect(result).to eq("")
    end

    it "redacts before highlighting" do
      obj = { password: "secret123" }
      result = helper.highlight_json_redacted(obj)
      expect(result).to include("[REDACTED]")
      expect(result).not_to include("secret123")
    end

    it "returns highlighted HTML" do
      # Use a non-sensitive field name (not containing password, token, key, secret, etc.)
      obj = { name: "value" }
      result = helper.highlight_json_redacted(obj)
      expect(result).to include("name")
      expect(result).to include("value")
    end

    it "combines redaction and highlighting" do
      # api_key contains "key" which is a default sensitive field
      obj = { api_key: "secret-key-123", status: "active" }
      result = helper.highlight_json_redacted(obj)
      expect(result).to include("[REDACTED]")
      expect(result).to include("active")
      expect(result).not_to include("secret-key-123")
    end
  end
end
