# frozen_string_literal: true

require "rails_helper"

RSpec.describe RubyLLM::Agents::Workflow::WorkflowContext do
  describe "#initialize" do
    it "stores initial params" do
      ctx = described_class.new(topic: "AI", depth: 3)

      expect(ctx[:topic]).to eq("AI")
      expect(ctx[:depth]).to eq(3)
      expect(ctx.params).to eq({topic: "AI", depth: 3})
    end

    it "starts with empty step_results and errors" do
      ctx = described_class.new
      expect(ctx.step_results).to eq({})
      expect(ctx.errors).to eq({})
    end
  end

  describe "#[] and #[]=" do
    it "reads and writes values" do
      ctx = described_class.new
      ctx[:key] = "value"
      expect(ctx[:key]).to eq("value")
    end

    it "converts string keys to symbols" do
      ctx = described_class.new
      ctx["key"] = "value"
      expect(ctx[:key]).to eq("value")
    end
  end

  describe "#fetch" do
    it "returns value for existing key" do
      ctx = described_class.new(a: 1)
      expect(ctx.fetch(:a)).to eq(1)
    end

    it "returns default for missing key" do
      ctx = described_class.new
      expect(ctx.fetch(:missing, "default")).to eq("default")
    end
  end

  describe "#store_step_result" do
    it "stores result accessible via step_result and []" do
      ctx = described_class.new
      result = double("result")

      ctx.store_step_result(:draft, result)

      expect(ctx.step_result(:draft)).to eq(result)
      expect(ctx[:draft]).to eq(result)
    end
  end

  describe "#store_error" do
    it "records an error for a step" do
      ctx = described_class.new
      error = StandardError.new("boom")

      ctx.store_error(:draft, error)

      expect(ctx.errors[:draft]).to eq(error)
    end
  end

  describe "#step_completed?" do
    it "returns true for completed steps" do
      ctx = described_class.new
      ctx.store_step_result(:draft, "done")

      expect(ctx.step_completed?(:draft)).to be true
      expect(ctx.step_completed?(:edit)).to be false
    end
  end

  describe "#to_h" do
    it "returns a snapshot of all data" do
      ctx = described_class.new(topic: "AI")
      ctx[:extra] = "data"

      hash = ctx.to_h
      expect(hash[:topic]).to eq("AI")
      expect(hash[:extra]).to eq("data")
    end

    it "returns a copy (not a reference)" do
      ctx = described_class.new(topic: "AI")
      hash = ctx.to_h
      hash[:topic] = "changed"

      expect(ctx[:topic]).to eq("AI")
    end
  end

  describe "#completed_step_count" do
    it "counts completed steps" do
      ctx = described_class.new
      expect(ctx.completed_step_count).to eq(0)

      ctx.store_step_result(:a, "done")
      ctx.store_step_result(:b, "done")
      expect(ctx.completed_step_count).to eq(2)
    end
  end

  describe "thread safety" do
    it "handles concurrent writes without errors" do
      ctx = described_class.new

      threads = 10.times.map do |i|
        Thread.new { ctx[:"key_#{i}"] = i }
      end
      threads.each(&:join)

      10.times do |i|
        expect(ctx[:"key_#{i}"]).to eq(i)
      end
    end
  end
end
