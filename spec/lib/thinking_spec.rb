# frozen_string_literal: true

require "rails_helper"
require "ostruct"

RSpec.describe "Thinking Support" do
  # Helper to create a fresh agent class for each test
  def create_agent_class(&block)
    Class.new(RubyLLM::Agents::Base) do
      class_eval(&block) if block
    end
  end

  describe "DSL" do
    describe ".thinking" do
      it "sets effort level" do
        klass = create_agent_class { thinking effort: :high }
        expect(klass.thinking[:effort]).to eq(:high)
      end

      it "sets token budget" do
        klass = create_agent_class { thinking budget: 10_000 }
        expect(klass.thinking[:budget]).to eq(10_000)
      end

      it "sets both effort and budget" do
        klass = create_agent_class { thinking effort: :medium, budget: 5000 }
        config = klass.thinking
        expect(config[:effort]).to eq(:medium)
        expect(config[:budget]).to eq(5000)
      end

      it "returns nil when not configured" do
        klass = create_agent_class
        expect(klass.thinking).to be_nil
      end

      it "inherits from parent" do
        parent = create_agent_class { thinking effort: :high }
        child = Class.new(parent)
        expect(child.thinking[:effort]).to eq(:high)
      end

      it "can override parent thinking" do
        parent = create_agent_class { thinking effort: :high }
        child = Class.new(parent) { thinking effort: :low }
        expect(child.thinking[:effort]).to eq(:low)
      end

      it "falls back to configuration default when set" do
        original_default = RubyLLM::Agents.configuration.default_thinking
        begin
          RubyLLM::Agents.configuration.default_thinking = { effort: :medium }
          klass = create_agent_class
          expect(klass.thinking[:effort]).to eq(:medium)
        ensure
          RubyLLM::Agents.configuration.default_thinking = original_default
        end
      end
    end

    describe ".thinking_config" do
      it "returns nil when not configured" do
        klass = create_agent_class
        expect(klass.thinking_config).to be_nil
      end

      it "returns configured value" do
        klass = create_agent_class { thinking effort: :high, budget: 8000 }
        config = klass.thinking_config
        expect(config[:effort]).to eq(:high)
        expect(config[:budget]).to eq(8000)
      end

      it "inherits from parent" do
        parent = create_agent_class { thinking effort: :high }
        child = Class.new(parent)
        expect(child.thinking_config[:effort]).to eq(:high)
      end
    end
  end

  describe "Configuration" do
    describe ".default_thinking" do
      it "defaults to nil" do
        config = RubyLLM::Agents::Configuration.new
        expect(config.default_thinking).to be_nil
      end

      it "can be set to effort configuration" do
        config = RubyLLM::Agents::Configuration.new
        config.default_thinking = { effort: :medium }
        expect(config.default_thinking[:effort]).to eq(:medium)
      end

      it "can be set with budget" do
        config = RubyLLM::Agents::Configuration.new
        config.default_thinking = { effort: :high, budget: 10_000 }
        expect(config.default_thinking[:budget]).to eq(10_000)
      end
    end
  end

  describe "Result" do
    describe "thinking attributes" do
      it "initializes with thinking_text" do
        result = RubyLLM::Agents::Result.new(
          content: "test",
          thinking_text: "Let me think about this..."
        )
        expect(result.thinking_text).to eq("Let me think about this...")
      end

      it "initializes with thinking_signature" do
        result = RubyLLM::Agents::Result.new(
          content: "test",
          thinking_signature: "sig_abc123"
        )
        expect(result.thinking_signature).to eq("sig_abc123")
      end

      it "initializes with thinking_tokens" do
        result = RubyLLM::Agents::Result.new(
          content: "test",
          thinking_tokens: 500
        )
        expect(result.thinking_tokens).to eq(500)
      end

      it "defaults thinking attributes to nil" do
        result = RubyLLM::Agents::Result.new(content: "test")
        expect(result.thinking_text).to be_nil
        expect(result.thinking_signature).to be_nil
        expect(result.thinking_tokens).to be_nil
      end
    end

    describe "#has_thinking?" do
      it "returns true when thinking_text is present" do
        result = RubyLLM::Agents::Result.new(
          content: "test",
          thinking_text: "Some reasoning..."
        )
        expect(result.has_thinking?).to be true
      end

      it "returns false when thinking_text is nil" do
        result = RubyLLM::Agents::Result.new(content: "test")
        expect(result.has_thinking?).to be false
      end

      it "returns false when thinking_text is empty" do
        result = RubyLLM::Agents::Result.new(
          content: "test",
          thinking_text: ""
        )
        expect(result.has_thinking?).to be false
      end
    end

    describe "#to_h" do
      it "includes thinking attributes" do
        result = RubyLLM::Agents::Result.new(
          content: "test",
          thinking_text: "Reasoning...",
          thinking_signature: "sig_123",
          thinking_tokens: 250
        )
        hash = result.to_h

        expect(hash[:thinking_text]).to eq("Reasoning...")
        expect(hash[:thinking_signature]).to eq("sig_123")
        expect(hash[:thinking_tokens]).to eq(250)
      end
    end
  end

  describe "Execution" do
    describe "#resolved_thinking" do
      let(:agent_class) do
        create_agent_class do
          thinking effort: :high, budget: 5000

          def system_prompt
            "You are a helpful assistant"
          end

          def user_prompt
            "Test prompt"
          end
        end
      end

      let(:no_thinking_class) do
        create_agent_class do
          def system_prompt
            "Test"
          end

          def user_prompt
            "Test"
          end
        end
      end

      # Stub the client building to avoid calling with_thinking on mock
      before do
        allow_any_instance_of(RubyLLM::Agents::Base).to receive(:build_client).and_return(double)
      end

      it "returns class-level thinking configuration" do
        agent = agent_class.new
        config = agent.resolved_thinking
        expect(config[:effort]).to eq(:high)
        expect(config[:budget]).to eq(5000)
      end

      it "returns runtime override when provided" do
        agent = agent_class.new(thinking: { effort: :low, budget: 1000 })
        config = agent.resolved_thinking
        expect(config[:effort]).to eq(:low)
        expect(config[:budget]).to eq(1000)
      end

      it "returns nil when thinking is explicitly disabled at runtime" do
        agent = agent_class.new(thinking: false)
        expect(agent.resolved_thinking).to be_nil
      end

      it "returns nil when thinking effort is :none" do
        agent = agent_class.new(thinking: { effort: :none })
        expect(agent.resolved_thinking).to be_nil
      end

      it "returns nil when class has no thinking and no runtime override" do
        agent = no_thinking_class.new
        expect(agent.resolved_thinking).to be_nil
      end
    end
  end

  describe "ResponseBuilding" do
    describe "#result_thinking_data" do
      let(:agent_class) do
        create_agent_class do
          def system_prompt
            "Test"
          end

          def user_prompt
            "Test"
          end
        end
      end

      let(:agent) do
        # Stub build_client to avoid MockClient issues
        allow_any_instance_of(RubyLLM::Agents::Base).to receive(:build_client).and_return(double)
        agent_class.new
      end

      it "extracts thinking from response with object methods" do
        thinking = OpenStruct.new(
          text: "My reasoning...",
          signature: "sig_abc",
          tokens: 100
        )
        response = OpenStruct.new(thinking: thinking)

        data = agent.send(:result_thinking_data, response)

        expect(data[:thinking_text]).to eq("My reasoning...")
        expect(data[:thinking_signature]).to eq("sig_abc")
        expect(data[:thinking_tokens]).to eq(100)
      end

      it "extracts thinking from response with hash access" do
        thinking = {
          text: "Hash reasoning...",
          signature: "sig_def",
          tokens: 200
        }
        response = OpenStruct.new(thinking: thinking)

        data = agent.send(:result_thinking_data, response)

        expect(data[:thinking_text]).to eq("Hash reasoning...")
        expect(data[:thinking_signature]).to eq("sig_def")
        expect(data[:thinking_tokens]).to eq(200)
      end

      it "returns empty hash when response has no thinking" do
        response = OpenStruct.new(thinking: nil)
        data = agent.send(:result_thinking_data, response)
        expect(data).to eq({})
      end

      it "returns empty hash when response does not respond to thinking" do
        response = Object.new
        data = agent.send(:result_thinking_data, response)
        expect(data).to eq({})
      end

      it "compacts nil values" do
        thinking = OpenStruct.new(
          text: "Only text",
          signature: nil,
          tokens: nil
        )
        response = OpenStruct.new(thinking: thinking)

        data = agent.send(:result_thinking_data, response)

        expect(data.keys).to eq([:thinking_text])
        expect(data[:thinking_text]).to eq("Only text")
      end
    end
  end

  describe "Instrumentation" do
    describe "#safe_extract_thinking_data" do
      let(:agent_class) do
        create_agent_class do
          def system_prompt
            "Test"
          end

          def user_prompt
            "Test"
          end
        end
      end

      let(:agent) do
        # Stub build_client to avoid MockClient issues
        allow_any_instance_of(RubyLLM::Agents::Base).to receive(:build_client).and_return(double)
        agent_class.new
      end

      it "extracts thinking data from response" do
        thinking = OpenStruct.new(
          text: "Thinking content",
          signature: "sig_123",
          tokens: 50
        )
        response = OpenStruct.new(thinking: thinking)

        data = agent.send(:safe_extract_thinking_data, response)

        expect(data[:thinking_text]).to eq("Thinking content")
        expect(data[:thinking_signature]).to eq("sig_123")
        expect(data[:thinking_tokens]).to eq(50)
      end

      it "returns empty hash when no thinking present" do
        response = OpenStruct.new(thinking: nil)
        data = agent.send(:safe_extract_thinking_data, response)
        expect(data).to eq({})
      end
    end
  end

  describe "complete agent with thinking" do
    it "supports full configuration with thinking" do
      tool = Class.new { def self.name; "TestTool"; end }

      klass = create_agent_class do
        model "claude-opus-4.5"
        temperature 0.8
        thinking effort: :high, budget: 10_000

        cache_for 2.hours
        streaming true
        tools [tool]

        param :query, required: true

        def system_prompt
          "You are a helpful assistant"
        end

        def user_prompt
          query
        end
      end

      expect(klass.model).to eq("claude-opus-4.5")
      expect(klass.temperature).to eq(0.8)
      expect(klass.thinking[:effort]).to eq(:high)
      expect(klass.thinking[:budget]).to eq(10_000)
      expect(klass.cache_enabled?).to be true
      expect(klass.streaming).to be true
      expect(klass.tools).to include(tool)
    end
  end
end
