# frozen_string_literal: true

require "rails_helper"

RSpec.describe RubyLLM::Agents::Embedder do
  let(:config) { double("config") }

  before do
    allow(RubyLLM::Agents).to receive(:configuration).and_return(config)
    allow(config).to receive(:default_model).and_return("gpt-4o")
    allow(config).to receive(:default_embedding_model).and_return("text-embedding-3-small")
    allow(config).to receive(:default_embedding_dimensions).and_return(nil)
    allow(config).to receive(:default_embedding_batch_size).and_return(100)
    allow(config).to receive(:default_timeout).and_return(120)
    allow(config).to receive(:default_temperature).and_return(0.7)
    allow(config).to receive(:default_streaming).and_return(false)
    allow(config).to receive(:budgets_enabled?).and_return(false)
    allow(config).to receive(:track_embeddings).and_return(false)
    allow(config).to receive(:track_executions).and_return(false)
    allow(config).to receive(:track_image_generation).and_return(false)
    allow(config).to receive(:track_audio).and_return(false)
    allow(config).to receive(:track_moderation).and_return(false)
  end

  # Mock RubyLLM.embed response
  let(:mock_response) do
    double(
      "EmbeddingResponse",
      vectors: [[0.1, 0.2, 0.3]],
      input_tokens: 5,
      model: "text-embedding-3-small"
    )
  end

  let(:mock_batch_response) do
    double(
      "EmbeddingResponse",
      vectors: [[0.1, 0.2], [0.3, 0.4], [0.5, 0.6]],
      input_tokens: 15,
      model: "text-embedding-3-small"
    )
  end

  describe ".agent_type" do
    it "returns :embedding" do
      expect(described_class.agent_type).to eq(:embedding)
    end
  end

  describe "DSL" do
    let(:base_embedder) do
      Class.new(described_class) do
        def self.name
          "TestEmbedder"
        end
      end
    end

    describe ".model" do
      it "sets and returns the model" do
        base_embedder.model "text-embedding-3-large"
        expect(base_embedder.model).to eq("text-embedding-3-large")
      end

      it "returns default when not set" do
        expect(base_embedder.model).to eq("text-embedding-3-small")
      end

      it "inherits from parent class" do
        base_embedder.model "text-embedding-3-large"
        child = Class.new(base_embedder) do
          def self.name
            "ChildEmbedder"
          end
        end
        expect(child.model).to eq("text-embedding-3-large")
      end
    end

    describe ".dimensions" do
      it "sets and returns dimensions" do
        base_embedder.dimensions 512
        expect(base_embedder.dimensions).to eq(512)
      end

      it "returns nil when not set (use model default)" do
        expect(base_embedder.dimensions).to be_nil
      end

      it "inherits from parent class" do
        base_embedder.dimensions 256
        child = Class.new(base_embedder) do
          def self.name
            "ChildEmbedder"
          end
        end
        expect(child.dimensions).to eq(256)
      end
    end

    describe ".batch_size" do
      it "sets and returns batch_size" do
        base_embedder.batch_size 50
        expect(base_embedder.batch_size).to eq(50)
      end

      it "returns default when not set" do
        expect(base_embedder.batch_size).to eq(100)
      end

      it "inherits from parent class" do
        base_embedder.batch_size 25
        child = Class.new(base_embedder) do
          def self.name
            "ChildEmbedder"
          end
        end
        expect(child.batch_size).to eq(25)
      end
    end

    describe ".description" do
      it "sets and returns description" do
        base_embedder.description "Embeds documents for search"
        expect(base_embedder.description).to eq("Embeds documents for search")
      end

      it "returns nil when not set" do
        expect(base_embedder.description).to be_nil
      end
    end

    describe ".cache_for" do
      it "enables caching with TTL" do
        base_embedder.cache_for 1.week
        expect(base_embedder.cache_enabled?).to be true
        expect(base_embedder.cache_ttl).to eq(1.week)
      end
    end

    describe ".cache_enabled?" do
      it "returns false by default" do
        expect(base_embedder.cache_enabled?).to be false
      end

      it "returns true after cache_for is called" do
        base_embedder.cache_for 1.hour
        expect(base_embedder.cache_enabled?).to be true
      end
    end

    describe ".cache_ttl" do
      it "returns default TTL when not set" do
        expect(base_embedder.cache_ttl).to eq(1.hour)
      end

      it "returns configured TTL" do
        base_embedder.cache_for 1.day
        expect(base_embedder.cache_ttl).to eq(1.day)
      end
    end

    describe "DSL inheritance" do
      it "allows child classes to override parent settings" do
        base_embedder.model "text-embedding-3-small"
        base_embedder.dimensions 1536

        child = Class.new(base_embedder) do
          def self.name
            "ChildEmbedder"
          end

          model "text-embedding-3-large"
          # dimensions not overridden
        end

        expect(child.model).to eq("text-embedding-3-large")
        expect(child.dimensions).to eq(1536)
      end
    end
  end

  describe "#call" do
    let(:test_embedder) do
      Class.new(described_class) do
        def self.name
          "TestEmbedder"
        end

        model "text-embedding-3-small"
      end
    end

    before do
      allow(mock_response).to receive(:respond_to?).with(:input_cost).and_return(false)
    end

    context "with single text" do
      it "returns an EmbeddingResult" do
        allow(RubyLLM).to receive(:embed).and_return(mock_response)

        result = test_embedder.call(text: "Hello world")

        expect(result).to be_a(RubyLLM::Agents::EmbeddingResult)
      end

      it "passes text to RubyLLM.embed" do
        expect(RubyLLM).to receive(:embed)
          .with(["Hello world"], hash_including(model: "text-embedding-3-small"))
          .and_return(mock_response)

        test_embedder.call(text: "Hello world")
      end

      it "returns correct vectors" do
        allow(RubyLLM).to receive(:embed).and_return(mock_response)

        result = test_embedder.call(text: "Hello")
        expect(result.vector).to eq([0.1, 0.2, 0.3])
      end

      it "returns single result" do
        allow(RubyLLM).to receive(:embed).and_return(mock_response)

        result = test_embedder.call(text: "Hello")
        expect(result.single?).to be true
        expect(result.count).to eq(1)
      end
    end

    context "with multiple texts" do
      before do
        allow(mock_batch_response).to receive(:respond_to?).with(:input_cost).and_return(false)
      end

      it "returns batch result" do
        allow(RubyLLM).to receive(:embed).and_return(mock_batch_response)

        result = test_embedder.call(texts: ["Hello", "World", "Test"])

        expect(result.batch?).to be true
        expect(result.count).to eq(3)
        expect(result.vectors.size).to eq(3)
      end

      it "aggregates input tokens" do
        allow(RubyLLM).to receive(:embed).and_return(mock_batch_response)

        result = test_embedder.call(texts: ["Hello", "World", "Test"])

        expect(result.input_tokens).to eq(15)
      end
    end

    context "with batch processing" do
      let(:embedder_with_small_batch) do
        Class.new(described_class) do
          def self.name
            "SmallBatchEmbedder"
          end

          model "text-embedding-3-small"
          batch_size 2
        end
      end

      it "splits into batches based on batch_size" do
        batch1_response = double(vectors: [[0.1], [0.2]], input_tokens: 4, model: "test")
        batch2_response = double(vectors: [[0.3]], input_tokens: 2, model: "test")
        allow(batch1_response).to receive(:respond_to?).with(:input_cost).and_return(false)
        allow(batch2_response).to receive(:respond_to?).with(:input_cost).and_return(false)

        expect(RubyLLM).to receive(:embed).twice.and_return(batch1_response, batch2_response)

        result = embedder_with_small_batch.call(texts: ["A", "B", "C"])

        expect(result.vectors).to eq([[0.1], [0.2], [0.3]])
        expect(result.input_tokens).to eq(6)
      end

      it "calls progress block for each batch" do
        batch1_response = double(vectors: [[0.1], [0.2]], input_tokens: 4, model: "test")
        batch2_response = double(vectors: [[0.3]], input_tokens: 2, model: "test")
        allow(batch1_response).to receive(:respond_to?).with(:input_cost).and_return(false)
        allow(batch2_response).to receive(:respond_to?).with(:input_cost).and_return(false)

        allow(RubyLLM).to receive(:embed).and_return(batch1_response, batch2_response)

        batches_processed = []
        embedder_with_small_batch.call(texts: ["A", "B", "C"]) do |batch_result, index|
          batches_processed << { index: index, count: batch_result.count }
        end

        expect(batches_processed).to eq([
          { index: 0, count: 2 },
          { index: 1, count: 1 }
        ])
      end
    end

    context "with dimensions override" do
      let(:embedder_with_dims) do
        Class.new(described_class) do
          def self.name
            "DimsEmbedder"
          end

          model "text-embedding-3-small"
          dimensions 512
        end
      end

      it "passes dimensions to RubyLLM.embed" do
        expect(RubyLLM).to receive(:embed)
          .with(anything, hash_including(dimensions: 512))
          .and_return(mock_response)

        embedder_with_dims.call(text: "Hello")
      end

      it "allows runtime dimension override" do
        expect(RubyLLM).to receive(:embed)
          .with(anything, hash_including(dimensions: 256))
          .and_return(mock_response)

        test_embedder.call(text: "Hello", dimensions: 256)
      end
    end

    context "with model override" do
      it "allows runtime model override" do
        expect(RubyLLM).to receive(:embed)
          .with(anything, hash_including(model: "text-embedding-3-large"))
          .and_return(mock_response)

        test_embedder.call(text: "Hello", model: "text-embedding-3-large")
      end
    end

    context "with preprocessing" do
      let(:preprocessing_embedder) do
        Class.new(described_class) do
          def self.name
            "PreprocessingEmbedder"
          end

          model "text-embedding-3-small"

          def preprocess(text)
            text.strip.downcase
          end
        end
      end

      it "applies preprocessing before embedding" do
        allow(mock_response).to receive(:respond_to?).with(:input_cost).and_return(false)
        expect(RubyLLM).to receive(:embed)
          .with(["hello world"], anything)
          .and_return(mock_response)

        preprocessing_embedder.call(text: "  Hello World  ")
      end
    end

    context "timing" do
      it "tracks duration" do
        allow(RubyLLM).to receive(:embed).and_return(mock_response)

        result = test_embedder.call(text: "Hello")

        expect(result.duration_ms).to be >= 0
        expect(result.started_at).to be_present
        expect(result.completed_at).to be_present
      end
    end

    context "validation" do
      it "raises error when both text and texts provided" do
        expect {
          test_embedder.call(text: "Hello", texts: ["World"])
        }.to raise_error(ArgumentError, /Provide either text: or texts:, not both/)
      end

      it "raises error when neither text nor texts provided" do
        expect {
          test_embedder.call
        }.to raise_error(ArgumentError, /Provide either text: or texts:/)
      end

      it "raises error for empty texts array" do
        expect {
          test_embedder.call(texts: [])
        }.to raise_error(ArgumentError, /texts cannot be empty/)
      end

      it "raises error for non-string in texts" do
        expect {
          test_embedder.call(texts: ["valid", 123])
        }.to raise_error(ArgumentError, /texts\[1\] must be a String/)
      end

      it "raises error for empty string in texts" do
        expect {
          test_embedder.call(texts: ["valid", ""])
        }.to raise_error(ArgumentError, /texts\[1\] cannot be empty/)
      end
    end
  end

  describe "cost calculation" do
    let(:test_embedder) do
      Class.new(described_class) do
        def self.name
          "CostEmbedder"
        end

        model "text-embedding-3-small"
      end
    end

    it "uses response cost if available" do
      response_with_cost = double(
        vectors: [[0.1]],
        input_tokens: 100,
        model: "text-embedding-3-small",
        input_cost: 0.05
      )
      allow(response_with_cost).to receive(:respond_to?).with(:input_cost).and_return(true)
      allow(RubyLLM).to receive(:embed).and_return(response_with_cost)

      result = test_embedder.call(text: "Hello")

      expect(result.total_cost).to eq(0.05)
    end

    it "estimates cost based on tokens and model" do
      mock_response = double(
        vectors: [[0.1]],
        input_tokens: 5,
        model: "text-embedding-3-small"
      )
      allow(mock_response).to receive(:respond_to?).with(:input_cost).and_return(false)
      allow(RubyLLM).to receive(:embed).and_return(mock_response)

      result = test_embedder.call(text: "Hello")

      # 5 tokens * $0.02/million = $0.0000001
      expect(result.total_cost).to be > 0
    end
  end

  describe "#agent_cache_key" do
    let(:test_embedder) do
      Class.new(described_class) do
        def self.name
          "CacheKeyEmbedder"
        end

        model "text-embedding-3-small"
      end
    end

    it "generates unique cache key" do
      embedder = test_embedder.new(text: "Hello world")
      key = embedder.agent_cache_key

      expect(key).to start_with("ruby_llm_agents/embedding/CacheKeyEmbedder/")
    end

    it "generates different keys for different texts" do
      embedder1 = test_embedder.new(text: "Hello")
      embedder2 = test_embedder.new(text: "World")

      expect(embedder1.agent_cache_key).not_to eq(embedder2.agent_cache_key)
    end

    it "generates same key for same text" do
      embedder1 = test_embedder.new(text: "Hello")
      embedder2 = test_embedder.new(text: "Hello")

      expect(embedder1.agent_cache_key).to eq(embedder2.agent_cache_key)
    end
  end
end
