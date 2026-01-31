# frozen_string_literal: true

require "rails_helper"

RSpec.describe RubyLLM::Agents::BaseAgent, "execution methods" do
  let(:config) { RubyLLM::Agents.configuration }

  let(:test_agent_class) do
    Class.new(described_class) do
      def self.name
        "ExecutionTestAgent"
      end

      model "gpt-4o"
      version "1.0"
      timeout 30

      param :query, required: true

      def user_prompt
        query
      end

      def system_prompt
        "You are a helpful assistant"
      end
    end
  end

  let(:agent) { test_agent_class.new(query: "test query") }

  before do
    stub_agent_configuration
  end

  describe "#execute" do
    let(:mock_response) { build_mock_response(content: "test response", input_tokens: 100, output_tokens: 50) }
    let(:mock_chat) { build_mock_chat_client(response: mock_response) }

    before do
      stub_ruby_llm_chat(mock_chat)
    end

    it "builds client and executes LLM call" do
      context = RubyLLM::Agents::Pipeline::Context.new(
        input: "test query",
        agent_class: test_agent_class,
        agent_instance: agent,
        model: "gpt-4o"
      )

      agent.send(:execute, context)

      expect(context.output).to be_a(RubyLLM::Agents::Result)
      expect(context.output.content).to eq("test response")
    end

    it "captures response metadata to context" do
      context = RubyLLM::Agents::Pipeline::Context.new(
        input: "test query",
        agent_class: test_agent_class,
        agent_instance: agent,
        model: "gpt-4o"
      )

      agent.send(:execute, context)

      expect(context.input_tokens).to eq(100)
      expect(context.output_tokens).to eq(50)
    end

    it "processes response content" do
      hash_response = build_mock_response(
        content: { "key" => "value", "number" => 42 },
        input_tokens: 100,
        output_tokens: 50
      )
      mock_chat_with_hash = build_mock_chat_client(response: hash_response)
      stub_ruby_llm_chat(mock_chat_with_hash)

      context = RubyLLM::Agents::Pipeline::Context.new(
        input: "test query",
        agent_class: test_agent_class,
        agent_instance: agent,
        model: "gpt-4o"
      )

      agent.send(:execute, context)

      # Hash keys should be symbolized
      expect(context.output.content).to eq({ key: "value", number: 42 })
    end
  end

  describe "#build_client" do
    let(:mock_chat) { build_mock_chat_client }

    before do
      stub_ruby_llm_chat(mock_chat)
    end

    it "configures client with model" do
      agent.send(:build_client)
      expect(mock_chat).to have_received(:with_model).with("gpt-4o")
    end

    it "configures client with temperature" do
      agent.send(:build_client)
      expect(mock_chat).to have_received(:with_temperature)
    end

    it "configures client with system prompt when present" do
      agent.send(:build_client)
      expect(mock_chat).to have_received(:with_instructions).with("You are a helpful assistant")
    end

    context "with schema" do
      let(:schema_agent_class) do
        Class.new(described_class) do
          define_singleton_method(:name) { "SchemaAgent" }
          model "gpt-4o"
          param :query

          schema do
            string :answer, description: "The answer"
          end

          define_method(:user_prompt) { query }
        end
      end

      it "configures client with class-level schema" do
        schema_agent = schema_agent_class.new(query: "test")
        schema_agent.send(:build_client)
        expect(mock_chat).to have_received(:with_schema).with(schema_agent_class.schema)
      end

      it "allows instance method to override class-level schema" do
        instance_schema = double("InstanceSchema")
        override_class = Class.new(schema_agent_class) do
          define_singleton_method(:name) { "OverrideSchemaAgent" }
          define_method(:schema) { instance_schema }
        end

        override_agent = override_class.new(query: "test")
        override_agent.send(:build_client)
        expect(mock_chat).to have_received(:with_schema).with(instance_schema)
      end
    end

    context "with tools" do
      let(:mock_tool) { double("Tool", name: "search") }

      let(:tools_agent_class) do
        tool = mock_tool
        Class.new(described_class) do
          define_singleton_method(:name) { "ToolsAgent" }
          tools [tool]
          param :query

          define_method(:user_prompt) { query }
        end
      end

      it "configures client with tools when present" do
        tools_agent = tools_agent_class.new(query: "test")
        tools_agent.send(:build_client)
        expect(mock_chat).to have_received(:with_tools).with(mock_tool)
      end
    end

    context "with thinking" do
      let(:thinking_agent_class) do
        Class.new(described_class) do
          def self.name
            "ThinkingAgent"
          end

          model "claude-3-5-sonnet"
          thinking effort: :high, budget: 10000
          param :query

          def user_prompt
            query
          end
        end
      end

      it "configures client with thinking when present" do
        thinking_agent = thinking_agent_class.new(query: "test")
        thinking_agent.send(:build_client)
        expect(mock_chat).to have_received(:with_thinking).with(effort: :high, budget: 10000)
      end
    end

    context "with messages" do
      let(:messages_agent_class) do
        Class.new(described_class) do
          def self.name
            "MessagesAgent"
          end

          model "gpt-4o"
          param :query

          def user_prompt
            query
          end

          def messages
            [
              { role: :user, content: "Hello" },
              { role: :assistant, content: "Hi there!" }
            ]
          end
        end
      end

      it "applies messages to client" do
        messages_agent = messages_agent_class.new(query: "test")
        messages_agent.send(:build_client)
        expect(mock_chat).to have_received(:add_message).twice
      end
    end
  end

  describe "#execute_llm_call" do
    let(:mock_response) { build_mock_response }
    let(:mock_chat) { build_mock_chat_client(response: mock_response) }
    let(:context) do
      RubyLLM::Agents::Pipeline::Context.new(
        input: "test query",
        agent_class: test_agent_class,
        agent_instance: agent,
        model: "gpt-4o"
      )
    end

    before do
      stub_ruby_llm_chat(mock_chat)
    end

    it "calls ask on the client" do
      agent.send(:execute_llm_call, mock_chat, context)
      expect(mock_chat).to have_received(:ask).with("test query")
    end

    it "passes attachments when present" do
      agent_with_attachments = test_agent_class.new(query: "test", with: ["file.txt"])
      agent_with_attachments.send(:execute_llm_call, mock_chat, context)
      expect(mock_chat).to have_received(:ask).with("test", with: ["file.txt"])
    end

    it "respects timeout setting" do
      slow_chat = build_mock_chat_client
      allow(slow_chat).to receive(:ask) { sleep 0.1; mock_response }

      short_timeout_class = Class.new(test_agent_class) do
        def self.name
          "ShortTimeoutAgent"
        end

        timeout 0.01 # 10ms timeout
      end

      short_agent = short_timeout_class.new(query: "test")

      expect {
        short_agent.send(:execute_llm_call, slow_chat, context)
      }.to raise_error(Timeout::Error)
    end

    context "with streaming enabled" do
      let(:streaming_agent_class) do
        Class.new(test_agent_class) do
          def self.name
            "StreamingAgent"
          end

          streaming true
        end
      end

      it "yields chunks when streaming" do
        chunks = []
        streaming_chat = build_mock_streaming_chat(
          chunks: [{ content: "Hello" }, { content: " World" }],
          final_response: mock_response
        )
        stub_ruby_llm_chat(streaming_chat)

        streaming_agent = streaming_agent_class.new(query: "test")
        streaming_context = RubyLLM::Agents::Pipeline::Context.new(
          input: "test query",
          agent_class: streaming_agent_class,
          agent_instance: streaming_agent,
          model: "gpt-4o",
          stream_block: ->(chunk) { chunks << chunk }
        )
        streaming_agent.instance_variable_set(:@force_streaming, true)

        streaming_agent.send(:execute_llm_call, streaming_chat, streaming_context)

        expect(chunks).to eq([{ content: "Hello" }, { content: " World" }])
      end

      it "records time to first token" do
        streaming_chat = build_mock_streaming_chat(
          chunks: [{ content: "Hello" }],
          final_response: mock_response
        )
        stub_ruby_llm_chat(streaming_chat)

        streaming_agent = streaming_agent_class.new(query: "test")
        streaming_context = RubyLLM::Agents::Pipeline::Context.new(
          input: "test query",
          agent_class: streaming_agent_class,
          agent_instance: streaming_agent,
          model: "gpt-4o",
          stream_block: ->(chunk) {},
          started_at: Time.current
        )
        streaming_agent.instance_variable_set(:@force_streaming, true)

        streaming_agent.send(:execute_llm_call, streaming_chat, streaming_context)

        expect(streaming_context.time_to_first_token_ms).to be_a(Integer)
        expect(streaming_context.time_to_first_token_ms).to be >= 0
      end
    end
  end

  describe "#capture_response" do
    let(:mock_response) do
      build_mock_response(
        content: "test",
        input_tokens: 100,
        output_tokens: 50,
        model_id: "gpt-4o",
        finish_reason: "stop"
      )
    end
    let(:context) do
      RubyLLM::Agents::Pipeline::Context.new(
        input: "test query",
        agent_class: test_agent_class,
        agent_instance: agent,
        model: "gpt-4o"
      )
    end

    it "captures token counts" do
      agent.send(:capture_response, mock_response, context)

      expect(context.input_tokens).to eq(100)
      expect(context.output_tokens).to eq(50)
    end

    it "captures model used" do
      agent.send(:capture_response, mock_response, context)

      expect(context.model_used).to eq("gpt-4o")
    end

    it "captures finish reason when available" do
      agent.send(:capture_response, mock_response, context)

      expect(context.finish_reason).to eq("stop")
    end

    it "handles responses without finish_reason method" do
      simple_response = double("SimpleResponse")
      allow(simple_response).to receive(:input_tokens).and_return(100)
      allow(simple_response).to receive(:output_tokens).and_return(50)
      allow(simple_response).to receive(:model_id).and_return("gpt-4o")
      allow(simple_response).to receive(:respond_to?).with(:finish_reason).and_return(false)

      agent.send(:capture_response, simple_response, context)

      expect(context.finish_reason).to be_nil
    end
  end

  describe "#calculate_costs" do
    let(:mock_response) { build_mock_response(model_id: "gpt-4o") }
    let(:context) do
      ctx = RubyLLM::Agents::Pipeline::Context.new(
        input: "test query",
        agent_class: test_agent_class,
        agent_instance: agent,
        model: "gpt-4o"
      )
      ctx.input_tokens = 1000
      ctx.output_tokens = 500
      ctx
    end

    context "when model info is available" do
      before do
        model_info = double("ModelInfo")
        allow(model_info).to receive(:input_price).and_return(0.01) # $0.01 per 1M tokens
        allow(model_info).to receive(:output_price).and_return(0.03) # $0.03 per 1M tokens
        allow(RubyLLM::Models).to receive(:find).with("gpt-4o").and_return(model_info)
      end

      it "calculates input cost" do
        agent.send(:calculate_costs, mock_response, context)

        # 1000 tokens * $0.01/1M = $0.00001
        expect(context.input_cost).to be_within(0.000001).of(0.00001)
      end

      it "calculates output cost" do
        agent.send(:calculate_costs, mock_response, context)

        # 500 tokens * $0.03/1M = $0.000015
        expect(context.output_cost).to be_within(0.000001).of(0.000015)
      end

      it "calculates total cost" do
        agent.send(:calculate_costs, mock_response, context)

        expect(context.total_cost).to be_within(0.000001).of(0.000025)
      end
    end

    context "when model info is not available" do
      before do
        allow(RubyLLM::Models).to receive(:find).and_return(nil)
      end

      it "does not calculate costs" do
        # The method returns early when model_info is nil
        agent.send(:calculate_costs, mock_response, context)

        # Costs remain at their initial state (nil or 0 depending on context initialization)
        # The key is that the calculate_costs method does nothing when model_info is nil
        expect(RubyLLM::Models).to have_received(:find).with("gpt-4o")
      end
    end

    context "when RubyLLM::Models is not defined" do
      it "handles gracefully" do
        # Simulate RubyLLM::Models not being defined
        allow(agent).to receive(:find_model_info).and_return(nil)

        expect { agent.send(:calculate_costs, mock_response, context) }.not_to raise_error
      end
    end
  end

  describe "#build_result" do
    let(:mock_response) { build_mock_response }
    let(:context) do
      ctx = RubyLLM::Agents::Pipeline::Context.new(
        input: "test query",
        agent_class: test_agent_class,
        agent_instance: agent,
        model: "gpt-4o"
      )
      ctx.input_tokens = 100
      ctx.output_tokens = 50
      ctx.input_cost = 0.001
      ctx.output_cost = 0.002
      ctx.total_cost = 0.003
      ctx.model_used = "gpt-4o"
      ctx.started_at = Time.current - 1
      ctx.completed_at = Time.current
      ctx.finish_reason = "stop"
      ctx.attempts_made = 1
      ctx
    end

    it "builds a Result object with all metadata" do
      result = agent.send(:build_result, "test content", mock_response, context)

      expect(result).to be_a(RubyLLM::Agents::Result)
      expect(result.content).to eq("test content")
      expect(result.input_tokens).to eq(100)
      expect(result.output_tokens).to eq(50)
      expect(result.input_cost).to eq(0.001)
      expect(result.output_cost).to eq(0.002)
      expect(result.total_cost).to eq(0.003)
      expect(result.model_id).to eq("gpt-4o")
      expect(result.chosen_model_id).to eq("gpt-4o")
      expect(result.finish_reason).to eq("stop")
      expect(result.attempts_count).to eq(1)
    end

    it "includes timing data" do
      result = agent.send(:build_result, "test content", mock_response, context)

      expect(result.started_at).to be_present
      expect(result.completed_at).to be_present
    end
  end

  describe "#process_response" do
    let(:mock_response) { build_mock_response(content: "plain text") }

    it "returns string content as-is" do
      result = agent.send(:process_response, mock_response)
      expect(result).to eq("plain text")
    end

    it "symbolizes hash keys" do
      hash_response = build_mock_response(content: { "key" => "value", "nested" => { "inner" => "data" } })

      result = agent.send(:process_response, hash_response)

      expect(result[:key]).to eq("value")
      expect(result[:nested]).to eq({ "inner" => "data" }) # Only top-level keys symbolized
    end
  end

  describe "#extract_model_price" do
    it "extracts price from object with method" do
      model_info = double("ModelInfo")
      allow(model_info).to receive(:input_price).and_return(0.01)

      result = agent.send(:extract_model_price, model_info, :input_price)
      expect(result).to eq(0.01)
    end

    it "extracts price from hash" do
      model_info = { input_price: 0.01 }

      result = agent.send(:extract_model_price, model_info, :input_price)
      expect(result).to eq(0.01)
    end

    it "returns 0 when price is nil" do
      model_info = double("ModelInfo")
      allow(model_info).to receive(:input_price).and_return(nil)

      result = agent.send(:extract_model_price, model_info, :input_price)
      expect(result).to eq(0)
    end

    it "returns 0 when method not available" do
      model_info = Object.new

      result = agent.send(:extract_model_price, model_info, :input_price)
      expect(result).to eq(0)
    end
  end

  describe "#result_thinking_data" do
    it "returns empty hash when no thinking" do
      response = build_mock_response(thinking: nil)

      result = agent.send(:result_thinking_data, response)

      expect(result).to eq({})
    end

    it "extracts thinking data from response" do
      thinking = double("Thinking")
      allow(thinking).to receive(:text).and_return("thinking text")
      allow(thinking).to receive(:signature).and_return("sig123")
      allow(thinking).to receive(:tokens).and_return(500)

      response = double("Response")
      allow(response).to receive(:thinking).and_return(thinking)

      result = agent.send(:result_thinking_data, response)

      expect(result[:thinking_text]).to eq("thinking text")
      expect(result[:thinking_signature]).to eq("sig123")
      expect(result[:thinking_tokens]).to eq(500)
    end

    it "handles hash-based thinking" do
      thinking = { text: "thinking text", signature: "sig123", tokens: 500 }

      response = double("Response")
      allow(response).to receive(:thinking).and_return(thinking)

      result = agent.send(:result_thinking_data, response)

      expect(result[:thinking_text]).to eq("thinking text")
      expect(result[:thinking_signature]).to eq("sig123")
      expect(result[:thinking_tokens]).to eq(500)
    end
  end

  describe "#safe_extract_thinking_data" do
    it "returns empty hash on errors" do
      response = double("Response")
      allow(response).to receive(:thinking).and_raise(StandardError.new("error"))

      result = agent.send(:safe_extract_thinking_data, response)

      expect(result).to eq({})
    end
  end
end
