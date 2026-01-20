# frozen_string_literal: true

require "rails_helper"

RSpec.describe RubyLLM::Agents::DSL::Caching do
  let(:test_class) do
    Class.new do
      extend RubyLLM::Agents::DSL::Caching

      def self.name
        "TestAgent"
      end
    end
  end

  describe "#cache_for" do
    it "enables caching with the specified TTL" do
      test_class.cache_for(1.hour)

      expect(test_class.cache_enabled?).to be true
      expect(test_class.cache_ttl).to eq(1.hour)
    end

    it "enables caching with different TTL values" do
      test_class.cache_for(30.minutes)

      expect(test_class.cache_enabled?).to be true
      expect(test_class.cache_ttl).to eq(30.minutes)
    end
  end

  describe "#cache_enabled?" do
    it "returns false when caching is not enabled" do
      expect(test_class.cache_enabled?).to be false
    end

    it "returns true when caching is enabled" do
      test_class.cache_for(1.hour)
      expect(test_class.cache_enabled?).to be true
    end
  end

  describe "#cache_ttl" do
    it "returns default TTL when not explicitly set" do
      expect(test_class.cache_ttl).to eq(1.hour)
    end

    it "returns the configured TTL" do
      test_class.cache_for(2.hours)
      expect(test_class.cache_ttl).to eq(2.hours)
    end
  end

  describe "#cache_key_includes" do
    it "returns nil when not set" do
      expect(test_class.cache_key_includes).to be_nil
    end

    it "sets the keys to include in cache key" do
      test_class.cache_key_includes(:user_id, :query)
      expect(test_class.cache_key_includes).to eq([:user_id, :query])
    end

    it "accepts an array" do
      test_class.cache_key_includes([:tenant_id, :context])
      expect(test_class.cache_key_includes).to eq([:tenant_id, :context])
    end
  end

  describe "#cache_key_excludes" do
    it "returns default excludes when not set" do
      expect(test_class.cache_key_excludes).to eq(%i[skip_cache dry_run with])
    end

    it "sets the keys to exclude from cache key" do
      test_class.cache_key_excludes(:timestamp, :request_id)
      expect(test_class.cache_key_excludes).to eq([:timestamp, :request_id])
    end
  end

  describe "#caching_config" do
    it "returns nil when caching is not enabled" do
      expect(test_class.caching_config).to be_nil
    end

    it "returns config hash when caching is enabled" do
      test_class.cache_for(1.hour)
      test_class.cache_key_includes(:query)

      config = test_class.caching_config
      expect(config[:enabled]).to be true
      expect(config[:ttl]).to eq(1.hour)
      expect(config[:key_includes]).to eq([:query])
      expect(config[:key_excludes]).to eq(%i[skip_cache dry_run with])
    end
  end

  describe "inheritance" do
    it "inherits cache_enabled from parent" do
      test_class.cache_for(1.hour)

      child_class = Class.new(test_class)
      expect(child_class.cache_enabled?).to be true
    end

    it "inherits cache_ttl from parent" do
      test_class.cache_for(2.hours)

      child_class = Class.new(test_class)
      expect(child_class.cache_ttl).to eq(2.hours)
    end

    it "allows child to override cache settings" do
      test_class.cache_for(1.hour)

      child_class = Class.new(test_class) do
        extend RubyLLM::Agents::DSL::Caching
        cache_for 30.minutes
      end

      expect(child_class.cache_ttl).to eq(30.minutes)
    end

    it "inherits cache_key_includes from parent" do
      test_class.cache_key_includes(:user_id)

      child_class = Class.new(test_class)
      expect(child_class.cache_key_includes).to eq([:user_id])
    end

    it "inherits cache_key_excludes from parent" do
      test_class.cache_key_excludes(:timestamp)

      child_class = Class.new(test_class)
      expect(child_class.cache_key_excludes).to eq([:timestamp])
    end
  end
end
