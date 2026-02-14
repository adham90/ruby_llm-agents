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
    let(:real_response) { build_real_response(content: "test response", input_tokens: 100, output_tokens: 50) }
    let(:mock_chat) { build_mock_chat_client(response: real_response) }

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
      hash_response = build_real_response(input_tokens: 100, output_tokens: 50)
      hash_response.content = { "key" => "value", "number" => 42 }
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
        instance_schema = Struct.new(:type).new("custom_override")
        override_class = Class.new(schema_agent_class) do
          define_singleton_method(:name) { "OverrideSchemaAgent" }
          define_method(:schema) { instance_schema }
        end

        override_agent = override_class.new(query: "test")
        override_agent.send(:build_client)
        expect(mock_chat).to have_received(:with_schema).with(instance_schema)
      end

      it "does not call with_schema when schema is nil" do
        no_schema_class = Class.new(described_class) do
          define_singleton_method(:name) { "NoSchemaAgent" }
          model "gpt-4o"
          param :query
          define_method(:user_prompt) { query }
        end

        no_schema_agent = no_schema_class.new(query: "test")
        no_schema_agent.send(:build_client)
        expect(mock_chat).not_to have_received(:with_schema)
      end

      it "works with hash schema value" do
        hash_schema = { type: "object", properties: { answer: { type: "string" } } }
        hash_schema_class = Class.new(described_class) do
          define_singleton_method(:name) { "HashSchemaAgent" }
          model "gpt-4o"
          param :query
          schema(hash_schema)
          define_method(:user_prompt) { query }
        end

        hash_agent = hash_schema_class.new(query: "test")
        hash_agent.send(:build_client)
        expect(mock_chat).to have_received(:with_schema).with(hash_schema)
      end

      it "child class inherits schema for build_client" do
        child_class = Class.new(schema_agent_class) do
          define_singleton_method(:name) { "ChildSchemaAgent" }
        end

        child_agent = child_class.new(query: "test")
        child_agent.send(:build_client)
        expect(mock_chat).to have_received(:with_schema).with(schema_agent_class.schema)
      end

      it "instance delegates to class-level schema" do
        schema_agent = schema_agent_class.new(query: "test")
        expect(schema_agent.schema).to eq(schema_agent_class.schema)
      end
    end

    context "with tools" do
      let(:mock_tool) { Struct.new(:name).new("search") }

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
    let(:real_response) { build_real_response }
    let(:mock_chat) { build_mock_chat_client(response: real_response) }
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
      allow(slow_chat).to receive(:ask) { sleep 0.1; real_response }

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
          final_response: real_response
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
          final_response: real_response
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
    let(:response) do
      build_real_response(
        content: "test",
        input_tokens: 100,
        output_tokens: 50,
        model_id: "gpt-4o"
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
      agent.send(:capture_response, response, context)

      expect(context.input_tokens).to eq(100)
      expect(context.output_tokens).to eq(50)
    end

    it "captures model used" do
      agent.send(:capture_response, response, context)

      expect(context.model_used).to eq("gpt-4o")
    end

    it "sets finish_reason to nil for real Message (which lacks finish_reason)" do
      agent.send(:capture_response, response, context)

      # Real RubyLLM::Message does not have finish_reason — the respond_to? guard returns nil
      expect(context.finish_reason).to be_nil
    end

    it "captures finish_reason when the response object supports it" do
      response_with_finish = Struct.new(:input_tokens, :output_tokens, :model_id, :finish_reason)
        .new(100, 50, "gpt-4o", "stop")

      agent.send(:capture_response, response_with_finish, context)

      expect(context.finish_reason).to eq("stop")
    end
  end

  describe "#calculate_costs" do
    let(:response) { build_real_response(model_id: "gpt-4o") }
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

    context "with real model pricing (no stubs)" do
      let(:model_info) { RubyLLM::Models.find("gpt-4o") }

      it "calculates input cost from real pricing" do
        agent.send(:calculate_costs, response, context)

        expected_input = (1000 / 1_000_000.0) * model_info.pricing.text_tokens.input
        expect(context.input_cost).to be_within(0.0000001).of(expected_input)
      end

      it "calculates output cost from real pricing" do
        agent.send(:calculate_costs, response, context)

        expected_output = (500 / 1_000_000.0) * model_info.pricing.text_tokens.output
        expect(context.output_cost).to be_within(0.0000001).of(expected_output)
      end

      it "calculates total cost from real pricing" do
        agent.send(:calculate_costs, response, context)

        expected_input = (1000 / 1_000_000.0) * model_info.pricing.text_tokens.input
        expected_output = (500 / 1_000_000.0) * model_info.pricing.text_tokens.output
        expected_total = (expected_input + expected_output).round(6)
        expect(context.total_cost).to be_within(0.0000001).of(expected_total)
      end

      it "produces non-zero costs (regression: mocks previously hid zero-cost bug)" do
        agent.send(:calculate_costs, response, context)

        expect(context.input_cost).to be > 0
        expect(context.output_cost).to be > 0
        expect(context.total_cost).to be > 0
      end
    end

    context "when tokens are zero" do
      before do
        context.input_tokens = 0
        context.output_tokens = 0
      end

      it "returns zero costs" do
        agent.send(:calculate_costs, response, context)

        expect(context.input_cost).to eq(0.0)
        expect(context.output_cost).to eq(0.0)
        expect(context.total_cost).to eq(0.0)
      end
    end

    context "when pricing object is nil" do
      before do
        allow(RubyLLM::Models).to receive(:find).with("gpt-4o").and_return(build_model_info_nil_pricing)
      end

      it "defaults costs to zero" do
        agent.send(:calculate_costs, response, context)

        expect(context.input_cost).to eq(0.0)
        expect(context.output_cost).to eq(0.0)
        expect(context.total_cost).to eq(0.0)
      end
    end

    context "when text_tokens is nil" do
      before do
        allow(RubyLLM::Models).to receive(:find).with("gpt-4o").and_return(build_model_info_nil_text_tokens)
      end

      it "defaults costs to zero" do
        agent.send(:calculate_costs, response, context)

        expect(context.input_cost).to eq(0.0)
        expect(context.output_cost).to eq(0.0)
        expect(context.total_cost).to eq(0.0)
      end
    end

    context "with partial pricing (output is nil)" do
      before do
        allow(RubyLLM::Models).to receive(:find).with("gpt-4o")
          .and_return(build_model_info_with_pricing(input_price: 1.0, output_price: nil))
      end

      it "calculates input cost and defaults output to zero" do
        agent.send(:calculate_costs, response, context)

        expect(context.input_cost).to be_within(0.0000001).of(0.001)
        expect(context.output_cost).to eq(0.0)
        expect(context.total_cost).to be_within(0.0000001).of(0.001)
      end
    end

    context "when model info is not available" do
      let(:response) { build_real_response(model_id: "nonexistent-model-xyz") }

      it "does not calculate costs" do
        agent.send(:calculate_costs, response, context)

        # find_model_info rescues the error and returns nil — costs stay at default 0.0
        expect(context.input_cost).to eq(0.0)
        expect(context.output_cost).to eq(0.0)
        expect(context.total_cost).to eq(0.0)
      end
    end

    context "when RubyLLM::Models is not defined" do
      it "handles gracefully" do
        allow(agent).to receive(:find_model_info).and_return(nil)

        expect { agent.send(:calculate_costs, response, context) }.not_to raise_error
      end
    end
  end

  describe "#build_result" do
    let(:real_response) { build_real_response }
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
      result = agent.send(:build_result, "test content", real_response, context)

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
      result = agent.send(:build_result, "test content", real_response, context)

      expect(result.started_at).to be_present
      expect(result.completed_at).to be_present
    end
  end

  describe "#process_response" do
    it "returns string content as-is" do
      response = build_real_response(content: "plain text")
      result = agent.send(:process_response, response)
      expect(result).to eq("plain text")
    end

    it "symbolizes hash keys" do
      hash_response = build_real_response(content: "placeholder")
      hash_response.content = { "key" => "value", "nested" => { "inner" => "data" } }

      result = agent.send(:process_response, hash_response)

      expect(result[:key]).to eq("value")
      expect(result[:nested]).to eq({ "inner" => "data" }) # Only top-level keys symbolized
    end
  end

  describe "#result_thinking_data" do
    it "returns empty hash when no thinking" do
      response = build_real_response(thinking: nil)

      result = agent.send(:result_thinking_data, response)

      expect(result).to eq({})
    end

    it "extracts thinking data from real Thinking object" do
      thinking = RubyLLM::Thinking.new(text: "thinking text", signature: "sig123")
      response = build_real_response(thinking: thinking)

      result = agent.send(:result_thinking_data, response)

      expect(result[:thinking_text]).to eq("thinking text")
      expect(result[:thinking_signature]).to eq("sig123")
      # Real Thinking has no tokens method — thinking_tokens is nil (correctly omitted by .compact)
      expect(result).not_to have_key(:thinking_tokens)
    end

    it "handles hash-based thinking" do
      response = build_real_response(thinking: { text: "thinking text", signature: "sig123", tokens: 500 })

      result = agent.send(:result_thinking_data, response)

      expect(result[:thinking_text]).to eq("thinking text")
      expect(result[:thinking_signature]).to eq("sig123")
      expect(result[:thinking_tokens]).to eq(500)
    end
  end

  describe "#safe_extract_thinking_data" do
    it "returns empty hash on errors" do
      error_response = Class.new {
        def thinking = raise(StandardError, "error")
      }.new

      result = agent.send(:safe_extract_thinking_data, error_response)

      expect(result).to eq({})
    end
  end
end
