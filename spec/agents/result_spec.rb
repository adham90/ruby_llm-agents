# frozen_string_literal: true

require "rails_helper"

RSpec.describe RubyLLM::Agents::Result do
  describe "#initialize" do
    it "sets content" do
      result = described_class.new(content: { key: "value" })
      expect(result.content).to eq({ key: "value" })
    end

    it "sets token usage" do
      result = described_class.new(
        content: "test",
        input_tokens: 100,
        output_tokens: 50,
        cached_tokens: 10,
        cache_creation_tokens: 5
      )

      expect(result.input_tokens).to eq(100)
      expect(result.output_tokens).to eq(50)
      expect(result.cached_tokens).to eq(10)
      expect(result.cache_creation_tokens).to eq(5)
    end

    it "sets cost" do
      result = described_class.new(
        content: "test",
        input_cost: 0.001,
        output_cost: 0.002,
        total_cost: 0.003
      )

      expect(result.input_cost).to eq(0.001)
      expect(result.output_cost).to eq(0.002)
      expect(result.total_cost).to eq(0.003)
    end

    it "sets model info" do
      result = described_class.new(
        content: "test",
        model_id: "gpt-4o",
        chosen_model_id: "gpt-4o-mini",
        temperature: 0.7
      )

      expect(result.model_id).to eq("gpt-4o")
      expect(result.chosen_model_id).to eq("gpt-4o-mini")
      expect(result.temperature).to eq(0.7)
    end

    it "sets timing" do
      started = Time.current
      completed = started + 1.second

      result = described_class.new(
        content: "test",
        started_at: started,
        completed_at: completed,
        duration_ms: 1000,
        time_to_first_token_ms: 250
      )

      expect(result.started_at).to eq(started)
      expect(result.completed_at).to eq(completed)
      expect(result.duration_ms).to eq(1000)
      expect(result.time_to_first_token_ms).to eq(250)
    end

    it "sets status info" do
      result = described_class.new(
        content: "test",
        finish_reason: "stop",
        streaming: true
      )

      expect(result.finish_reason).to eq("stop")
      expect(result.streaming).to be true
    end

    it "sets error info" do
      result = described_class.new(
        content: "test",
        error_class: "Timeout::Error",
        error_message: "Request timed out"
      )

      expect(result.error_class).to eq("Timeout::Error")
      expect(result.error_message).to eq("Request timed out")
    end

    it "sets reliability info" do
      attempts = [{ model_id: "gpt-4o", duration_ms: 500 }]
      result = described_class.new(
        content: "test",
        attempts: attempts,
        attempts_count: 2
      )

      expect(result.attempts).to eq(attempts)
      expect(result.attempts_count).to eq(2)
    end

    it "defaults cached_tokens to 0" do
      result = described_class.new(content: "test")
      expect(result.cached_tokens).to eq(0)
    end

    it "defaults cache_creation_tokens to 0" do
      result = described_class.new(content: "test")
      expect(result.cache_creation_tokens).to eq(0)
    end

    it "defaults streaming to false" do
      result = described_class.new(content: "test")
      expect(result.streaming).to be false
    end

    it "defaults attempts to empty array" do
      result = described_class.new(content: "test")
      expect(result.attempts).to eq([])
    end

    it "defaults attempts_count to 1" do
      result = described_class.new(content: "test")
      expect(result.attempts_count).to eq(1)
    end

    it "sets tool calls" do
      tool_calls = [
        { "id" => "call_abc", "name" => "search", "arguments" => { "query" => "test" } },
        { "id" => "call_def", "name" => "calculate", "arguments" => { "x" => 10 } }
      ]
      result = described_class.new(
        content: "test",
        tool_calls: tool_calls,
        tool_calls_count: 2
      )

      expect(result.tool_calls).to eq(tool_calls)
      expect(result.tool_calls_count).to eq(2)
    end

    it "defaults tool_calls to empty array" do
      result = described_class.new(content: "test")
      expect(result.tool_calls).to eq([])
    end

    it "defaults tool_calls_count to 0" do
      result = described_class.new(content: "test")
      expect(result.tool_calls_count).to eq(0)
    end

    it "sets chosen_model_id to model_id if not provided" do
      result = described_class.new(content: "test", model_id: "gpt-4o")
      expect(result.chosen_model_id).to eq("gpt-4o")
    end
  end

  describe "#total_tokens" do
    it "returns sum of input and output tokens" do
      result = described_class.new(
        content: "test",
        input_tokens: 100,
        output_tokens: 50
      )

      expect(result.total_tokens).to eq(150)
    end

    it "handles nil input_tokens" do
      result = described_class.new(content: "test", output_tokens: 50)
      expect(result.total_tokens).to eq(50)
    end

    it "handles nil output_tokens" do
      result = described_class.new(content: "test", input_tokens: 100)
      expect(result.total_tokens).to eq(100)
    end

    it "returns 0 when both are nil" do
      result = described_class.new(content: "test")
      expect(result.total_tokens).to eq(0)
    end
  end

  describe "#streaming?" do
    it "returns true when streaming is true" do
      result = described_class.new(content: "test", streaming: true)
      expect(result.streaming?).to be true
    end

    it "returns false when streaming is false" do
      result = described_class.new(content: "test", streaming: false)
      expect(result.streaming?).to be false
    end

    it "returns false by default" do
      result = described_class.new(content: "test")
      expect(result.streaming?).to be false
    end
  end

  describe "#success?" do
    it "returns true when error_class is nil" do
      result = described_class.new(content: "test")
      expect(result.success?).to be true
    end

    it "returns false when error_class is set" do
      result = described_class.new(content: "test", error_class: "StandardError")
      expect(result.success?).to be false
    end
  end

  describe "#error?" do
    it "returns false when error_class is nil" do
      result = described_class.new(content: "test")
      expect(result.error?).to be false
    end

    it "returns true when error_class is set" do
      result = described_class.new(content: "test", error_class: "StandardError")
      expect(result.error?).to be true
    end
  end

  describe "#used_fallback?" do
    it "returns false when chosen_model_id equals model_id" do
      result = described_class.new(
        content: "test",
        model_id: "gpt-4o",
        chosen_model_id: "gpt-4o"
      )
      expect(result.used_fallback?).to be false
    end

    it "returns true when chosen_model_id differs from model_id" do
      result = described_class.new(
        content: "test",
        model_id: "gpt-4o",
        chosen_model_id: "gpt-4o-mini"
      )
      expect(result.used_fallback?).to be true
    end

    it "returns false when chosen_model_id is nil" do
      result = described_class.new(content: "test", model_id: "gpt-4o")
      expect(result.used_fallback?).to be false
    end
  end

  describe "#truncated?" do
    it "returns true when finish_reason is length" do
      result = described_class.new(content: "test", finish_reason: "length")
      expect(result.truncated?).to be true
    end

    it "returns false for other finish reasons" do
      result = described_class.new(content: "test", finish_reason: "stop")
      expect(result.truncated?).to be false
    end

    it "returns false when finish_reason is nil" do
      result = described_class.new(content: "test")
      expect(result.truncated?).to be false
    end
  end

  describe "#has_tool_calls?" do
    it "returns true when tool_calls_count > 0" do
      result = described_class.new(content: "test", tool_calls_count: 2)
      expect(result.has_tool_calls?).to be true
    end

    it "returns false when tool_calls_count is 0" do
      result = described_class.new(content: "test", tool_calls_count: 0)
      expect(result.has_tool_calls?).to be false
    end

    it "returns false when tool_calls_count is nil" do
      result = described_class.new(content: "test")
      expect(result.has_tool_calls?).to be false
    end
  end

  describe "#to_h" do
    it "returns all attributes as a hash" do
      tool_calls = [{ "id" => "call_abc", "name" => "search", "arguments" => {} }]

      result = described_class.new(
        content: { key: "value" },
        input_tokens: 100,
        output_tokens: 50,
        model_id: "gpt-4o",
        duration_ms: 1000,
        tool_calls: tool_calls,
        tool_calls_count: 1
      )

      hash = result.to_h

      expect(hash[:content]).to eq({ key: "value" })
      expect(hash[:input_tokens]).to eq(100)
      expect(hash[:output_tokens]).to eq(50)
      expect(hash[:total_tokens]).to eq(150)
      expect(hash[:model_id]).to eq("gpt-4o")
      expect(hash[:duration_ms]).to eq(1000)
      expect(hash[:tool_calls]).to eq(tool_calls)
      expect(hash[:tool_calls_count]).to eq(1)
    end
  end

  describe "backward compatibility delegations" do
    let(:result) do
      described_class.new(
        content: { key: "value", nested: { deep: "data" } }
      )
    end

    it "delegates [] to content" do
      expect(result[:key]).to eq("value")
    end

    it "delegates dig to content" do
      expect(result.dig(:nested, :deep)).to eq("data")
    end

    it "delegates keys to content" do
      expect(result.keys).to eq([:key, :nested])
    end

    it "delegates values to content" do
      expect(result.values).to eq(["value", { deep: "data" }])
    end

    it "delegates each to content" do
      pairs = []
      result.each { |k, v| pairs << [k, v] }
      expect(pairs).to eq([[:key, "value"], [:nested, { deep: "data" }]])
    end

    it "delegates map to content" do
      keys = result.map { |k, _v| k }
      expect(keys).to eq([:key, :nested])
    end

    it "handles nil content gracefully" do
      result = described_class.new(content: nil)
      expect(result[:key]).to be_nil
    end
  end

  describe "#to_json" do
    it "returns content as JSON" do
      result = described_class.new(content: { key: "value" })
      expect(result.to_json).to eq('{"key":"value"}')
    end
  end

  describe "#has_thinking?" do
    it "returns true when thinking_text is present" do
      result = described_class.new(
        content: "test",
        thinking_text: "Let me think about this..."
      )
      expect(result.has_thinking?).to be true
    end

    it "returns false when thinking_text is nil" do
      result = described_class.new(content: "test", thinking_text: nil)
      expect(result.has_thinking?).to be false
    end

    it "returns false when thinking_text is empty" do
      result = described_class.new(content: "test", thinking_text: "")
      expect(result.has_thinking?).to be false
    end

    it "returns false by default" do
      result = described_class.new(content: "test")
      expect(result.has_thinking?).to be false
    end
  end

  describe "thinking attributes" do
    it "sets thinking_text" do
      result = described_class.new(
        content: "test",
        thinking_text: "reasoning content"
      )
      expect(result.thinking_text).to eq("reasoning content")
    end

    it "sets thinking_signature" do
      result = described_class.new(
        content: "test",
        thinking_signature: "sig_abc123"
      )
      expect(result.thinking_signature).to eq("sig_abc123")
    end

    it "sets thinking_tokens" do
      result = described_class.new(
        content: "test",
        thinking_tokens: 500
      )
      expect(result.thinking_tokens).to eq(500)
    end
  end

  describe "#to_h with thinking data" do
    it "includes thinking fields in hash" do
      result = described_class.new(
        content: "test",
        thinking_text: "Let me reason...",
        thinking_signature: "sig_123",
        thinking_tokens: 200
      )

      hash = result.to_h

      expect(hash[:thinking_text]).to eq("Let me reason...")
      expect(hash[:thinking_signature]).to eq("sig_123")
      expect(hash[:thinking_tokens]).to eq(200)
    end
  end
end
