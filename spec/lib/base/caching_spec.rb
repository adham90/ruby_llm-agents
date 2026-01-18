# frozen_string_literal: true

require "rails_helper"
require "digest"

RSpec.describe RubyLLM::Agents::Base::Caching do
  let(:agent_class) do
    Class.new(RubyLLM::Agents::Base) do
      model "gpt-4o"
      version "1.0.0"

      def self.name
        "TestCachingAgent"
      end
    end
  end

  let(:options) { { query: "test query", limit: 10 } }
  let(:agent) { agent_class.new(**options) }

  describe "#agent_cache_key" do
    it "includes the ruby_llm_agent namespace" do
      expect(agent.agent_cache_key).to start_with("ruby_llm_agent/")
    end

    it "includes the class name" do
      expect(agent.agent_cache_key).to include("TestCachingAgent")
    end

    it "includes the version" do
      expect(agent.agent_cache_key).to include("1.0.0")
    end

    it "includes the cache key hash" do
      hash = agent.cache_key_hash
      expect(agent.agent_cache_key).to end_with(hash)
    end

    it "returns consistent format" do
      key = agent.agent_cache_key
      parts = key.split("/")

      expect(parts[0]).to eq("ruby_llm_agent")
      expect(parts[1]).to eq("TestCachingAgent")
      expect(parts[2]).to eq("1.0.0")
      expect(parts[3]).to be_a(String)
    end

    context "when version changes" do
      let(:v2_agent_class) do
        Class.new(RubyLLM::Agents::Base) do
          model "gpt-4o"
          version "2.0.0"

          def self.name
            "TestCachingAgent"
          end
        end
      end

      it "produces different cache keys" do
        v1_agent = agent_class.new(**options)
        v2_agent = v2_agent_class.new(**options)

        expect(v1_agent.agent_cache_key).not_to eq(v2_agent.agent_cache_key)
      end
    end

    context "when options change" do
      it "produces different cache keys" do
        agent1 = agent_class.new(query: "query1")
        agent2 = agent_class.new(query: "query2")

        expect(agent1.agent_cache_key).not_to eq(agent2.agent_cache_key)
      end
    end
  end

  describe "#cache_key_hash" do
    it "returns a SHA256 hex digest" do
      hash = agent.cache_key_hash
      expect(hash).to match(/\A[a-f0-9]{64}\z/)
    end

    it "is consistent for the same options" do
      agent1 = agent_class.new(**options)
      agent2 = agent_class.new(**options)

      expect(agent1.cache_key_hash).to eq(agent2.cache_key_hash)
    end

    it "differs for different options" do
      agent1 = agent_class.new(query: "query1")
      agent2 = agent_class.new(query: "query2")

      expect(agent1.cache_key_hash).not_to eq(agent2.cache_key_hash)
    end

    it "uses cache_key_data for hashing" do
      data = agent.cache_key_data
      expected_hash = Digest::SHA256.hexdigest(data.to_json)

      expect(agent.cache_key_hash).to eq(expected_hash)
    end
  end

  describe "#cache_key_data" do
    it "returns options without skip_cache" do
      agent_with_skip = agent_class.new(query: "test", skip_cache: true)
      data = agent_with_skip.cache_key_data

      expect(data).not_to have_key(:skip_cache)
      expect(data).to have_key(:query)
    end

    it "returns options without dry_run" do
      agent_with_dry_run = agent_class.new(query: "test", dry_run: true)
      data = agent_with_dry_run.cache_key_data

      expect(data).not_to have_key(:dry_run)
      expect(data).to have_key(:query)
    end

    it "returns options without with" do
      agent_with_with = agent_class.new(query: "test", with: :something)
      data = agent_with_with.cache_key_data

      expect(data).not_to have_key(:with)
      expect(data).to have_key(:query)
    end

    it "excludes all three keys simultaneously" do
      agent_all = agent_class.new(
        query: "test",
        skip_cache: true,
        dry_run: true,
        with: :something
      )
      data = agent_all.cache_key_data

      expect(data).not_to have_key(:skip_cache)
      expect(data).not_to have_key(:dry_run)
      expect(data).not_to have_key(:with)
      expect(data).to have_key(:query)
    end

    it "includes all other options" do
      agent_many = agent_class.new(
        query: "test",
        limit: 10,
        format: :json,
        context: { user: "test" }
      )
      data = agent_many.cache_key_data

      expect(data[:query]).to eq("test")
      expect(data[:limit]).to eq(10)
      expect(data[:format]).to eq(:json)
      expect(data[:context]).to eq({ user: "test" })
    end

    it "returns empty hash when only excluded options are present" do
      agent_only_excluded = agent_class.new(
        skip_cache: true,
        dry_run: true,
        with: :something
      )
      data = agent_only_excluded.cache_key_data

      expect(data).to eq({})
    end
  end

  describe "CacheHelper integration" do
    let(:mock_cache_store) { ActiveSupport::Cache::MemoryStore.new }

    before do
      allow(RubyLLM::Agents.configuration).to receive(:cache_store).and_return(mock_cache_store)
    end

    describe "#cache_store" do
      it "returns the configured cache store" do
        expect(agent.cache_store).to eq(mock_cache_store)
      end
    end

    describe "#cache_key" do
      it "generates namespaced cache key" do
        key = agent.cache_key("test", "part1", "part2")
        expect(key).to eq("ruby_llm_agents:test:part1:part2")
      end

      it "converts symbols to strings" do
        key = agent.cache_key(:budget, :global)
        expect(key).to eq("ruby_llm_agents:budget:global")
      end

      it "handles single part" do
        key = agent.cache_key("single")
        expect(key).to eq("ruby_llm_agents:single")
      end
    end

    describe "#cache_read" do
      it "reads from the cache store" do
        mock_cache_store.write("test_key", "test_value")

        expect(agent.cache_read("test_key")).to eq("test_value")
      end

      it "returns nil for missing keys" do
        expect(agent.cache_read("nonexistent_key")).to be_nil
      end
    end

    describe "#cache_write" do
      it "writes to the cache store" do
        agent.cache_write("test_key", "my_value")

        expect(mock_cache_store.read("test_key")).to eq("my_value")
      end

      it "accepts expires_in option" do
        agent.cache_write("expiring_key", "expiring_value", expires_in: 1.hour)

        expect(mock_cache_store.read("expiring_key")).to eq("expiring_value")
      end

      it "can write complex values" do
        value = { nested: { data: [1, 2, 3] }, string: "test" }
        agent.cache_write("complex_key", value)

        expect(mock_cache_store.read("complex_key")).to eq(value)
      end
    end

    describe "#cache_exist?" do
      it "returns true for existing keys" do
        mock_cache_store.write("existing_key", "value")

        expect(agent.cache_exist?("existing_key")).to be true
      end

      it "returns false for missing keys" do
        expect(agent.cache_exist?("nonexistent_key")).to be false
      end
    end

    describe "#cache_delete" do
      it "removes the key from cache" do
        mock_cache_store.write("delete_key", "value")

        agent.cache_delete("delete_key")

        expect(mock_cache_store.read("delete_key")).to be_nil
      end
    end

    describe "#cache_increment" do
      let(:key) { "increment_key" }

      context "when cache store supports increment" do
        it "increments the value by 1 by default" do
          mock_cache_store.write(key, 5)
          result = agent.cache_increment(key)

          expect(result).to eq(6)
        end

        it "increments by custom amount" do
          mock_cache_store.write(key, 10)
          result = agent.cache_increment(key, 5)

          expect(result).to eq(15)
        end

        it "handles expires_in option" do
          result = agent.cache_increment(key, 1, expires_in: 1.hour)
          expect(result).to be_a(Numeric)
        end
      end

      context "when key doesn't exist" do
        it "creates the key with initial increment" do
          result = agent.cache_increment("new_key", 1, expires_in: 1.hour)
          expect(result).to be_a(Numeric)
        end
      end

      context "when cache store does not support increment" do
        let(:non_increment_store) { double("CacheStore") }

        before do
          allow(RubyLLM::Agents.configuration).to receive(:cache_store).and_return(non_increment_store)
          allow(non_increment_store).to receive(:respond_to?).with(:increment).and_return(false)
        end

        it "falls back to read-modify-write" do
          allow(non_increment_store).to receive(:read).with(key).and_return(10)
          allow(non_increment_store).to receive(:write)

          result = agent.cache_increment(key, 5, expires_in: 1.hour)

          expect(result).to eq(15)
          expect(non_increment_store).to have_received(:write).with(key, 15, expires_in: 1.hour)
        end

        it "handles nil values as zero" do
          allow(non_increment_store).to receive(:read).with(key).and_return(nil)
          allow(non_increment_store).to receive(:write)

          result = agent.cache_increment(key, 3, expires_in: 1.hour)

          expect(result).to eq(3)
        end
      end
    end
  end

  describe "inheritance" do
    let(:parent_agent_class) do
      Class.new(RubyLLM::Agents::Base) do
        model "gpt-4o"
        version "1.0.0"

        def self.name
          "ParentCachingAgent"
        end
      end
    end

    let(:child_agent_class) do
      Class.new(parent_agent_class) do
        version "1.1.0"

        def self.name
          "ChildCachingAgent"
        end
      end
    end

    it "child has different cache key due to class name" do
      parent = parent_agent_class.new(query: "test")
      child = child_agent_class.new(query: "test")

      expect(parent.agent_cache_key).not_to eq(child.agent_cache_key)
    end

    it "child has different cache key due to version" do
      parent = parent_agent_class.new(query: "test")
      child = child_agent_class.new(query: "test")

      expect(parent.agent_cache_key).to include("1.0.0")
      expect(child.agent_cache_key).to include("1.1.0")
    end
  end

  describe "edge cases" do
    describe "with nil values in options" do
      it "handles nil values" do
        agent_with_nil = agent_class.new(query: nil, limit: nil)
        expect { agent_with_nil.agent_cache_key }.not_to raise_error
      end
    end

    describe "with empty options" do
      it "generates valid cache key" do
        empty_agent = agent_class.new
        expect(empty_agent.agent_cache_key).to be_a(String)
        expect(empty_agent.agent_cache_key.length).to be > 0
      end
    end

    describe "with deeply nested options" do
      it "hashes nested structures correctly" do
        agent1 = agent_class.new(
          data: { level1: { level2: { level3: "value" } } }
        )
        agent2 = agent_class.new(
          data: { level1: { level2: { level3: "different" } } }
        )

        expect(agent1.cache_key_hash).not_to eq(agent2.cache_key_hash)
      end
    end

    describe "with array options" do
      it "hashes arrays correctly" do
        agent1 = agent_class.new(items: [1, 2, 3])
        agent2 = agent_class.new(items: [1, 2, 4])

        expect(agent1.cache_key_hash).not_to eq(agent2.cache_key_hash)
      end

      it "considers array order" do
        agent1 = agent_class.new(items: [1, 2, 3])
        agent2 = agent_class.new(items: [3, 2, 1])

        expect(agent1.cache_key_hash).not_to eq(agent2.cache_key_hash)
      end
    end

    describe "with special characters in options" do
      it "handles unicode strings" do
        agent_unicode = agent_class.new(query: "Hello 世界 🌍")
        expect { agent_unicode.agent_cache_key }.not_to raise_error
      end

      it "handles special JSON characters" do
        agent_special = agent_class.new(query: 'test "quoted" and \\backslash')
        expect { agent_special.agent_cache_key }.not_to raise_error
      end
    end
  end

  describe "CacheHelper NAMESPACE constant" do
    it "is defined" do
      expect(RubyLLM::Agents::CacheHelper::NAMESPACE).to eq("ruby_llm_agents")
    end
  end
end
