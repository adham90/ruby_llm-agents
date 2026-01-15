# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Streaming Support" do
  # Silence deprecation warnings for tests
  before do
    RubyLLM::Agents::Deprecations.silenced = true
  end

  after do
    RubyLLM::Agents::Deprecations.silenced = false
  end

  let(:streaming_agent_class) do
    Class.new(RubyLLM::Agents::Base) do
      model "gpt-4o"
      streaming true
      param :query, required: true

      def user_prompt
        query
      end
    end
  end

  let(:non_streaming_agent_class) do
    Class.new(RubyLLM::Agents::Base) do
      model "gpt-4o"
      streaming false
      param :query, required: true

      def user_prompt
        query
      end
    end
  end

  describe ".stream class method" do
    it "exists on agent classes" do
      expect(streaming_agent_class).to respond_to(:stream)
    end

    it "requires a block" do
      expect {
        streaming_agent_class.stream(query: "test")
      }.to raise_error(ArgumentError, "Block required for streaming")
    end

    it "forces streaming even on non-streaming agents" do
      agent = non_streaming_agent_class.new(query: "test")
      expect(agent.send(:streaming_enabled?)).to be false

      # When using stream method, it sets @force_streaming
      agent.instance_variable_set(:@force_streaming, true)
      expect(agent.send(:streaming_enabled?)).to be true
    end
  end

  describe "streaming_enabled?" do
    it "returns true when class has streaming enabled" do
      agent = streaming_agent_class.new(query: "test")
      expect(agent.send(:streaming_enabled?)).to be true
    end

    it "returns false when class has streaming disabled" do
      agent = non_streaming_agent_class.new(query: "test")
      expect(agent.send(:streaming_enabled?)).to be false
    end

    it "returns true when force_streaming is set" do
      agent = non_streaming_agent_class.new(query: "test")
      agent.instance_variable_set(:@force_streaming, true)
      expect(agent.send(:streaming_enabled?)).to be true
    end
  end

  describe "streaming DSL" do
    it "can enable streaming via DSL" do
      klass = Class.new(RubyLLM::Agents::Base) do
        streaming true
      end

      expect(klass.streaming).to be true
    end

    it "can disable streaming via DSL" do
      klass = Class.new(RubyLLM::Agents::Base) do
        streaming false
      end

      expect(klass.streaming).to be false
    end

    it "inherits streaming setting from parent" do
      parent = Class.new(RubyLLM::Agents::Base) do
        streaming true
      end

      child = Class.new(parent)

      expect(child.streaming).to be true
    end
  end

  describe "Result with streaming" do
    it "Result#streaming? returns true for streaming results" do
      result = RubyLLM::Agents::Result.new(
        content: "test",
        streaming: true
      )

      expect(result.streaming?).to be true
    end

    it "Result#streaming? returns false for non-streaming results" do
      result = RubyLLM::Agents::Result.new(
        content: "test",
        streaming: false
      )

      expect(result.streaming?).to be false
    end

    it "Result tracks time_to_first_token_ms" do
      result = RubyLLM::Agents::Result.new(
        content: "test",
        streaming: true,
        time_to_first_token_ms: 150
      )

      expect(result.time_to_first_token_ms).to eq(150)
    end
  end
end
