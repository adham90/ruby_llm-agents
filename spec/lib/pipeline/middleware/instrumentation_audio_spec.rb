# frozen_string_literal: true

require "rails_helper"

RSpec.describe RubyLLM::Agents::Pipeline::Middleware::Instrumentation, "audio persistence" do
  let(:agent_class) do
    Class.new do
      def self.name
        "TestSpeaker"
      end

      def self.agent_type
        :audio
      end

      def self.model
        "tts-1"
      end
    end
  end

  let(:app) { double("app") }
  let(:middleware) { described_class.new(app, agent_class) }
  let(:config) { double("config") }

  let(:mock_execution) do
    double("RubyLLM::Agents::Execution",
      id: 456,
      status: "running",
      detail: nil,
      class: RubyLLM::Agents::Execution)
  end

  def build_context(options = {})
    RubyLLM::Agents::Pipeline::Context.new(
      input: "Hello world",
      agent_class: agent_class,
      **options
    )
  end

  before do
    allow(RubyLLM::Agents).to receive(:configuration).and_return(config)
    allow(config).to receive(:track_audio).and_return(true)
    allow(config).to receive(:track_executions).and_return(true)
    allow(config).to receive(:track_embeddings).and_return(true)
    allow(config).to receive(:track_image_generation).and_return(true)
    allow(config).to receive(:async_logging).and_return(false)
    allow(config).to receive(:persist_prompts).and_return(false)
    allow(config).to receive(:persist_responses).and_return(false)
    allow(config).to receive(:multi_tenancy_enabled?).and_return(false)

    allow(RubyLLM::Agents::Execution).to receive(:create!).and_return(mock_execution)
    allow(mock_execution).to receive(:update!)
    allow(mock_execution).to receive(:create_detail!)
  end

  describe "persist_audio_data enabled with SpeechResult output" do
    let(:speech_result) do
      RubyLLM::Agents::SpeechResult.new(
        audio: "fake-binary-audio-data",
        audio_url: "https://example.com/audio.mp3",
        format: :mp3,
        duration: 2.5,
        file_size: 12_345,
        voice_id: "nova",
        provider: :openai
      )
    end

    before do
      allow(config).to receive(:respond_to?).with(:persist_audio_data).and_return(true)
      allow(config).to receive(:persist_audio_data).and_return(true)
    end

    it "stores audio_data_uri in the response detail" do
      context = build_context

      allow(app).to receive(:call) do |ctx|
        ctx.output = speech_result
        ctx
      end

      expect(mock_execution).to receive(:create_detail!).with(
        hash_including(
          response: hash_including(
            audio_data_uri: start_with("data:audio/mpeg;base64,"),
            audio_url: "https://example.com/audio.mp3",
            format: "mp3",
            duration: 2.5,
            file_size: 12_345,
            voice_id: "nova",
            provider: "openai"
          )
        )
      )

      middleware.call(context)
    end

    it "includes all audio metadata fields" do
      context = build_context

      allow(app).to receive(:call) do |ctx|
        ctx.output = speech_result
        ctx
      end

      saved_detail = nil
      allow(mock_execution).to receive(:create_detail!) do |data|
        saved_detail = data
      end

      middleware.call(context)

      response = saved_detail[:response]
      expect(response[:audio_data_uri]).to start_with("data:audio/mpeg;base64,")
      expect(response[:format]).to eq("mp3")
      expect(response[:duration]).to eq(2.5)
      expect(response[:file_size]).to eq(12_345)
      expect(response[:voice_id]).to eq("nova")
      expect(response[:provider]).to eq("openai")
    end
  end

  describe "persist_audio_data disabled (default)" do
    before do
      allow(config).to receive(:respond_to?).with(:persist_audio_data).and_return(true)
      allow(config).to receive(:persist_audio_data).and_return(false)
    end

    it "does NOT store audio_data_uri in response" do
      speech_result = RubyLLM::Agents::SpeechResult.new(
        audio: "fake-binary-audio-data",
        audio_url: "https://example.com/audio.mp3",
        format: :mp3,
        duration: 2.5,
        voice_id: "nova",
        provider: :openai
      )

      context = build_context

      allow(app).to receive(:call) do |ctx|
        ctx.output = speech_result
        ctx
      end

      saved_detail = nil
      allow(mock_execution).to receive(:create_detail!) do |data|
        saved_detail = data
      end

      middleware.call(context)

      response = saved_detail&.dig(:response)
      expect(response).not_to have_key(:audio_data_uri) if response
    end

    it "still stores audio_url when present" do
      speech_result = RubyLLM::Agents::SpeechResult.new(
        audio: "fake-binary-audio-data",
        audio_url: "https://example.com/audio.mp3",
        format: :mp3,
        provider: :openai
      )

      context = build_context

      allow(app).to receive(:call) do |ctx|
        ctx.output = speech_result
        ctx
      end

      saved_detail = nil
      allow(mock_execution).to receive(:create_detail!) do |data|
        saved_detail = data
      end

      middleware.call(context)

      response = saved_detail[:response]
      expect(response).to include(audio_url: "https://example.com/audio.mp3")
    end

    it "does not create response if no audio_url" do
      speech_result = RubyLLM::Agents::SpeechResult.new(
        audio: "fake-binary-audio-data",
        format: :mp3,
        provider: :openai
      )

      context = build_context

      allow(app).to receive(:call) do |ctx|
        ctx.output = speech_result
        ctx
      end

      saved_detail = nil
      allow(mock_execution).to receive(:create_detail!) do |data|
        saved_detail = data
      end

      middleware.call(context)

      # With persist_audio_data off and no audio_url, response should be absent or empty
      response = saved_detail&.dig(:response)
      expect(response).to be_nil
    end
  end

  describe "non-audio executions are unaffected" do
    let(:text_agent_class) do
      Class.new do
        def self.name
          "TestAgent"
        end

        def self.agent_type
          :text
        end

        def self.model
          "gpt-4o"
        end
      end
    end

    let(:text_middleware) { described_class.new(app, text_agent_class) }

    before do
      allow(config).to receive(:respond_to?).with(:persist_audio_data).and_return(true)
      allow(config).to receive(:persist_audio_data).and_return(true)
    end

    it "does not add audio fields to non-SpeechResult output" do
      context = RubyLLM::Agents::Pipeline::Context.new(
        input: "test",
        agent_class: text_agent_class
      )

      allow(app).to receive(:call) do |ctx|
        ctx.output = "plain text response"
        ctx
      end

      saved_detail = nil
      allow(mock_execution).to receive(:create_detail!) do |data|
        saved_detail = data
      end

      text_middleware.call(context)

      response = saved_detail&.dig(:response)
      expect(response).to be_nil
    end
  end

  describe "config without persist_audio_data (backward compatibility)" do
    before do
      allow(config).to receive(:respond_to?).with(:persist_audio_data).and_return(false)
    end

    it "does not error when config lacks persist_audio_data" do
      speech_result = RubyLLM::Agents::SpeechResult.new(
        audio: "fake-binary-audio-data",
        audio_url: "https://example.com/audio.mp3",
        format: :mp3,
        provider: :openai
      )

      context = build_context

      allow(app).to receive(:call) do |ctx|
        ctx.output = speech_result
        ctx
      end

      expect { middleware.call(context) }.not_to raise_error
    end

    it "still stores audio_url even without persist_audio_data config" do
      speech_result = RubyLLM::Agents::SpeechResult.new(
        audio_url: "https://example.com/audio.mp3",
        format: :mp3,
        provider: :openai
      )

      context = build_context

      allow(app).to receive(:call) do |ctx|
        ctx.output = speech_result
        ctx
      end

      saved_detail = nil
      allow(mock_execution).to receive(:create_detail!) do |data|
        saved_detail = data
      end

      middleware.call(context)

      response = saved_detail[:response]
      expect(response).to include(audio_url: "https://example.com/audio.mp3")
    end
  end
end
