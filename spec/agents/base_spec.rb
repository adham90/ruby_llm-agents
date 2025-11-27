# frozen_string_literal: true

require "rails_helper"

RSpec.describe RubyLLM::Agents::Base do
  describe "DSL class methods" do
    describe ".model" do
      it "sets and gets the model" do
        klass = Class.new(described_class) do
          model "gpt-4"
        end
        expect(klass.model).to eq("gpt-4")
      end

      it "inherits model from parent" do
        parent = Class.new(described_class) { model "gpt-4" }
        child = Class.new(parent)
        expect(child.model).to eq("gpt-4")
      end
    end

    describe ".temperature" do
      it "sets and gets the temperature" do
        klass = Class.new(described_class) do
          temperature 0.7
        end
        expect(klass.temperature).to eq(0.7)
      end
    end

    describe ".version" do
      it "sets and gets the version" do
        klass = Class.new(described_class) do
          version "2.0"
        end
        expect(klass.version).to eq("2.0")
      end

      it "defaults to 1.0" do
        klass = Class.new(described_class)
        expect(klass.version).to eq("1.0")
      end
    end

    describe ".param" do
      it "defines required parameters" do
        klass = Class.new(described_class) do
          param :query, required: true
        end
        expect(klass.params[:query]).to include(required: true)
      end

      it "defines parameters with defaults" do
        klass = Class.new(described_class) do
          param :limit, default: 10
        end
        expect(klass.params[:limit]).to include(default: 10)
      end
    end

    describe ".cache" do
      it "sets cache duration" do
        klass = Class.new(described_class) do
          cache 1.hour
        end
        expect(klass.cache_ttl).to eq(1.hour)
      end
    end

    describe ".streaming" do
      it "sets and gets streaming mode" do
        klass = Class.new(described_class) do
          streaming true
        end
        expect(klass.streaming).to be true
      end

      it "defaults to false" do
        klass = Class.new(described_class)
        expect(klass.streaming).to be false
      end

      it "inherits streaming from parent" do
        parent = Class.new(described_class) { streaming true }
        child = Class.new(parent)
        expect(child.streaming).to be true
      end
    end

    describe ".tools" do
      let(:mock_tool) do
        Class.new do
          def self.name
            "MockTool"
          end
        end
      end

      it "sets and gets tools" do
        tool = mock_tool
        klass = Class.new(described_class) do
          tools tool
        end
        expect(klass.tools).to include(tool)
      end

      it "defaults to empty array" do
        klass = Class.new(described_class)
        expect(klass.tools).to eq([])
      end

      it "allows multiple tools" do
        tool1 = mock_tool
        tool2 = Class.new { def self.name; "AnotherTool"; end }
        klass = Class.new(described_class) do
          tools tool1, tool2
        end
        expect(klass.tools).to include(tool1, tool2)
      end

      it "inherits tools from parent" do
        tool = mock_tool
        parent = Class.new(described_class) { tools tool }
        child = Class.new(parent)
        expect(child.tools).to include(tool)
      end
    end
  end

  describe "instance initialization" do
    let(:agent_class) do
      Class.new(described_class) do
        model "gpt-4"
        temperature 0.5
        param :query, required: true
        param :limit, default: 10
      end
    end

    it "sets required parameters" do
      agent = agent_class.new(query: "test")
      expect(agent.query).to eq("test")
    end

    it "uses default values for optional parameters" do
      agent = agent_class.new(query: "test")
      expect(agent.limit).to eq(10)
    end

    it "allows overriding defaults" do
      agent = agent_class.new(query: "test", limit: 20)
      expect(agent.limit).to eq(20)
    end

    it "raises error for missing required parameters" do
      expect {
        agent_class.new(limit: 10)
      }.to raise_error(ArgumentError, /missing required params/)
    end
  end

  describe "dry_run mode" do
    let(:mock_tool) do
      Class.new do
        def self.name
          "TestTool"
        end
      end
    end

    let(:agent_class) do
      Class.new(described_class) do
        model "gpt-4"
        param :query, required: true

        def system_prompt
          "Test prompt"
        end

        def user_prompt
          query
        end
      end
    end

    it "returns a Result object when dry_run: true" do
      agent = agent_class.new(query: "test", dry_run: true)
      result = agent.call

      expect(result).to be_a(RubyLLM::Agents::Result)
      expect(result.content[:dry_run]).to be true
      expect(result.content[:model]).to eq("gpt-4")
      expect(result.content[:user_prompt]).to eq("test")
      expect(result.model_id).to eq("gpt-4")
    end

    it "supports backward compatible hash access on dry_run result" do
      agent = agent_class.new(query: "test", dry_run: true)
      result = agent.call

      # Delegated methods still work
      expect(result[:dry_run]).to be true
      expect(result[:model]).to eq("gpt-4")
      expect(result[:user_prompt]).to eq("test")
    end

    it "includes streaming in dry run response" do
      streaming_class = Class.new(described_class) do
        model "gpt-4"
        streaming true
        param :query, required: true

        def user_prompt
          query
        end
      end

      result = streaming_class.call(query: "test", dry_run: true)
      expect(result[:streaming]).to be true
    end

    it "includes tools in dry run response" do
      tool = mock_tool
      tools_class = Class.new(described_class) do
        model "gpt-4"
        param :query, required: true

        def user_prompt
          query
        end
      end
      tools_class.tools(tool)

      result = tools_class.call(query: "test", dry_run: true)
      expect(result[:tools]).to include("TestTool")
    end
  end

  describe ".call" do
    let(:agent_class) do
      Class.new(described_class) do
        model "gpt-4"
        param :query, required: true

        def system_prompt
          "Test system prompt"
        end

        def user_prompt
          query
        end
      end
    end

    it "creates instance and calls #call" do
      agent_instance = instance_double(agent_class)
      allow(agent_class).to receive(:new).and_return(agent_instance)
      allow(agent_instance).to receive(:call).and_return("result")

      result = agent_class.call(query: "test")

      expect(agent_class).to have_received(:new).with(query: "test")
      expect(agent_instance).to have_received(:call)
      expect(result).to eq("result")
    end
  end

  describe "#cache_key" do
    let(:agent_class) do
      Class.new(described_class) do
        model "gpt-4"
        param :query, required: true

        def system_prompt
          "Test prompt"
        end

        def user_prompt
          query
        end
      end
    end

    it "generates consistent cache key for same inputs" do
      agent1 = agent_class.new(query: "test")
      agent2 = agent_class.new(query: "test")

      expect(agent1.send(:cache_key)).to eq(agent2.send(:cache_key))
    end

    it "generates different cache key for different inputs" do
      agent1 = agent_class.new(query: "test1")
      agent2 = agent_class.new(query: "test2")

      expect(agent1.send(:cache_key)).not_to eq(agent2.send(:cache_key))
    end

    it "excludes :with from cache key" do
      agent1 = agent_class.new(query: "test", with: "image.png")
      agent2 = agent_class.new(query: "test")

      expect(agent1.send(:cache_key)).to eq(agent2.send(:cache_key))
    end
  end

  describe "attachments support" do
    let(:agent_class) do
      Class.new(described_class) do
        model "gpt-4o"
        param :query, required: true

        def user_prompt
          query
        end
      end
    end

    describe "#ask_options" do
      it "returns empty hash when no attachments" do
        agent = agent_class.new(query: "test")
        expect(agent.send(:ask_options)).to eq({})
      end

      it "includes :with when attachment provided" do
        agent = agent_class.new(query: "test", with: "image.png")
        expect(agent.send(:ask_options)).to eq({with: "image.png"})
      end

      it "supports array of attachments" do
        agent = agent_class.new(query: "test", with: ["a.png", "b.png"])
        expect(agent.send(:ask_options)).to eq({with: ["a.png", "b.png"]})
      end
    end

    describe "dry_run with attachments" do
      it "includes attachments in dry run response" do
        result = agent_class.call(query: "test", with: "photo.jpg", dry_run: true)

        expect(result[:attachments]).to eq("photo.jpg")
      end

      it "includes array attachments in dry run response" do
        result = agent_class.call(query: "test", with: ["a.png", "b.png"], dry_run: true)

        expect(result[:attachments]).to eq(["a.png", "b.png"])
      end

      it "shows nil attachments when none provided" do
        result = agent_class.call(query: "test", dry_run: true)

        expect(result[:attachments]).to be_nil
      end
    end
  end
end
