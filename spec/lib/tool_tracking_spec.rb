# frozen_string_literal: true

require "rails_helper"

RSpec.describe RubyLLM::Agents::Base::ToolTracking do
  # Test class that includes the module
  let(:test_class) do
    Class.new do
      include RubyLLM::Agents::Base::ToolTracking

      attr_accessor :accumulated_tool_calls

      def initialize
        @accumulated_tool_calls = []
      end
    end
  end

  let(:instance) { test_class.new }

  describe "#reset_accumulated_tool_calls!" do
    it "resets accumulated_tool_calls to empty array" do
      instance.accumulated_tool_calls = [{ id: "1", name: "test" }]
      instance.reset_accumulated_tool_calls!
      expect(instance.accumulated_tool_calls).to eq([])
    end

    it "creates the array if not initialized" do
      instance.instance_variable_set(:@accumulated_tool_calls, nil)
      instance.reset_accumulated_tool_calls!
      expect(instance.accumulated_tool_calls).to eq([])
    end
  end

  describe "#extract_tool_calls_from_client" do
    context "when client does not respond to messages" do
      it "returns early without error" do
        client = double("client")
        expect { instance.extract_tool_calls_from_client(client) }.not_to raise_error
        expect(instance.accumulated_tool_calls).to eq([])
      end
    end

    context "when client has no messages" do
      it "does not add any tool calls" do
        client = double("client", messages: [])
        instance.extract_tool_calls_from_client(client)
        expect(instance.accumulated_tool_calls).to eq([])
      end
    end

    context "when messages have no tool calls" do
      it "does not add any tool calls" do
        user_message = double("message", role: :user)
        assistant_message = double("message", role: :assistant, tool_calls: nil)
        allow(assistant_message).to receive(:respond_to?).with(:tool_calls).and_return(true)

        client = double("client", messages: [user_message, assistant_message])
        instance.extract_tool_calls_from_client(client)
        expect(instance.accumulated_tool_calls).to eq([])
      end
    end

    context "when messages have tool calls" do
      it "extracts tool calls from assistant messages" do
        tool_call = double("tool_call",
          id: "call_123",
          name: "search_tool",
          arguments: { query: "test" }
        )
        allow(tool_call).to receive(:respond_to?).with(:to_h).and_return(false)

        assistant_message = double("message",
          role: :assistant,
          tool_calls: { "call_123" => tool_call }
        )
        allow(assistant_message).to receive(:respond_to?).with(:tool_calls).and_return(true)

        client = double("client", messages: [assistant_message])
        instance.extract_tool_calls_from_client(client)

        expect(instance.accumulated_tool_calls.size).to eq(1)
        expect(instance.accumulated_tool_calls.first["name"]).to eq("search_tool")
      end

      it "skips non-assistant messages" do
        tool_call = double("tool_call", id: "1", name: "tool", arguments: {})
        allow(tool_call).to receive(:respond_to?).with(:to_h).and_return(false)

        user_message = double("message", role: :user, tool_calls: { "1" => tool_call })
        allow(user_message).to receive(:respond_to?).with(:tool_calls).and_return(true)

        client = double("client", messages: [user_message])
        instance.extract_tool_calls_from_client(client)
        expect(instance.accumulated_tool_calls).to eq([])
      end

      it "handles multiple tool calls in a single message" do
        tool_call_1 = double("tool_call", id: "1", name: "tool_a", arguments: {})
        tool_call_2 = double("tool_call", id: "2", name: "tool_b", arguments: {})
        allow(tool_call_1).to receive(:respond_to?).with(:to_h).and_return(false)
        allow(tool_call_2).to receive(:respond_to?).with(:to_h).and_return(false)

        assistant_message = double("message",
          role: :assistant,
          tool_calls: { "1" => tool_call_1, "2" => tool_call_2 }
        )
        allow(assistant_message).to receive(:respond_to?).with(:tool_calls).and_return(true)

        client = double("client", messages: [assistant_message])
        instance.extract_tool_calls_from_client(client)

        expect(instance.accumulated_tool_calls.size).to eq(2)
        expect(instance.accumulated_tool_calls.map { |tc| tc["name"] }).to contain_exactly("tool_a", "tool_b")
      end

      it "handles multiple messages with tool calls" do
        tool_call_1 = double("tool_call", id: "1", name: "tool_a", arguments: {})
        tool_call_2 = double("tool_call", id: "2", name: "tool_b", arguments: {})
        allow(tool_call_1).to receive(:respond_to?).with(:to_h).and_return(false)
        allow(tool_call_2).to receive(:respond_to?).with(:to_h).and_return(false)

        message_1 = double("message", role: :assistant, tool_calls: { "1" => tool_call_1 })
        message_2 = double("message", role: :assistant, tool_calls: { "2" => tool_call_2 })
        allow(message_1).to receive(:respond_to?).with(:tool_calls).and_return(true)
        allow(message_2).to receive(:respond_to?).with(:tool_calls).and_return(true)

        client = double("client", messages: [message_1, message_2])
        instance.extract_tool_calls_from_client(client)

        expect(instance.accumulated_tool_calls.size).to eq(2)
      end
    end

    context "when message does not respond to tool_calls" do
      it "skips the message" do
        assistant_message = double("message", role: :assistant)
        allow(assistant_message).to receive(:respond_to?).with(:tool_calls).and_return(false)

        client = double("client", messages: [assistant_message])
        instance.extract_tool_calls_from_client(client)
        expect(instance.accumulated_tool_calls).to eq([])
      end
    end
  end

  describe "#serialize_tool_call" do
    context "when tool_call responds to to_h" do
      it "uses to_h and transforms keys to strings" do
        tool_call = double("tool_call")
        allow(tool_call).to receive(:respond_to?).with(:to_h).and_return(true)
        allow(tool_call).to receive(:to_h).and_return({
          id: "call_123",
          name: "search",
          arguments: { query: "test" }
        })

        result = instance.serialize_tool_call(tool_call)

        expect(result).to eq({
          "id" => "call_123",
          "name" => "search",
          "arguments" => { query: "test" }
        })
      end

      it "handles nested hashes" do
        tool_call = double("tool_call")
        allow(tool_call).to receive(:respond_to?).with(:to_h).and_return(true)
        allow(tool_call).to receive(:to_h).and_return({
          id: "1",
          name: "tool",
          arguments: { nested: { key: "value" } }
        })

        result = instance.serialize_tool_call(tool_call)
        expect(result["arguments"]).to eq({ nested: { key: "value" } })
      end
    end

    context "when tool_call does not respond to to_h" do
      it "builds hash from accessors" do
        tool_call = double("tool_call",
          id: "call_456",
          name: "calculator",
          arguments: { expression: "2+2" }
        )
        allow(tool_call).to receive(:respond_to?).with(:to_h).and_return(false)

        result = instance.serialize_tool_call(tool_call)

        expect(result).to eq({
          "id" => "call_456",
          "name" => "calculator",
          "arguments" => { expression: "2+2" }
        })
      end

      it "handles nil arguments" do
        tool_call = double("tool_call", id: "1", name: "tool", arguments: nil)
        allow(tool_call).to receive(:respond_to?).with(:to_h).and_return(false)

        result = instance.serialize_tool_call(tool_call)
        expect(result["arguments"]).to be_nil
      end
    end
  end
end
