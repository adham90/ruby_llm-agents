# frozen_string_literal: true

require "rails_helper"

RSpec.describe RubyLLM::Agents::Pipeline::Context do
  # Mock agent class for testing
  let(:agent_class) do
    Class.new do
      def self.name
        "TestEmbedder"
      end

      def self.agent_type
        :embedding
      end

      def self.model
        "text-embedding-3-small"
      end
    end
  end

  describe "#initialize" do
    it "sets input and agent_class" do
      context = described_class.new(input: "hello", agent_class: agent_class)

      expect(context.input).to eq("hello")
      expect(context.agent_class).to eq(agent_class)
    end

    it "extracts agent_type from agent class" do
      context = described_class.new(input: "hello", agent_class: agent_class)

      expect(context.agent_type).to eq(:embedding)
    end

    it "extracts model from agent class when not provided" do
      context = described_class.new(input: "hello", agent_class: agent_class)

      expect(context.model).to eq("text-embedding-3-small")
    end

    it "allows model override" do
      context = described_class.new(
        input: "hello",
        agent_class: agent_class,
        model: "text-embedding-3-large"
      )

      expect(context.model).to eq("text-embedding-3-large")
    end

    it "stores additional options" do
      context = described_class.new(
        input: "hello",
        agent_class: agent_class,
        tenant: { id: "t1" },
        custom_option: "value"
      )

      expect(context.options[:tenant]).to eq({ id: "t1" })
      expect(context.options[:custom_option]).to eq("value")
    end

    it "initializes tracking fields" do
      context = described_class.new(input: "hello", agent_class: agent_class)

      expect(context.attempt).to eq(0)
      expect(context.attempts_made).to eq(0)
      expect(context.cached).to eq(false)
      expect(context.input_tokens).to eq(0)
      expect(context.output_tokens).to eq(0)
      expect(context.total_cost).to eq(0.0)
    end
  end

  describe "#duration_ms" do
    it "returns nil when not started" do
      context = described_class.new(input: "hello", agent_class: agent_class)

      expect(context.duration_ms).to be_nil
    end

    it "returns nil when not completed" do
      context = described_class.new(input: "hello", agent_class: agent_class)
      context.started_at = Time.current

      expect(context.duration_ms).to be_nil
    end

    it "calculates duration when completed" do
      context = described_class.new(input: "hello", agent_class: agent_class)
      context.started_at = Time.current
      context.completed_at = context.started_at + 1.5.seconds

      expect(context.duration_ms).to eq(1500)
    end
  end

  describe "#cached?" do
    it "returns false by default" do
      context = described_class.new(input: "hello", agent_class: agent_class)

      expect(context.cached?).to be false
    end

    it "returns true when cached is set" do
      context = described_class.new(input: "hello", agent_class: agent_class)
      context.cached = true

      expect(context.cached?).to be true
    end
  end

  describe "#success?" do
    it "returns false when output is nil" do
      context = described_class.new(input: "hello", agent_class: agent_class)

      expect(context.success?).to be false
    end

    it "returns false when error is set" do
      context = described_class.new(input: "hello", agent_class: agent_class)
      context.output = "result"
      context.error = StandardError.new("boom")

      expect(context.success?).to be false
    end

    it "returns true when output is set and no error" do
      context = described_class.new(input: "hello", agent_class: agent_class)
      context.output = "result"

      expect(context.success?).to be true
    end
  end

  describe "#failed?" do
    it "returns false when no error" do
      context = described_class.new(input: "hello", agent_class: agent_class)

      expect(context.failed?).to be false
    end

    it "returns true when error is set" do
      context = described_class.new(input: "hello", agent_class: agent_class)
      context.error = StandardError.new("boom")

      expect(context.failed?).to be true
    end
  end

  describe "#total_tokens" do
    it "returns sum of input and output tokens" do
      context = described_class.new(input: "hello", agent_class: agent_class)
      context.input_tokens = 100
      context.output_tokens = 50

      expect(context.total_tokens).to eq(150)
    end
  end

  describe "metadata access" do
    it "allows storing and retrieving metadata" do
      context = described_class.new(input: "hello", agent_class: agent_class)

      context[:custom_key] = "custom_value"

      expect(context[:custom_key]).to eq("custom_value")
    end

    it "returns metadata hash" do
      context = described_class.new(input: "hello", agent_class: agent_class)
      context[:key1] = "value1"
      context[:key2] = "value2"

      expect(context.metadata).to eq({ key1: "value1", key2: "value2" })
    end
  end

  describe "#to_h" do
    it "returns hash representation" do
      context = described_class.new(input: "hello", agent_class: agent_class)
      context.started_at = Time.current
      context.completed_at = context.started_at + 1.second
      context.output = "result"
      context.input_tokens = 10
      context.total_cost = 0.001

      hash = context.to_h

      expect(hash[:agent_class]).to eq("TestEmbedder")
      expect(hash[:agent_type]).to eq(:embedding)
      expect(hash[:model]).to eq("text-embedding-3-small")
      expect(hash[:duration_ms]).to eq(1000)
      expect(hash[:success]).to be true
      expect(hash[:input_tokens]).to eq(10)
      expect(hash[:total_cost]).to eq(0.001)
    end

    it "includes error details when present" do
      context = described_class.new(input: "hello", agent_class: agent_class)
      context.error = ArgumentError.new("bad input")

      hash = context.to_h

      expect(hash[:error_class]).to eq("ArgumentError")
      expect(hash[:error_message]).to eq("bad input")
    end
  end

  describe "#dup_for_retry" do
    it "creates a new context with same input" do
      context = described_class.new(
        input: "hello",
        agent_class: agent_class,
        model: "custom-model"
      )
      context.tenant_id = "t1"
      context.started_at = Time.current
      context.attempts_made = 2

      new_context = context.dup_for_retry

      expect(new_context.input).to eq("hello")
      expect(new_context.agent_class).to eq(agent_class)
      expect(new_context.model).to eq("custom-model")
      expect(new_context.tenant_id).to eq("t1")
      expect(new_context.started_at).to eq(context.started_at)
      expect(new_context.attempts_made).to eq(2)
    end

    it "does not copy output or error" do
      context = described_class.new(input: "hello", agent_class: agent_class)
      context.output = "old result"
      context.error = StandardError.new("old error")

      new_context = context.dup_for_retry

      expect(new_context.output).to be_nil
      expect(new_context.error).to be_nil
    end
  end

  describe "agent type inference" do
    it "infers :embedding from class name" do
      embedder_class = Class.new do
        def self.name
          "MyEmbedder"
        end
      end

      context = described_class.new(input: "hello", agent_class: embedder_class)
      expect(context.agent_type).to eq(:embedding)
    end

    it "infers :image from class name" do
      generator_class = Class.new do
        def self.name
          "ImageGenerator"
        end
      end

      context = described_class.new(input: "hello", agent_class: generator_class)
      expect(context.agent_type).to eq(:image)
    end

    it "infers :audio from transcriber class name" do
      transcriber_class = Class.new do
        def self.name
          "AudioTranscriber"
        end
      end

      context = described_class.new(input: "hello", agent_class: transcriber_class)
      expect(context.agent_type).to eq(:audio)
    end

    it "defaults to :conversation for unknown names" do
      generic_class = Class.new do
        def self.name
          "MyCustomAgent"
        end
      end

      context = described_class.new(input: "hello", agent_class: generic_class)
      expect(context.agent_type).to eq(:conversation)
    end
  end
end
