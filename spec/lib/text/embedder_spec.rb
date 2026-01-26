# frozen_string_literal: true

require "rails_helper"

RSpec.describe RubyLLM::Agents::Embedder do
  let(:embedder_class) do
    Class.new(described_class) do
      def self.name
        "TestEmbedder"
      end
    end
  end

  before do
    RubyLLM::Agents.reset_configuration!
    RubyLLM::Agents.configure do |c|
      c.default_embedding_model = "text-embedding-3-small"
      c.default_embedding_dimensions = nil
      c.default_embedding_batch_size = 100
    end
  end

  describe ".agent_type" do
    it "returns :embedding" do
      expect(embedder_class.agent_type).to eq(:embedding)
    end
  end

  describe ".model" do
    it "sets and gets the model" do
      embedder_class.model "text-embedding-3-large"
      expect(embedder_class.model).to eq("text-embedding-3-large")
    end

    it "defaults to config default_embedding_model" do
      expect(embedder_class.model).to eq("text-embedding-3-small")
    end
  end

  describe ".dimensions" do
    it "sets and gets the dimensions" do
      embedder_class.dimensions 512
      expect(embedder_class.dimensions).to eq(512)
    end

    it "defaults to config default_embedding_dimensions" do
      expect(embedder_class.dimensions).to be_nil
    end
  end

  describe ".batch_size" do
    it "sets and gets the batch size" do
      embedder_class.batch_size 50
      expect(embedder_class.batch_size).to eq(50)
    end

    it "defaults to config default_embedding_batch_size" do
      expect(embedder_class.batch_size).to eq(100)
    end
  end

  describe "#initialize" do
    it "accepts text parameter" do
      embedder = embedder_class.new(text: "Hello world")
      expect(embedder.text).to eq("Hello world")
      expect(embedder.texts).to be_nil
    end

    it "accepts texts parameter" do
      embedder = embedder_class.new(texts: ["Hello", "World"])
      expect(embedder.texts).to eq(["Hello", "World"])
      expect(embedder.text).to be_nil
    end

    it "raises when both text and texts provided" do
      expect {
        embedder_class.new(text: "Hello", texts: ["World"]).send(:normalize_input)
      }.to raise_error(ArgumentError, /Provide either text: or texts:, not both/)
    end

    it "raises when neither text nor texts provided" do
      expect {
        embedder_class.new({}).send(:normalize_input)
      }.to raise_error(ArgumentError, /Provide either text: or texts:/)
    end
  end

  describe "#preprocess" do
    let(:embedder) { embedder_class.new(text: "test") }

    it "returns text unchanged by default" do
      expect(embedder.preprocess("Hello World")).to eq("Hello World")
    end
  end

  describe "custom preprocessing" do
    let(:custom_embedder_class) do
      Class.new(described_class) do
        def self.name
          "CustomEmbedder"
        end

        def preprocess(text)
          text.strip.downcase
        end
      end
    end

    it "applies custom preprocessing" do
      embedder = custom_embedder_class.new(text: "  HELLO WORLD  ")
      expect(embedder.preprocess("  HELLO WORLD  ")).to eq("hello world")
    end
  end

  describe "#user_prompt" do
    it "returns single text for single input" do
      embedder = embedder_class.new(text: "Hello")
      expect(embedder.user_prompt).to eq("Hello")
    end

    it "joins multiple texts for batch input" do
      embedder = embedder_class.new(texts: ["Hello", "World"])
      expect(embedder.user_prompt).to eq("Hello\n---\nWorld")
    end
  end

  describe "inheritance" do
    let(:parent_embedder) do
      Class.new(described_class) do
        def self.name
          "ParentEmbedder"
        end

        model "text-embedding-3-large"
        dimensions 1024
        batch_size 50
      end
    end

    let(:child_embedder) do
      Class.new(parent_embedder) do
        def self.name
          "ChildEmbedder"
        end
      end
    end

    it "inherits settings from parent" do
      expect(child_embedder.model).to eq("text-embedding-3-large")
      expect(child_embedder.dimensions).to eq(1024)
      expect(child_embedder.batch_size).to eq(50)
    end

    it "allows child to override parent settings" do
      child_embedder.dimensions 512
      expect(child_embedder.dimensions).to eq(512)
      expect(parent_embedder.dimensions).to eq(1024)
    end
  end

  describe "input validation" do
    it "validates texts cannot be empty array" do
      embedder = embedder_class.new(texts: [])
      expect {
        embedder.send(:validate_input!, [])
      }.to raise_error(ArgumentError, "texts cannot be empty")
    end

    it "validates each text is a string" do
      embedder = embedder_class.new(texts: ["valid"])
      expect {
        embedder.send(:validate_input!, ["valid", 123])
      }.to raise_error(ArgumentError, /must be a String/)
    end

    it "validates texts are not empty strings" do
      embedder = embedder_class.new(texts: ["valid"])
      expect {
        embedder.send(:validate_input!, ["valid", ""])
      }.to raise_error(ArgumentError, /cannot be empty/)
    end
  end

  describe "#agent_cache_key" do
    it "generates unique cache key" do
      embedder1 = embedder_class.new(text: "Hello")
      embedder2 = embedder_class.new(text: "Hello")
      embedder3 = embedder_class.new(text: "World")

      expect(embedder1.agent_cache_key).to eq(embedder2.agent_cache_key)
      expect(embedder1.agent_cache_key).not_to eq(embedder3.agent_cache_key)
    end

    it "includes model in cache key" do
      embedder_class.model "text-embedding-3-small"
      embedder = embedder_class.new(text: "Hello")

      expect(embedder.agent_cache_key).to include("text-embedding-3-small")
    end

    it "includes dimensions in cache key when set" do
      embedder_class.dimensions 512
      embedder = embedder_class.new(text: "Hello")

      expect(embedder.agent_cache_key).to include("512")
    end
  end
end
