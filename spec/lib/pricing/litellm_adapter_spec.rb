# frozen_string_literal: true

require "rails_helper"

RSpec.describe RubyLLM::Agents::Pricing::LiteLLMAdapter do
  before do
    RubyLLM::Agents::Pricing::DataStore.refresh!
    stub_request(:get, RubyLLM::Agents::Pricing::DataStore::LITELLM_URL)
      .to_return(status: 200, body: litellm_data.to_json)
  end

  after do
    RubyLLM::Agents::Pricing::DataStore.refresh!
  end

  let(:litellm_data) do
    {
      "whisper-1" => {
        "mode" => "audio_transcription",
        "input_cost_per_second" => 0.0001
      },
      "gpt-4o-transcribe" => {
        "mode" => "audio_transcription",
        "input_cost_per_audio_token" => 0.000006
      },
      "gpt-4o" => {
        "input_cost_per_token" => 0.0000025,
        "output_cost_per_token" => 0.00001,
        "mode" => "chat"
      },
      "tts-1" => {
        "input_cost_per_character" => 0.000015,
        "mode" => "audio_speech"
      },
      "dall-e-3" => {
        "input_cost_per_image" => 0.04,
        "mode" => "image_generation"
      },
      "text-embedding-3-small" => {
        "input_cost_per_token" => 0.00000002,
        "mode" => "embedding"
      },
      "audio_transcription/deepgram-nova" => {
        "mode" => "audio_transcription",
        "input_cost_per_second" => 0.00015
      }
    }
  end

  describe ".find_model" do
    context "text LLM models" do
      it "returns normalized pricing for gpt-4o" do
        result = described_class.find_model("gpt-4o")
        expect(result[:input_cost_per_token]).to eq(0.0000025)
        expect(result[:output_cost_per_token]).to eq(0.00001)
        expect(result[:mode]).to eq("chat")
        expect(result[:source]).to eq(:litellm)
      end
    end

    context "transcription models" do
      it "returns per-second pricing for whisper-1" do
        result = described_class.find_model("whisper-1")
        expect(result[:input_cost_per_second]).to eq(0.0001)
        expect(result[:mode]).to eq("audio_transcription")
        expect(result[:source]).to eq(:litellm)
      end

      it "returns per-audio-token pricing for gpt-4o-transcribe" do
        result = described_class.find_model("gpt-4o-transcribe")
        expect(result[:input_cost_per_audio_token]).to eq(0.000006)
        expect(result[:source]).to eq(:litellm)
      end
    end

    context "TTS models" do
      it "returns per-character pricing for tts-1" do
        result = described_class.find_model("tts-1")
        expect(result[:input_cost_per_character]).to eq(0.000015)
        expect(result[:source]).to eq(:litellm)
      end
    end

    context "image models" do
      it "returns per-image pricing for dall-e-3" do
        result = described_class.find_model("dall-e-3")
        expect(result[:input_cost_per_image]).to eq(0.04)
        expect(result[:source]).to eq(:litellm)
      end
    end

    context "embedding models" do
      it "returns per-token pricing for text-embedding-3-small" do
        result = described_class.find_model("text-embedding-3-small")
        expect(result[:input_cost_per_token]).to eq(0.00000002)
        expect(result[:mode]).to eq("embedding")
        expect(result[:source]).to eq(:litellm)
      end
    end

    context "prefixed model keys" do
      it "finds models with audio_transcription/ prefix" do
        result = described_class.find_model("deepgram-nova")
        expect(result[:input_cost_per_second]).to eq(0.00015)
      end
    end

    context "unknown models" do
      it "returns nil" do
        expect(described_class.find_model("totally-fake-model-xyz")).to be_nil
      end
    end

    context "when LiteLLM data is unavailable" do
      before do
        RubyLLM::Agents::Pricing::DataStore.refresh!
        stub_request(:get, RubyLLM::Agents::Pricing::DataStore::LITELLM_URL)
          .to_return(status: 500, body: "error")
      end

      it "returns nil" do
        expect(described_class.find_model("gpt-4o")).to be_nil
      end
    end
  end
end
