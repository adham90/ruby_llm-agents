# frozen_string_literal: true

require "rails_helper"

RSpec.describe RubyLLM::Agents::Redactor do
  before do
    # Reset configuration to defaults
    RubyLLM::Agents.reset_configuration!
  end

  describe ".redact" do
    context "with string input" do
      it "redacts sensitive field values" do
        input = { password: "secret123", name: "John" }
        result = described_class.redact(input)

        expect(result[:password]).to eq("[REDACTED]")
        expect(result[:name]).to eq("John")
      end

      it "redacts common sensitive fields" do
        sensitive_fields = %w[password token api_key secret credential auth key access_token]
        input = sensitive_fields.each_with_object({}) { |f, h| h[f.to_sym] = "value" }

        result = described_class.redact(input)

        sensitive_fields.each do |field|
          expect(result[field.to_sym]).to eq("[REDACTED]"), "Expected #{field} to be redacted"
        end
      end

      it "is case insensitive for field names" do
        input = { PASSWORD: "secret", Api_Key: "key123" }
        result = described_class.redact(input)

        expect(result[:PASSWORD]).to eq("[REDACTED]")
        expect(result[:Api_Key]).to eq("[REDACTED]")
      end
    end

    context "with nested hashes" do
      it "redacts sensitive fields at any depth" do
        input = {
          "user" => {
            "name" => "John",
            "login" => {
              "password" => "secret123",
              "api_key" => "key456",
              "username" => "john_doe"
            }
          }
        }

        result = described_class.redact(input)

        expect(result["user"]["name"]).to eq("John")
        expect(result["user"]["login"]["password"]).to eq("[REDACTED]")
        expect(result["user"]["login"]["api_key"]).to eq("[REDACTED]")
        expect(result["user"]["login"]["username"]).to eq("john_doe")
      end
    end

    context "with arrays" do
      it "redacts sensitive fields in array elements" do
        input = {
          users: [
            { name: "John", password: "pass1" },
            { name: "Jane", password: "pass2" }
          ]
        }

        result = described_class.redact(input)

        expect(result[:users][0][:password]).to eq("[REDACTED]")
        expect(result[:users][1][:password]).to eq("[REDACTED]")
        expect(result[:users][0][:name]).to eq("John")
      end
    end

    context "with custom fields configuration" do
      before do
        RubyLLM::Agents.configure do |config|
          config.redaction = { fields: %w[ssn credit_card] }
        end
      end

      it "includes custom fields in redaction" do
        input = { ssn: "123-45-6789", credit_card: "4111111111111111", name: "John" }
        result = described_class.redact(input)

        expect(result[:ssn]).to eq("[REDACTED]")
        expect(result[:credit_card]).to eq("[REDACTED]")
        expect(result[:name]).to eq("John")
      end
    end

    context "with non-hash input" do
      it "returns strings as-is" do
        expect(described_class.redact("plain text")).to eq("plain text")
      end

      it "returns nil as-is" do
        expect(described_class.redact(nil)).to be_nil
      end

      it "returns numbers as-is" do
        expect(described_class.redact(42)).to eq(42)
      end
    end
  end

  describe ".redact_string" do
    context "with pattern-based redaction" do
      before do
        RubyLLM::Agents.configure do |config|
          config.redaction = {
            patterns: [
              /\b\d{3}-\d{2}-\d{4}\b/,                                        # SSN
              /\b[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}\b/          # Email
            ]
          }
        end
      end

      it "applies custom patterns" do
        input = "Contact john@example.com or SSN: 123-45-6789"
        result = described_class.redact_string(input)

        expect(result).to include("[REDACTED]")
        expect(result).not_to include("john@example.com")
        expect(result).not_to include("123-45-6789")
      end
    end

    context "with truncation" do
      before do
        RubyLLM::Agents.configure do |config|
          config.redaction = { max_value_length: 50 }
        end
      end

      it "truncates long strings" do
        long_string = "a" * 100
        result = described_class.redact_string(long_string)

        expect(result.length).to eq(53) # 50 chars + "..."
        expect(result).to end_with("...")
      end

      it "does not truncate short strings" do
        short_string = "hello"
        result = described_class.redact_string(short_string)

        expect(result).to eq("hello")
      end
    end

    context "with nil input" do
      it "returns nil" do
        expect(described_class.redact_string(nil)).to be_nil
      end
    end
  end

  describe "edge cases" do
    it "handles symbols as values" do
      input = { status: :active, password: :secret }
      result = described_class.redact(input)

      expect(result[:status]).to eq(:active)
      expect(result[:password]).to eq("[REDACTED]")
    end

    it "handles empty hashes" do
      expect(described_class.redact({})).to eq({})
    end

    it "handles empty arrays" do
      expect(described_class.redact([])).to eq([])
    end

    it "does not modify the original object" do
      input = { password: "secret" }
      original = input.dup

      described_class.redact(input)

      expect(input).to eq(original)
    end
  end
end
