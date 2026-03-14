# frozen_string_literal: true

require "rails_helper"

RSpec.describe RubyLLM::Agents::StreamEvent do
  describe "#initialize" do
    it "sets type and data" do
      event = described_class.new(:chunk, {content: "Hello"})
      expect(event.type).to eq(:chunk)
      expect(event.data).to eq({content: "Hello"})
    end

    it "defaults data to empty hash" do
      event = described_class.new(:error)
      expect(event.data).to eq({})
    end
  end

  describe "#chunk?" do
    it "returns true for :chunk type" do
      expect(described_class.new(:chunk).chunk?).to be true
    end

    it "returns false for other types" do
      expect(described_class.new(:tool_start).chunk?).to be false
    end
  end

  describe "#tool_event?" do
    it "returns true for :tool_start" do
      expect(described_class.new(:tool_start).tool_event?).to be true
    end

    it "returns true for :tool_end" do
      expect(described_class.new(:tool_end).tool_event?).to be true
    end

    it "returns false for :chunk" do
      expect(described_class.new(:chunk).tool_event?).to be false
    end

    it "returns false for :agent_start" do
      expect(described_class.new(:agent_start).tool_event?).to be false
    end
  end

  describe "#agent_event?" do
    it "returns true for :agent_start" do
      expect(described_class.new(:agent_start).agent_event?).to be true
    end

    it "returns true for :agent_end" do
      expect(described_class.new(:agent_end).agent_event?).to be true
    end

    it "returns false for :tool_start" do
      expect(described_class.new(:tool_start).agent_event?).to be false
    end
  end

  describe "#error?" do
    it "returns true for :error type" do
      expect(described_class.new(:error).error?).to be true
    end

    it "returns false for other types" do
      expect(described_class.new(:chunk).error?).to be false
    end
  end

  describe "#to_h" do
    it "returns hash with type and data" do
      event = described_class.new(:tool_start, {tool_name: "bash", input: {cmd: "ls"}})
      expect(event.to_h).to eq({type: :tool_start, data: {tool_name: "bash", input: {cmd: "ls"}}})
    end
  end
end

RSpec.describe "Stream events integration" do
  let(:test_agent_class) do
    Class.new(RubyLLM::Agents::BaseAgent) do
      def self.name
        "StreamEventsTestAgent"
      end

      model "gpt-4o"
      streaming true

      param :query, required: true

      def user_prompt
        query
      end
    end
  end

  before do
    stub_agent_configuration
  end

  describe "streaming with stream_events: true" do
    it "wraps chunks as StreamEvent objects" do
      chunk = double("Chunk", content: "Hello")
      mock_client = build_mock_streaming_chat(
        chunks: [chunk],
        final_response: build_real_response(content: "Hello")
      )
      stub_ruby_llm_chat(mock_client)

      events = []
      test_agent_class.call(query: "test", stream_events: true) do |event|
        events << event
      end

      chunk_events = events.select(&:chunk?)
      expect(chunk_events.length).to eq(1)
      expect(chunk_events.first).to be_a(RubyLLM::Agents::StreamEvent)
      expect(chunk_events.first.data[:content]).to eq("Hello")
    end
  end

  describe "streaming without stream_events (default)" do
    it "passes raw chunks unchanged" do
      chunk = double("Chunk", content: "Hello")
      mock_client = build_mock_streaming_chat(
        chunks: [chunk],
        final_response: build_real_response(content: "Hello")
      )
      stub_ruby_llm_chat(mock_client)

      received = []
      test_agent_class.call(query: "test") do |c|
        received << c
      end

      expect(received.first).to eq(chunk)
      expect(received.first).not_to be_a(RubyLLM::Agents::StreamEvent)
    end
  end

  describe "tool lifecycle events" do
    let(:tool_class) do
      Class.new(RubyLLM::Agents::Tool) do
        def self.name
          "StreamTestTool"
        end

        description "A test tool"
        param :input, desc: "Input", required: true

        def execute(input:)
          "result: #{input}"
        end
      end
    end

    let(:agent_with_tools) do
      tool = tool_class
      Class.new(RubyLLM::Agents::BaseAgent) do
        define_method(:self_name) { "StreamToolTestAgent" }
        define_singleton_method(:name) { "StreamToolTestAgent" }

        model "gpt-4o"
        streaming true
        tools [tool]

        param :query, required: true

        def user_prompt
          query
        end
      end
    end

    it "emits tool_start and tool_end events when stream_events: true" do
      tool_call_obj = double("ToolCall",
        id: "call_123",
        name: "stream_test_tool",
        arguments: {input: "hello"})
      tool_result_obj = "result: hello"

      # Build a mock that triggers tool callbacks
      mock_client = build_mock_chat_client(response: build_real_response(content: "Done"))

      # Capture on_tool_call and on_tool_result blocks
      tool_call_block = nil
      tool_result_block = nil
      allow(mock_client).to receive(:on_tool_call) do |&blk|
        tool_call_block = blk
        mock_client
      end
      allow(mock_client).to receive(:on_tool_result) do |&blk|
        tool_result_block = blk
        mock_client
      end

      # When ask is called, trigger the callbacks to simulate tool execution
      allow(mock_client).to receive(:ask) do |_, **_opts, &block|
        tool_call_block&.call(tool_call_obj)
        tool_result_block&.call(tool_result_obj)
        build_real_response(content: "Done")
      end

      stub_ruby_llm_chat(mock_client)

      events = []
      agent_with_tools.call(query: "test", stream_events: true) do |event|
        events << event
      end

      tool_events = events.select(&:tool_event?)
      expect(tool_events.length).to eq(2)

      start_event = tool_events.find { |e| e.type == :tool_start }
      expect(start_event.data[:tool_name]).to eq("stream_test_tool")

      end_event = tool_events.find { |e| e.type == :tool_end }
      expect(end_event.data[:tool_name]).to eq("stream_test_tool")
      expect(end_event.data[:status]).to eq("success")
      expect(end_event.data[:duration_ms]).to be_a(Integer)
    end

    it "does not emit tool events when stream_events is not set" do
      tool_call_obj = double("ToolCall",
        id: "call_123",
        name: "stream_test_tool",
        arguments: {input: "hello"})
      tool_result_obj = "result: hello"

      mock_client = build_mock_chat_client(response: build_real_response(content: "Done"))

      tool_call_block = nil
      tool_result_block = nil
      allow(mock_client).to receive(:on_tool_call) do |&blk|
        tool_call_block = blk
        mock_client
      end
      allow(mock_client).to receive(:on_tool_result) do |&blk|
        tool_result_block = blk
        mock_client
      end

      allow(mock_client).to receive(:ask) do |_, **_opts, &block|
        tool_call_block&.call(tool_call_obj)
        tool_result_block&.call(tool_result_obj)
        build_real_response(content: "Done")
      end

      stub_ruby_llm_chat(mock_client)

      received = []
      agent_with_tools.call(query: "test") do |chunk|
        received << chunk
      end

      # Should not receive any StreamEvent objects (only raw chunks)
      stream_events = received.select { |r| r.is_a?(RubyLLM::Agents::StreamEvent) }
      expect(stream_events).to be_empty
    end
  end
end
