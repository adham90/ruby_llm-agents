# frozen_string_literal: true

require "rails_helper"

RSpec.describe RubyLLM::Agents::Embedder::DSL do
  # Create test embedder classes for each test
  let(:base_embedder) do
    Class.new(RubyLLM::Agents::Embedder)
  end

  describe ".model" do
    it "sets and returns the model" do
      base_embedder.model "text-embedding-3-large"
      expect(base_embedder.model).to eq("text-embedding-3-large")
    end

    it "returns default when not set" do
      expect(base_embedder.model).to eq(RubyLLM::Agents.configuration.default_embedding_model)
    end

    it "inherits from parent class" do
      base_embedder.model "text-embedding-3-large"
      child = Class.new(base_embedder)
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
      child = Class.new(base_embedder)
      expect(child.dimensions).to eq(256)
    end
  end

  describe ".batch_size" do
    it "sets and returns batch_size" do
      base_embedder.batch_size 50
      expect(base_embedder.batch_size).to eq(50)
    end

    it "returns default when not set" do
      expect(base_embedder.batch_size).to eq(RubyLLM::Agents.configuration.default_embedding_batch_size)
    end

    it "inherits from parent class" do
      base_embedder.batch_size 25
      child = Class.new(base_embedder)
      expect(child.batch_size).to eq(25)
    end
  end

  describe ".version" do
    it "sets and returns version" do
      base_embedder.version "2.0"
      expect(base_embedder.version).to eq("2.0")
    end

    it "returns default when not set" do
      expect(base_embedder.version).to eq("1.0")
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
        model "text-embedding-3-large"
        # dimensions not overridden
      end

      expect(child.model).to eq("text-embedding-3-large")
      expect(child.dimensions).to eq(1536)
    end
  end
end
