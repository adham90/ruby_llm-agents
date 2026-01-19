# frozen_string_literal: true

require "rails_helper"

RSpec.describe RubyLLM::Agents::EmbeddingResult do
  describe "#initialize" do
    it "sets vectors" do
      result = described_class.new(vectors: [[0.1, 0.2], [0.3, 0.4]])
      expect(result.vectors).to eq([[0.1, 0.2], [0.3, 0.4]])
    end

    it "sets model_id" do
      result = described_class.new(model_id: "text-embedding-3-small")
      expect(result.model_id).to eq("text-embedding-3-small")
    end

    it "sets dimensions" do
      result = described_class.new(dimensions: 1536)
      expect(result.dimensions).to eq(1536)
    end

    it "sets input_tokens" do
      result = described_class.new(input_tokens: 100)
      expect(result.input_tokens).to eq(100)
    end

    it "sets total_cost" do
      result = described_class.new(total_cost: 0.00002)
      expect(result.total_cost).to eq(0.00002)
    end

    it "sets duration_ms" do
      result = described_class.new(duration_ms: 500)
      expect(result.duration_ms).to eq(500)
    end

    it "calculates count from vectors if not provided" do
      result = described_class.new(vectors: [[0.1], [0.2], [0.3]])
      expect(result.count).to eq(3)
    end

    it "uses provided count over calculated" do
      result = described_class.new(vectors: [[0.1], [0.2]], count: 5)
      expect(result.count).to eq(5)
    end

    it "sets timing info" do
      started = Time.current
      completed = started + 1.second

      result = described_class.new(
        started_at: started,
        completed_at: completed
      )

      expect(result.started_at).to eq(started)
      expect(result.completed_at).to eq(completed)
    end

    it "sets tenant_id" do
      result = described_class.new(tenant_id: "tenant-123")
      expect(result.tenant_id).to eq("tenant-123")
    end

    it "sets error info" do
      result = described_class.new(
        error_class: "ArgumentError",
        error_message: "Invalid input"
      )

      expect(result.error_class).to eq("ArgumentError")
      expect(result.error_message).to eq("Invalid input")
    end
  end

  describe "#single?" do
    it "returns true when count is 1" do
      result = described_class.new(vectors: [[0.1, 0.2]], count: 1)
      expect(result.single?).to be true
    end

    it "returns false when count is greater than 1" do
      result = described_class.new(vectors: [[0.1], [0.2]], count: 2)
      expect(result.single?).to be false
    end
  end

  describe "#batch?" do
    it "returns true when count is greater than 1" do
      result = described_class.new(vectors: [[0.1], [0.2]], count: 2)
      expect(result.batch?).to be true
    end

    it "returns false when count is 1" do
      result = described_class.new(vectors: [[0.1]], count: 1)
      expect(result.batch?).to be false
    end
  end

  describe "#vector" do
    it "returns the first vector" do
      result = described_class.new(vectors: [[0.1, 0.2], [0.3, 0.4]])
      expect(result.vector).to eq([0.1, 0.2])
    end

    it "returns nil for empty vectors" do
      result = described_class.new(vectors: [])
      expect(result.vector).to be_nil
    end
  end

  describe "#success?" do
    it "returns true when no error" do
      result = described_class.new(vectors: [[0.1]])
      expect(result.success?).to be true
    end

    it "returns false when error_class is set" do
      result = described_class.new(error_class: "StandardError")
      expect(result.success?).to be false
    end
  end

  describe "#error?" do
    it "returns false when no error" do
      result = described_class.new(vectors: [[0.1]])
      expect(result.error?).to be false
    end

    it "returns true when error_class is set" do
      result = described_class.new(error_class: "StandardError")
      expect(result.error?).to be true
    end
  end

  describe "#similarity" do
    it "calculates cosine similarity between two results" do
      result1 = described_class.new(vectors: [[1.0, 0.0, 0.0]])
      result2 = described_class.new(vectors: [[1.0, 0.0, 0.0]])

      expect(result1.similarity(result2)).to eq(1.0)
    end

    it "calculates cosine similarity with raw vector" do
      result = described_class.new(vectors: [[1.0, 0.0, 0.0]])
      other = [1.0, 0.0, 0.0]

      expect(result.similarity(other)).to eq(1.0)
    end

    it "returns 0 for orthogonal vectors" do
      result1 = described_class.new(vectors: [[1.0, 0.0, 0.0]])
      result2 = described_class.new(vectors: [[0.0, 1.0, 0.0]])

      expect(result1.similarity(result2)).to eq(0.0)
    end

    it "returns approximately -1 for opposite vectors" do
      result1 = described_class.new(vectors: [[1.0, 0.0, 0.0]])
      result2 = described_class.new(vectors: [[-1.0, 0.0, 0.0]])

      expect(result1.similarity(result2)).to be_within(0.001).of(-1.0)
    end

    it "uses index parameter for batch results" do
      result = described_class.new(vectors: [[1.0, 0.0], [0.0, 1.0]])
      other = [0.0, 1.0]

      expect(result.similarity(other, index: 1)).to eq(1.0)
    end

    it "returns nil for invalid index" do
      result = described_class.new(vectors: [[1.0, 0.0]])
      expect(result.similarity([1.0, 0.0], index: 5)).to be_nil
    end

    it "raises ArgumentError for invalid other type" do
      result = described_class.new(vectors: [[1.0, 0.0]])
      expect { result.similarity("invalid") }.to raise_error(ArgumentError)
    end
  end

  describe "#most_similar" do
    it "returns sorted similar vectors" do
      query = described_class.new(vectors: [[1.0, 0.0, 0.0]])
      others = [
        [0.0, 1.0, 0.0],  # orthogonal
        [0.9, 0.1, 0.0],  # similar
        [1.0, 0.0, 0.0]   # identical
      ]

      results = query.most_similar(others, limit: 3)

      expect(results.size).to eq(3)
      expect(results[0][:index]).to eq(2) # identical first
      expect(results[1][:index]).to eq(1) # similar second
      expect(results[2][:index]).to eq(0) # orthogonal last
    end

    it "respects limit parameter" do
      query = described_class.new(vectors: [[1.0, 0.0]])
      others = [[0.1, 0.9], [0.5, 0.5], [0.9, 0.1]]

      results = query.most_similar(others, limit: 2)
      expect(results.size).to eq(2)
    end

    it "handles EmbeddingResult objects in others" do
      query = described_class.new(vectors: [[1.0, 0.0]])
      others = [
        described_class.new(vectors: [[0.0, 1.0]]),
        described_class.new(vectors: [[1.0, 0.0]])
      ]

      results = query.most_similar(others, limit: 2)
      expect(results[0][:index]).to eq(1) # identical
    end
  end

  describe "#to_h" do
    it "returns all attributes as hash" do
      started = Time.current
      completed = started + 1.second

      result = described_class.new(
        vectors: [[0.1, 0.2]],
        model_id: "text-embedding-3-small",
        dimensions: 2,
        input_tokens: 10,
        total_cost: 0.00001,
        duration_ms: 100,
        count: 1,
        started_at: started,
        completed_at: completed,
        tenant_id: "tenant-123"
      )

      hash = result.to_h

      expect(hash[:vectors]).to eq([[0.1, 0.2]])
      expect(hash[:model_id]).to eq("text-embedding-3-small")
      expect(hash[:dimensions]).to eq(2)
      expect(hash[:input_tokens]).to eq(10)
      expect(hash[:total_cost]).to eq(0.00001)
      expect(hash[:duration_ms]).to eq(100)
      expect(hash[:count]).to eq(1)
      expect(hash[:started_at]).to eq(started)
      expect(hash[:completed_at]).to eq(completed)
      expect(hash[:tenant_id]).to eq("tenant-123")
    end
  end
end
