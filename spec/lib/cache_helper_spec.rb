# frozen_string_literal: true

require "rails_helper"

RSpec.describe RubyLLM::Agents::CacheHelper do
  # Test class that extends the module
  let(:test_class) do
    Class.new do
      extend RubyLLM::Agents::CacheHelper
    end
  end

  # Test instance that includes the module
  let(:test_instance_class) do
    Class.new do
      include RubyLLM::Agents::CacheHelper
    end
  end

  let(:cache_store) { ActiveSupport::Cache::MemoryStore.new }

  before do
    RubyLLM::Agents.reset_configuration!
    allow(RubyLLM::Agents.configuration).to receive(:cache_store).and_return(cache_store)
    cache_store.clear
  end

  describe "NAMESPACE" do
    it "defines the cache key namespace" do
      expect(described_class::NAMESPACE).to eq("ruby_llm_agents")
    end
  end

  describe "#cache_store" do
    it "returns the configured cache store (extended)" do
      expect(test_class.cache_store).to eq(cache_store)
    end

    it "returns the configured cache store (included)" do
      instance = test_instance_class.new
      expect(instance.cache_store).to eq(cache_store)
    end
  end

  describe "#cache_key" do
    it "generates namespaced key with single part" do
      expect(test_class.cache_key("budget")).to eq("ruby_llm_agents:budget")
    end

    it "generates namespaced key with multiple parts" do
      expect(test_class.cache_key("budget", "global", "2024-01")).to eq("ruby_llm_agents:budget:global:2024-01")
    end

    it "converts symbols to strings" do
      expect(test_class.cache_key(:budget, :daily)).to eq("ruby_llm_agents:budget:daily")
    end

    it "handles mixed types" do
      expect(test_class.cache_key("budget", :daily, 123)).to eq("ruby_llm_agents:budget:daily:123")
    end
  end

  describe "#cache_read" do
    it "returns nil for missing keys" do
      expect(test_class.cache_read("missing_key")).to be_nil
    end

    it "returns cached value for existing keys" do
      cache_store.write("test_key", "test_value")
      expect(test_class.cache_read("test_key")).to eq("test_value")
    end

    it "returns complex objects" do
      data = { foo: "bar", count: 42 }
      cache_store.write("complex_key", data)
      expect(test_class.cache_read("complex_key")).to eq(data)
    end
  end

  describe "#cache_write" do
    it "writes value to cache" do
      test_class.cache_write("new_key", "new_value")
      expect(cache_store.read("new_key")).to eq("new_value")
    end

    it "supports expires_in option" do
      test_class.cache_write("expiring_key", "value", expires_in: 1.hour)
      expect(cache_store.read("expiring_key")).to eq("value")
    end

    it "overwrites existing values" do
      cache_store.write("key", "old")
      test_class.cache_write("key", "new")
      expect(cache_store.read("key")).to eq("new")
    end
  end

  describe "#cache_exist?" do
    it "returns false for missing keys" do
      expect(test_class.cache_exist?("missing")).to be false
    end

    it "returns true for existing keys" do
      cache_store.write("exists", "value")
      expect(test_class.cache_exist?("exists")).to be true
    end

    it "returns true for nil values" do
      cache_store.write("nil_value", nil)
      expect(test_class.cache_exist?("nil_value")).to be true
    end
  end

  describe "#cache_delete" do
    it "removes key from cache" do
      cache_store.write("to_delete", "value")
      test_class.cache_delete("to_delete")
      expect(cache_store.read("to_delete")).to be_nil
    end

    it "returns truthy for successful delete" do
      cache_store.write("key", "value")
      expect(test_class.cache_delete("key")).to be_truthy
    end

    it "handles missing keys gracefully" do
      expect { test_class.cache_delete("missing") }.not_to raise_error
    end
  end

  describe "#cache_increment" do
    context "with cache store that supports increment" do
      it "increments value by 1 by default" do
        cache_store.write("counter", 0)
        result = test_class.cache_increment("counter")
        expect(result).to eq(1)
      end

      it "increments by specified amount" do
        cache_store.write("counter", 10)
        result = test_class.cache_increment("counter", 5)
        expect(result).to eq(15)
      end

      it "increments by float amount" do
        cache_store.write("counter", 10)
        result = test_class.cache_increment("counter", 2.5)
        # MemoryStore's increment truncates floats, so we check it increments
        expect(result).to be >= 12
      end

      it "creates key with initial value if it does not exist" do
        result = test_class.cache_increment("new_counter", 5, expires_in: 1.hour)
        expect(result).to eq(5)
      end
    end

    context "with cache store that does not support increment" do
      let(:simple_cache) do
        # Create a simple cache that doesn't respond to increment
        Class.new do
          def initialize
            @data = {}
          end

          def read(key)
            @data[key]
          end

          def write(key, value, **_options)
            @data[key] = value
            true
          end
        end.new
      end

      before do
        allow(RubyLLM::Agents.configuration).to receive(:cache_store).and_return(simple_cache)
      end

      it "falls back to read-modify-write" do
        simple_cache.write("counter", 10)
        result = test_class.cache_increment("counter", 5)
        expect(result).to eq(15.0)
      end

      it "initializes missing keys to 0" do
        result = test_class.cache_increment("missing", 7)
        expect(result).to eq(7.0)
      end

      it "handles nil values" do
        simple_cache.write("nil_counter", nil)
        result = test_class.cache_increment("nil_counter", 3)
        expect(result).to eq(3.0)
      end
    end
  end

  describe "module usage patterns" do
    it "works when extended by a class" do
      klass = Class.new do
        extend RubyLLM::Agents::CacheHelper
      end

      key = klass.cache_key("test", "extended")
      klass.cache_write(key, "value")
      expect(klass.cache_read(key)).to eq("value")
    end

    it "works when included in a class" do
      klass = Class.new do
        include RubyLLM::Agents::CacheHelper
      end

      instance = klass.new
      key = instance.cache_key("test", "included")
      instance.cache_write(key, "value")
      expect(instance.cache_read(key)).to eq("value")
    end
  end
end
