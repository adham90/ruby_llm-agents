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

    it "returns dry run response when dry_run: true" do
      agent = agent_class.new(query: "test", dry_run: true)
      result = agent.call

      expect(result[:dry_run]).to be true
      expect(result[:model]).to eq("gpt-4")
      expect(result[:user_prompt]).to eq("test")
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
  end
end
