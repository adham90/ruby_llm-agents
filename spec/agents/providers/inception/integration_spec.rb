# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Mercury agent integration" do
  include ChatMockHelpers

  before do
    stub_agent_configuration(track_executions: false)
  end

  describe "basic Mercury chat agent" do
    let(:agent_class) do
      Class.new(RubyLLM::Agents::Base) do
        model "mercury-2"
        temperature 0.7
        system "You are a helpful assistant."
        user "{question}"

        def self.name
          "TestMercuryAgent"
        end
      end
    end

    it "configures the correct model" do
      expect(agent_class.model).to eq("mercury-2")
    end

    it "configures the correct temperature" do
      expect(agent_class.temperature).to eq(0.7)
    end

    it "auto-registers the question param" do
      expect(agent_class.params).to have_key(:question)
    end

    it "executes successfully and returns content" do
      response = build_mock_response(
        content: "A diffusion LLM generates tokens in parallel.",
        model_id: "mercury-2",
        input_tokens: 50,
        output_tokens: 20
      )
      client = build_mock_chat_client(response: response)
      stub_ruby_llm_chat(client)

      result = agent_class.call(question: "What is a diffusion LLM?")

      expect(result).to be_success
      expect(result.content).to eq("A diffusion LLM generates tokens in parallel.")
    end

    it "passes the model to RubyLLM.chat" do
      response = build_mock_response(content: "Hi", model_id: "mercury-2")
      client = build_mock_chat_client(response: response)

      expect(RubyLLM).to receive(:chat).with(hash_including(model: "mercury-2")).and_return(client)

      agent_class.call(question: "Hello")
    end

    it "sets the system prompt" do
      response = build_mock_response(content: "Test", model_id: "mercury-2")
      client = build_mock_chat_client(response: response)
      stub_ruby_llm_chat(client)

      expect(client).to receive(:with_instructions).with("You are a helpful assistant.").and_return(client)

      agent_class.call(question: "Test")
    end

    it "sets the temperature" do
      response = build_mock_response(content: "Test", model_id: "mercury-2")
      client = build_mock_chat_client(response: response)
      stub_ruby_llm_chat(client)

      expect(client).to receive(:with_temperature).with(0.7).and_return(client)

      agent_class.call(question: "Test")
    end

    it "passes the user prompt to ask" do
      response = build_mock_response(content: "Answer", model_id: "mercury-2")
      client = build_mock_chat_client(response: response)
      stub_ruby_llm_chat(client)

      expect(client).to receive(:ask).with("What is Ruby?").and_return(response)

      agent_class.call(question: "What is Ruby?")
    end
  end

  describe "Mercury coder agent" do
    let(:coder_class) do
      Class.new(RubyLLM::Agents::Base) do
        model "mercury-coder-small"
        temperature 0.0
        system "You are an expert programmer."
        user "Language: {language}\n\nTask: {task}"
        param :language, default: "ruby"

        def self.name
          "TestMercuryCoderAgent"
        end
      end
    end

    it "uses mercury-coder-small model" do
      expect(coder_class.model).to eq("mercury-coder-small")
    end

    it "uses temperature 0.0 for deterministic output" do
      expect(coder_class.temperature).to eq(0.0)
    end

    it "has language param with default" do
      expect(coder_class.params[:language]).to include(default: "ruby")
    end

    it "executes with default language" do
      response = build_mock_response(
        content: "def hello\n  puts 'hello'\nend",
        model_id: "mercury-coder-small",
        input_tokens: 30,
        output_tokens: 15
      )
      client = build_mock_chat_client(response: response)
      stub_ruby_llm_chat(client)

      result = coder_class.call(task: "Write a hello function")

      expect(result).to be_success
      expect(result.content).to include("def hello")
    end

    it "allows overriding the language" do
      response = build_mock_response(
        content: "def hello():\n    print('hello')",
        model_id: "mercury-coder-small"
      )
      client = build_mock_chat_client(response: response)
      stub_ruby_llm_chat(client)

      expect(client).to receive(:ask)
        .with("Language: python\n\nTask: Write a hello function")
        .and_return(response)

      result = coder_class.call(language: "python", task: "Write a hello function")
      expect(result).to be_success
    end
  end

  describe "Mercury agent with structured output" do
    let(:structured_class) do
      Class.new(RubyLLM::Agents::Base) do
        model "mercury-2"
        system "You are a sentiment analyzer."
        user "Analyze: {text}"

        returns do
          string :sentiment, description: "positive, negative, or neutral"
          number :score, description: "Sentiment score from -1 to 1"
        end

        def self.name
          "TestMercuryStructuredAgent"
        end
      end
    end

    it "defines a schema" do
      expect(structured_class.schema).not_to be_nil
    end

    it "passes schema to the client" do
      response = build_mock_response(
        content: {sentiment: "positive", score: 0.8}.to_json,
        model_id: "mercury-2"
      )
      client = build_mock_chat_client(response: response)
      stub_ruby_llm_chat(client)

      expect(client).to receive(:with_schema).and_return(client)

      structured_class.call(text: "I love this product!")
    end
  end

  describe "Mercury agent with reliability" do
    let(:reliable_class) do
      Class.new(RubyLLM::Agents::Base) do
        model "mercury-2"
        system "You are helpful."
        user "{query}"

        on_failure do
          retries times: 2, backoff: :linear
          fallback to: "mercury"
        end

        def self.name
          "TestMercuryReliableAgent"
        end
      end
    end

    it "configures retry settings" do
      config = reliable_class.reliability_config
      expect(config[:retries][:max]).to eq(2)
      expect(config[:retries][:backoff]).to eq(:linear)
    end

    it "configures fallback model" do
      expect(reliable_class.reliability_config[:fallback_models]).to include("mercury")
    end

    it "reports as reliability configured" do
      expect(reliable_class.reliability_configured?).to be true
    end
  end

  describe "Mercury agent execution tracking" do
    before do
      stub_agent_configuration(track_executions: true, async_logging: false)
    end

    let(:tracked_class) do
      Class.new(RubyLLM::Agents::Base) do
        model "mercury-2"
        system "You are helpful."
        user "{question}"

        def self.name
          "TestMercuryTrackedAgent"
        end
      end
    end

    it "records execution with mercury model" do
      response = build_mock_response(
        content: "Mercury response",
        model_id: "mercury-2",
        input_tokens: 50,
        output_tokens: 25
      )
      client = build_mock_chat_client(response: response)
      stub_ruby_llm_chat(client)

      expect {
        tracked_class.call(question: "Test tracking")
      }.to change(RubyLLM::Agents::Execution, :count).by(1)

      execution = RubyLLM::Agents::Execution.last
      expect(execution.agent_type).to eq("TestMercuryTrackedAgent")
      expect(execution.model_id).to eq("mercury-2")
      expect(execution.status).to eq("success")
      expect(execution.input_tokens).to eq(50)
      expect(execution.output_tokens).to eq(25)
    end

    it "records the execution detail with prompts" do
      response = build_mock_response(
        content: "Mercury response",
        model_id: "mercury-2"
      )
      client = build_mock_chat_client(response: response)
      stub_ruby_llm_chat(client)

      tracked_class.call(question: "Hello Mercury")

      execution = RubyLLM::Agents::Execution.last
      detail = execution.detail
      expect(detail).to be_present
      expect(detail.system_prompt).to eq("You are helpful.")
      expect(detail.user_prompt).to eq("Hello Mercury")
      # Response is stored as a hash with content, tokens, model_id
      expect(detail.response).to be_a(Hash)
      expect(detail.response["content"]).to eq("Mercury response")
    end
  end

  describe "provider capabilities integration" do
    let(:capabilities) { RubyLLM::Agents::Providers::Inception::Capabilities }

    it "correctly differentiates chat and coder models" do
      expect(capabilities.supports_functions?("mercury-2")).to be true
      expect(capabilities.supports_json_mode?("mercury-2")).to be true
      expect(capabilities.capabilities_for("mercury-2")).to include("reasoning")

      expect(capabilities.supports_functions?("mercury-coder-small")).to be false
      expect(capabilities.supports_json_mode?("mercury-coder-small")).to be false
      expect(capabilities.capabilities_for("mercury-coder-small")).to eq(["streaming"])
    end

    it "provides consistent pricing structure across all models" do
      %w[mercury-2 mercury mercury-coder-small mercury-edit].each do |model_id|
        pricing = capabilities.pricing_for(model_id)
        expect(pricing).to have_key(:text_tokens)
        expect(pricing[:text_tokens]).to have_key(:standard)
        expect(pricing[:text_tokens][:standard]).to have_key(:input_per_million)
        expect(pricing[:text_tokens][:standard]).to have_key(:output_per_million)
      end
    end

    it "reports correct model types" do
      expect(capabilities.model_type("mercury-2")).to eq("chat")
      expect(capabilities.model_type("mercury")).to eq("chat")
      expect(capabilities.model_type("mercury-coder-small")).to eq("code")
      expect(capabilities.model_type("mercury-edit")).to eq("code")
    end
  end
end
