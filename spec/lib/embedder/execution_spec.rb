# frozen_string_literal: true

require "rails_helper"

RSpec.describe RubyLLM::Agents::Embedder::Execution do
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

  let(:test_embedder) do
    Class.new(RubyLLM::Agents::Embedder) do
      model "text-embedding-3-small"
    end
  end

  before do
    # Disable tracking for most tests
    allow(RubyLLM::Agents.configuration).to receive(:track_embeddings).and_return(false)
  end

  describe "#call" do
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
        Class.new(RubyLLM::Agents::Embedder) do
          model "text-embedding-3-small"
          batch_size 2
        end
      end

      it "splits into batches based on batch_size" do
        batch1_response = double(vectors: [[0.1], [0.2]], input_tokens: 4, model: "test")
        batch2_response = double(vectors: [[0.3]], input_tokens: 2, model: "test")

        expect(RubyLLM).to receive(:embed).twice.and_return(batch1_response, batch2_response)

        result = embedder_with_small_batch.call(texts: ["A", "B", "C"])

        expect(result.vectors).to eq([[0.1], [0.2], [0.3]])
        expect(result.input_tokens).to eq(6)
      end

      it "calls progress block for each batch" do
        batch1_response = double(vectors: [[0.1], [0.2]], input_tokens: 4, model: "test")
        batch2_response = double(vectors: [[0.3]], input_tokens: 2, model: "test")

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
      it "passes dimensions to RubyLLM.embed" do
        embedder_with_dims = Class.new(RubyLLM::Agents::Embedder) do
          model "text-embedding-3-small"
          dimensions 512
        end

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
        Class.new(RubyLLM::Agents::Embedder) do
          model "text-embedding-3-small"

          def preprocess(text)
            text.strip.downcase
          end
        end
      end

      it "applies preprocessing before embedding" do
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
      allow(mock_response).to receive(:respond_to?).with(:input_cost).and_return(false)
      allow(RubyLLM).to receive(:embed).and_return(mock_response)

      result = test_embedder.call(text: "Hello")

      # 5 tokens * $0.02/million = $0.0000001
      expect(result.total_cost).to be > 0
    end
  end
end
