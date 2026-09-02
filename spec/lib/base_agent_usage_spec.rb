# frozen_string_literal: true

require "rails_helper"

RSpec.describe RubyLLM::Agents::BaseAgent, "usage accounting across tool loops" do
  let(:tool_error) { Class.new(StandardError) }

  let(:agent_class) do
    Class.new(described_class) do
      def self.name
        "UsageAccountingAgent"
      end

      model "gpt-4o"

      def user_prompt
        "open Instagram"
      end
    end
  end

  let(:agent) { agent_class.new }
  let(:context) do
    RubyLLM::Agents::Pipeline::Context.new(
      input: {},
      agent_class: agent_class,
      agent_instance: agent
    )
  end

  before do
    stub_agent_configuration
  end

  def assistant(input:, output:, model: "gpt-4o")
    build_real_response(content: "working", input_tokens: input, output_tokens: output, model_id: model)
  end

  def user_message(content = "tool result")
    RubyLLM::Message.new(role: :user, content: content)
  end

  # Mirrors a real chat client: `seeded` transcript rows exist before ask;
  # `appended` rows land in the history during the tool loop. When `error`
  # is nil the ask succeeds and returns the last appended message.
  def build_looping_client(appended, seeded: [], error: nil)
    history = seeded.dup
    client = double("RubyLLM::Chat")
    allow(client).to receive(:with_temperature).and_return(client)
    allow(client).to receive(:with_instructions).and_return(client)
    allow(client).to receive(:with_schema).and_return(client)
    allow(client).to receive(:with_tools).and_return(client)
    allow(client).to receive(:with_thinking).and_return(client)
    allow(client).to receive(:on_tool_call).and_return(client)
    allow(client).to receive(:on_tool_result).and_return(client)
    allow(client).to receive(:messages) { history }
    allow(client).to receive(:ask) do
      history.concat(appended)
      raise error if error

      appended.last
    end
    agent.instance_variable_set(:@client, client)
    client
  end

  describe "#execute_llm_call failure path" do
    it "sums usage across the tool loop when ask raises mid-loop" do
      client = build_looping_client(
        [
          assistant(input: 100, output: 20),
          user_message,
          assistant(input: 200, output: 30)
        ],
        error: tool_error.new("tool timed out")
      )

      expect {
        agent.send(:execute_llm_call, client, context)
      }.to raise_error(tool_error, "tool timed out")

      expect(context.input_tokens).to eq(300)
      expect(context.output_tokens).to eq(50)
      expect(context.model_used).to eq("gpt-4o")
      expect(context[:llm_usage]).to eq(
        "requests" => 2,
        "last_input_tokens" => 200,
        "last_output_tokens" => 30
      )
    end

    it "prices the summed usage through cost calculation" do
      pricing = build_model_info_with_pricing(input_price: 2.0, output_price: 10.0)
      allow(agent).to receive(:find_model_info).and_return(pricing)
      client = build_looping_client(
        [assistant(input: 600_000, output: 300_000), assistant(input: 400_000, output: 200_000)],
        error: tool_error.new("tool timed out")
      )

      expect { agent.send(:execute_llm_call, client, context) }.to raise_error(tool_error)

      expect(context.input_cost).to eq(2.0)
      expect(context.output_cost).to eq(5.0)
      expect(context.total_cost).to eq(7.0)
    end

    it "recovers usage on cooperative cancellation inside the tool loop" do
      client = build_looping_client(
        [assistant(input: 50, output: 10)],
        error: RubyLLM::Agents::CancelledError.new("cancel requested")
      )

      expect {
        agent.send(:execute_llm_call, client, context)
      }.to raise_error(RubyLLM::Agents::CancelledError)

      expect(context.input_tokens).to eq(50)
      expect(context.output_tokens).to eq(10)
    end

    it "ignores assistant history seeded before the call (transcript replay)" do
      client = build_looping_client(
        [user_message],
        seeded: [assistant(input: 999, output: 99)],
        error: tool_error.new("tool timed out")
      )

      expect { agent.send(:execute_llm_call, client, context) }.to raise_error(tool_error)

      expect(context.input_tokens.to_i).to eq(0)
      expect(context.output_tokens.to_i).to eq(0)
    end

    it "leaves context untouched when the failure precedes any completed response" do
      client = build_looping_client([user_message], error: tool_error.new("tool timed out"))

      expect { agent.send(:execute_llm_call, client, context) }.to raise_error(tool_error)

      expect(context.input_tokens.to_i).to eq(0)
      expect(context.output_tokens.to_i).to eq(0)
    end

    it "never masks the original error when recovery itself fails" do
      client = double("RubyLLM::Chat")
      allow(client).to receive(:messages).and_raise(RuntimeError, "history unavailable")
      allow(client).to receive(:ask).and_raise(tool_error, "original")
      agent.instance_variable_set(:@client, client)

      expect {
        agent.send(:execute_llm_call, client, context)
      }.to raise_error(tool_error, "original")
    end
  end

  describe "#capture_response" do
    it "sums usage across the tool loop on the successful path too" do
      client = build_looping_client(
        [
          assistant(input: 1_000, output: 50),
          user_message,
          assistant(input: 2_000, output: 40)
        ]
      )

      response = agent.send(:execute_llm_call, client, context)
      agent.send(:capture_response, response, context)

      expect(context.input_tokens).to eq(3_000)
      expect(context.output_tokens).to eq(90)
      expect(context[:llm_usage]).to eq(
        "requests" => 2,
        "last_input_tokens" => 2_000,
        "last_output_tokens" => 40
      )
    end

    it "keeps the single-response numbers when the history is unavailable" do
      response = assistant(input: 100, output: 50)
      client = double("RubyLLM::Chat")
      allow(client).to receive(:messages).and_return([])
      allow(client).to receive(:ask).and_return(response)
      agent.instance_variable_set(:@client, client)

      agent.send(:execute_llm_call, client, context)
      agent.send(:capture_response, response, context)

      expect(context.input_tokens).to eq(100)
      expect(context.output_tokens).to eq(50)
      expect(context[:llm_usage]).to be_nil
    end

    it "re-baselines per attempt so a retry overwrites instead of double counting" do
      failing = build_looping_client(
        [assistant(input: 200, output: 30)],
        error: tool_error.new("tool timed out")
      )
      expect { agent.send(:execute_llm_call, failing, context) }.to raise_error(tool_error)
      expect(context.input_tokens).to eq(200)

      retrying = build_looping_client([assistant(input: 10, output: 5)])
      response = agent.send(:execute_llm_call, retrying, context)
      agent.send(:capture_response, response, context)

      expect(context.input_tokens).to eq(10)
      expect(context.output_tokens).to eq(5)
      expect(context[:llm_usage]).to eq(
        "requests" => 1,
        "last_input_tokens" => 10,
        "last_output_tokens" => 5
      )
    end
  end

  describe "#execute" do
    it "sums usage across the loop through the full execution path" do
      client = build_looping_client(
        [
          assistant(input: 100, output: 10),
          user_message,
          assistant(input: 200, output: 20)
        ]
      )
      stub_ruby_llm_chat(client)

      agent.send(:execute, context)

      expect(context.input_tokens).to eq(300)
      expect(context.output_tokens).to eq(30)
      expect(context.output).to be_a(RubyLLM::Agents::Result)
      expect(context.output.content).to eq("working")
    end
  end
end
