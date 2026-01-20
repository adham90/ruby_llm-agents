# frozen_string_literal: true

require "rails_helper"

RSpec.describe RubyLLM::Agents::BaseAgent do
  let(:config) { double("config") }

  before do
    allow(RubyLLM::Agents).to receive(:configuration).and_return(config)
    allow(config).to receive(:default_model).and_return("gpt-4o")
    allow(config).to receive(:default_timeout).and_return(120)
    allow(config).to receive(:default_temperature).and_return(0.7)
    allow(config).to receive(:default_streaming).and_return(false)
    allow(config).to receive(:budgets_enabled?).and_return(false)
  end

  describe "DSL integration" do
    let(:agent_class) do
      Class.new(described_class) do
        def self.name
          "TestAgent"
        end

        model "claude-3-sonnet"
        version "2.0"
        description "A test agent"
        timeout 30

        cache_for 1.hour

        reliability do
          retries max: 2
          fallback_models "claude-3-haiku"
        end

        param :query, required: true
        param :limit, default: 10

        def user_prompt
          "Search for: #{query} (limit: #{limit})"
        end

        def system_prompt
          "You are a search assistant"
        end
      end
    end

    it "uses DSL::Base for model configuration" do
      expect(agent_class.model).to eq("claude-3-sonnet")
    end

    it "uses DSL::Base for version" do
      expect(agent_class.version).to eq("2.0")
    end

    it "uses DSL::Base for description" do
      expect(agent_class.description).to eq("A test agent")
    end

    it "uses DSL::Base for timeout" do
      expect(agent_class.timeout).to eq(30)
    end

    it "uses DSL::Caching for cache configuration" do
      expect(agent_class.cache_enabled?).to be true
      expect(agent_class.cache_ttl).to eq(1.hour)
    end

    it "uses DSL::Reliability for retry configuration" do
      expect(agent_class.retries_config[:max]).to eq(2)
    end

    it "uses DSL::Reliability for fallback models" do
      expect(agent_class.fallback_models).to eq(["claude-3-haiku"])
    end

    it "defines parameters with param DSL" do
      expect(agent_class.params[:query][:required]).to be true
      expect(agent_class.params[:limit][:default]).to eq(10)
    end
  end

  describe "#initialize" do
    let(:agent_class) do
      Class.new(described_class) do
        def self.name
          "TestAgent"
        end

        param :query, required: true
        param :count, type: Integer

        def user_prompt
          query
        end
      end
    end

    it "validates required parameters" do
      expect { agent_class.new }.to raise_error(ArgumentError, /missing required param: query/)
    end

    it "validates parameter types" do
      expect { agent_class.new(query: "test", count: "not an integer") }
        .to raise_error(ArgumentError, /expected Integer for :count/)
    end

    it "allows valid parameters" do
      agent = agent_class.new(query: "test", count: 5)
      expect(agent.query).to eq("test")
      expect(agent.count).to eq(5)
    end

    it "uses default values" do
      simple_class = Class.new(described_class) do
        def self.name
          "SimpleAgent"
        end

        param :limit, default: 10

        def user_prompt
          "test"
        end
      end

      agent = simple_class.new
      expect(agent.limit).to eq(10)
    end
  end

  describe "#dry_run_response" do
    let(:agent_class) do
      Class.new(described_class) do
        def self.name
          "DryRunAgent"
        end

        model "gpt-4o"
        timeout 30
        tools []

        param :query

        def user_prompt
          query
        end

        def system_prompt
          "Be helpful"
        end
      end
    end

    it "returns agent configuration without making API call" do
      result = agent_class.call(query: "test", dry_run: true)

      expect(result.content[:dry_run]).to be true
      expect(result.content[:agent]).to eq("DryRunAgent")
      expect(result.content[:model]).to eq("gpt-4o")
      expect(result.content[:system_prompt]).to eq("Be helpful")
      expect(result.content[:user_prompt]).to eq("test")
    end
  end

  describe "#agent_cache_key" do
    let(:agent_class) do
      Class.new(described_class) do
        def self.name
          "CacheAgent"
        end

        version "1.0"

        param :query

        def user_prompt
          query
        end

        def system_prompt
          "Be helpful"
        end
      end
    end

    it "generates a unique cache key" do
      agent = agent_class.new(query: "test query")
      key = agent.agent_cache_key

      expect(key).to start_with("ruby_llm_agent/CacheAgent/1.0/")
      expect(key).to match(/[a-f0-9]{64}$/) # SHA256 hex
    end

    it "generates different keys for different queries" do
      agent1 = agent_class.new(query: "query 1")
      agent2 = agent_class.new(query: "query 2")

      expect(agent1.agent_cache_key).not_to eq(agent2.agent_cache_key)
    end

    it "generates the same key for the same inputs" do
      agent1 = agent_class.new(query: "same query")
      agent2 = agent_class.new(query: "same query")

      expect(agent1.agent_cache_key).to eq(agent2.agent_cache_key)
    end
  end

  describe ".agent_type" do
    it "returns :conversation by default" do
      expect(described_class.agent_type).to eq(:conversation)
    end

    it "can be overridden in subclasses" do
      embedder_class = Class.new(described_class) do
        def self.name
          "Embedder"
        end

        def self.agent_type
          :embedding
        end

        def user_prompt
          "test"
        end
      end

      expect(embedder_class.agent_type).to eq(:embedding)
    end
  end

  describe ".stream" do
    let(:agent_class) do
      Class.new(described_class) do
        def self.name
          "StreamAgent"
        end

        def user_prompt
          "Hello"
        end
      end
    end

    it "requires a block" do
      expect { agent_class.stream(query: "test") }
        .to raise_error(ArgumentError, "Block required for streaming")
    end
  end

  describe "temperature DSL" do
    let(:agent_class) do
      Class.new(described_class) do
        def self.name
          "TempAgent"
        end

        temperature 0.9

        def user_prompt
          "test"
        end
      end
    end

    it "sets the temperature" do
      expect(agent_class.temperature).to eq(0.9)
    end
  end

  describe "tools DSL" do
    let(:mock_tool) { double("Tool", name: "search") }

    let(:agent_class) do
      tool = mock_tool
      Class.new(described_class) do
        define_singleton_method(:name) { "ToolsAgent" }
        tools [tool]

        define_method(:user_prompt) { "test" }
      end
    end

    it "sets the tools" do
      expect(agent_class.tools).to eq([mock_tool])
    end
  end

  describe "streaming DSL" do
    let(:agent_class) do
      Class.new(described_class) do
        def self.name
          "StreamingAgent"
        end

        streaming true

        def user_prompt
          "test"
        end
      end
    end

    it "sets streaming mode" do
      expect(agent_class.streaming).to be true
    end
  end

  describe "thinking DSL" do
    let(:agent_class) do
      Class.new(described_class) do
        def self.name
          "ThinkingAgent"
        end

        thinking effort: :high, budget: 10000

        def user_prompt
          "test"
        end
      end
    end

    it "sets thinking configuration" do
      expect(agent_class.thinking_config).to eq({ effort: :high, budget: 10000 })
    end
  end

  describe "context building" do
    let(:agent_class) do
      Class.new(described_class) do
        def self.name
          "ContextAgent"
        end

        param :query

        def user_prompt
          query
        end
      end
    end

    it "builds context with tenant when provided as hash" do
      agent = agent_class.new(query: "test", tenant: { id: "org_123" })
      context = agent.send(:build_context)

      expect(context.agent_class).to eq(agent_class)
      expect(context.agent_instance).to eq(agent)
      expect(context.input).to eq("test")
    end
  end

  describe "inheritance" do
    let(:parent_class) do
      Class.new(described_class) do
        def self.name
          "ParentAgent"
        end

        model "gpt-4o"
        version "1.0"
        temperature 0.5
        cache_for 1.hour

        param :shared_param, default: "parent"

        def user_prompt
          "parent prompt"
        end
      end
    end

    let(:child_class) do
      Class.new(parent_class) do
        def self.name
          "ChildAgent"
        end

        model "gpt-4o-mini"
        version "2.0"

        param :child_param, required: true

        def user_prompt
          "child: #{child_param}"
        end
      end
    end

    it "inherits model from parent" do
      expect(child_class.model).to eq("gpt-4o-mini")
    end

    it "inherits temperature from parent" do
      expect(child_class.temperature).to eq(0.5)
    end

    it "inherits cache settings from parent" do
      expect(child_class.cache_enabled?).to be true
    end

    it "merges parameters from parent and child" do
      expect(child_class.params.keys).to include(:shared_param, :child_param)
    end
  end
end
