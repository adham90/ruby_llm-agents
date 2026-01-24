# frozen_string_literal: true

require "rails_helper"

RSpec.describe RubyLLM::Agents::Redactor do
  let(:mock_config) do
    double("Configuration",
      redaction_fields: %w[password secret api_key token],
      redaction_patterns: [
        /\b\d{3}-\d{2}-\d{4}\b/,         # SSN pattern
        /\b[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Z|a-z]{2,}\b/  # Email pattern
      ],
      redaction_placeholder: "[REDACTED]",
      redaction_max_value_length: 1000
    )
  end

  before do
    allow(RubyLLM::Agents).to receive(:configuration).and_return(mock_config)
  end

  describe ".redact" do
    context "with a hash" do
      it "redacts sensitive field values" do
        input = { password: "secret123", name: "John" }
        result = described_class.redact(input)

        expect(result[:password]).to eq("[REDACTED]")
        expect(result[:name]).to eq("John")
      end

      it "redacts fields containing sensitive keywords" do
        input = {
          user_password: "secret",
          api_key_value: "sk-123",
          auth_token: "token123",
          client_secret: "shh"
        }
        result = described_class.redact(input)

        expect(result[:user_password]).to eq("[REDACTED]")
        expect(result[:api_key_value]).to eq("[REDACTED]")
        expect(result[:auth_token]).to eq("[REDACTED]")
        expect(result[:client_secret]).to eq("[REDACTED]")
      end

      it "is case-insensitive for field names" do
        input = { PASSWORD: "secret", Api_Key: "key123" }
        result = described_class.redact(input)

        expect(result[:PASSWORD]).to eq("[REDACTED]")
        expect(result[:Api_Key]).to eq("[REDACTED]")
      end

      it "handles string keys" do
        input = { "password" => "secret", "name" => "John" }
        result = described_class.redact(input)

        expect(result["password"]).to eq("[REDACTED]")
        expect(result["name"]).to eq("John")
      end

      it "does not modify original hash" do
        input = { password: "secret" }
        described_class.redact(input)

        expect(input[:password]).to eq("secret")
      end

      it "recursively redacts nested hashes" do
        input = {
          user: {
            credentials: {
              password: "secret",
              api_key: "key123"
            },
            name: "John"
          }
        }
        result = described_class.redact(input)

        expect(result[:user][:credentials][:password]).to eq("[REDACTED]")
        expect(result[:user][:credentials][:api_key]).to eq("[REDACTED]")
        expect(result[:user][:name]).to eq("John")
      end
    end

    context "with an array" do
      it "redacts each element" do
        input = [
          { password: "secret1" },
          { password: "secret2" }
        ]
        result = described_class.redact(input)

        expect(result[0][:password]).to eq("[REDACTED]")
        expect(result[1][:password]).to eq("[REDACTED]")
      end

      it "handles mixed arrays" do
        input = [
          { password: "secret" },
          "some text",
          123
        ]
        result = described_class.redact(input)

        expect(result[0][:password]).to eq("[REDACTED]")
        expect(result[1]).to eq("some text")
        expect(result[2]).to eq(123)
      end
    end

    context "with a string" do
      it "applies pattern-based redaction" do
        input = "My SSN is 123-45-6789"
        result = described_class.redact(input)

        expect(result).to eq("My SSN is [REDACTED]")
      end

      it "redacts email patterns" do
        input = "Contact: test@example.com"
        result = described_class.redact(input)

        expect(result).to eq("Contact: [REDACTED]")
      end

      it "redacts multiple patterns" do
        input = "SSN: 123-45-6789, Email: test@example.com"
        result = described_class.redact(input)

        expect(result).to eq("SSN: [REDACTED], Email: [REDACTED]")
      end
    end

    context "with primitives" do
      it "returns numbers unchanged" do
        expect(described_class.redact(123)).to eq(123)
        expect(described_class.redact(3.14)).to eq(3.14)
      end

      it "returns booleans unchanged" do
        expect(described_class.redact(true)).to eq(true)
        expect(described_class.redact(false)).to eq(false)
      end

      it "returns nil unchanged" do
        expect(described_class.redact(nil)).to be_nil
      end
    end

    context "with custom config" do
      it "uses provided config instead of global" do
        custom_config = double("CustomConfig",
          redaction_fields: %w[custom_field],
          redaction_patterns: [],
          redaction_placeholder: "[HIDDEN]",
          redaction_max_value_length: nil
        )

        input = { custom_field: "value", password: "secret" }
        result = described_class.redact(input, custom_config)

        expect(result[:custom_field]).to eq("[HIDDEN]")
        expect(result[:password]).to eq("secret")  # Not in custom fields
      end
    end
  end

  describe ".redact_string" do
    it "applies all configured patterns" do
      result = described_class.redact_string("SSN: 123-45-6789, Email: test@example.com")
      expect(result).to eq("SSN: [REDACTED], Email: [REDACTED]")
    end

    it "returns nil for nil input" do
      expect(described_class.redact_string(nil)).to be_nil
    end

    it "returns non-string input unchanged" do
      expect(described_class.redact_string(123)).to eq(123)
    end

    it "truncates long strings when max_length is configured" do
      long_string = "a" * 2000
      result = described_class.redact_string(long_string)

      expect(result.length).to be <= 1003  # 1000 + "..."
      expect(result).to end_with("...")
    end

    it "does not truncate when max_length is nil" do
      config_without_max = double("Config",
        redaction_patterns: [],
        redaction_placeholder: "[REDACTED]",
        redaction_max_value_length: nil
      )
      allow(RubyLLM::Agents).to receive(:configuration).and_return(config_without_max)

      long_string = "a" * 2000
      result = described_class.redact_string(long_string)

      expect(result.length).to eq(2000)
    end

    it "does not modify original string" do
      original = "SSN: 123-45-6789"
      described_class.redact_string(original)

      expect(original).to eq("SSN: 123-45-6789")
    end
  end

  describe "edge cases" do
    it "handles empty hash" do
      expect(described_class.redact({})).to eq({})
    end

    it "handles empty array" do
      expect(described_class.redact([])).to eq([])
    end

    it "handles empty string" do
      expect(described_class.redact("")).to eq("")
    end

    it "handles deeply nested structures" do
      input = {
        level1: {
          level2: {
            level3: {
              level4: {
                password: "deep_secret"
              }
            }
          }
        }
      }
      result = described_class.redact(input)

      expect(result[:level1][:level2][:level3][:level4][:password]).to eq("[REDACTED]")
    end

    it "handles arrays within hashes within arrays" do
      input = [
        {
          items: [
            { password: "secret1" },
            { password: "secret2" }
          ]
        }
      ]
      result = described_class.redact(input)

      expect(result[0][:items][0][:password]).to eq("[REDACTED]")
      expect(result[0][:items][1][:password]).to eq("[REDACTED]")
    end
  end

  describe "configuration integration" do
    it "uses default configuration when none provided" do
      # Should not raise
      result = described_class.redact({ password: "test" })
      expect(result[:password]).to eq("[REDACTED]")
    end
  end
end
