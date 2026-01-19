# frozen_string_literal: true

require "rails_helper"
require "tempfile"

RSpec.describe RubyLLM::Agents::SpeechResult do
  describe "#initialize" do
    it "sets audio data" do
      result = described_class.new(audio: "binary audio data")
      expect(result.audio).to eq("binary audio data")
    end

    it "sets audio_url" do
      result = described_class.new(audio_url: "https://example.com/audio.mp3")
      expect(result.audio_url).to eq("https://example.com/audio.mp3")
    end

    it "sets audio metadata" do
      result = described_class.new(
        duration: 30.5,
        format: :mp3,
        file_size: 48000,
        characters: 150
      )

      expect(result.duration).to eq(30.5)
      expect(result.format).to eq(:mp3)
      expect(result.file_size).to eq(48000)
      expect(result.characters).to eq(150)
    end

    it "sets provider and model info" do
      result = described_class.new(
        provider: :openai,
        model_id: "tts-1-hd",
        voice_id: "nova",
        voice_name: "Nova"
      )

      expect(result.provider).to eq(:openai)
      expect(result.model_id).to eq("tts-1-hd")
      expect(result.voice_id).to eq("nova")
      expect(result.voice_name).to eq("Nova")
    end

    it "sets execution metadata" do
      started = Time.current
      completed = started + 2.seconds

      result = described_class.new(
        duration_ms: 2000,
        total_cost: 0.015,
        status: :success,
        tenant_id: "tenant-123",
        started_at: started,
        completed_at: completed
      )

      expect(result.duration_ms).to eq(2000)
      expect(result.total_cost).to eq(0.015)
      expect(result.status).to eq(:success)
      expect(result.tenant_id).to eq("tenant-123")
      expect(result.started_at).to eq(started)
      expect(result.completed_at).to eq(completed)
    end

    it "sets error info" do
      result = described_class.new(
        error_class: "ArgumentError",
        error_message: "Voice not found"
      )

      expect(result.error_class).to eq("ArgumentError")
      expect(result.error_message).to eq("Voice not found")
    end

    it "defaults status to :success" do
      result = described_class.new(audio: "data")
      expect(result.status).to eq(:success)
    end
  end

  describe "#success?" do
    it "returns true when no error" do
      result = described_class.new(audio: "data")
      expect(result.success?).to be true
    end

    it "returns false when error_class is set" do
      result = described_class.new(error_class: "StandardError")
      expect(result.success?).to be false
    end
  end

  describe "#error?" do
    it "returns false when no error" do
      result = described_class.new(audio: "data")
      expect(result.error?).to be false
    end

    it "returns true when error_class is set" do
      result = described_class.new(error_class: "StandardError")
      expect(result.error?).to be true
    end
  end

  describe "#save_to" do
    it "saves audio data to file" do
      result = described_class.new(audio: "test audio data")

      Tempfile.create(["test", ".mp3"]) do |file|
        result.save_to(file.path)
        expect(File.read(file.path, mode: "rb")).to eq("test audio data")
      end
    end

    it "raises error when no audio data" do
      result = described_class.new(audio: nil)

      expect {
        result.save_to("/tmp/test.mp3")
      }.to raise_error(RuntimeError, /No audio data/)
    end
  end

  describe "#to_base64" do
    it "returns base64 encoded audio" do
      result = described_class.new(audio: "test audio data")
      encoded = result.to_base64

      expect(Base64.strict_decode64(encoded)).to eq("test audio data")
    end

    it "returns nil when no audio data" do
      result = described_class.new(audio: nil)
      expect(result.to_base64).to be_nil
    end
  end

  describe "#to_data_uri" do
    it "returns data URI with default mime type" do
      result = described_class.new(audio: "test audio data", format: :mp3)
      data_uri = result.to_data_uri

      expect(data_uri).to start_with("data:audio/mpeg;base64,")
    end

    it "uses correct mime type for wav format" do
      result = described_class.new(audio: "test audio data", format: :wav)
      data_uri = result.to_data_uri

      expect(data_uri).to start_with("data:audio/wav;base64,")
    end

    it "uses correct mime type for ogg format" do
      result = described_class.new(audio: "test audio data", format: :ogg)
      data_uri = result.to_data_uri

      expect(data_uri).to start_with("data:audio/ogg;base64,")
    end

    it "returns nil when no audio data" do
      result = described_class.new(audio: nil)
      expect(result.to_data_uri).to be_nil
    end
  end

  describe "#to_h" do
    it "returns all attributes as hash" do
      started = Time.current
      completed = started + 2.seconds

      result = described_class.new(
        audio: "test data",
        audio_url: "https://example.com/audio.mp3",
        duration: 5.0,
        format: :mp3,
        file_size: 8000,
        characters: 50,
        provider: :openai,
        model_id: "tts-1",
        voice_id: "nova",
        voice_name: "Nova",
        duration_ms: 500,
        total_cost: 0.001,
        status: :success,
        started_at: started,
        completed_at: completed,
        tenant_id: "tenant-123"
      )

      hash = result.to_h

      expect(hash[:audio_url]).to eq("https://example.com/audio.mp3")
      expect(hash[:duration]).to eq(5.0)
      expect(hash[:format]).to eq(:mp3)
      expect(hash[:file_size]).to eq(8000)
      expect(hash[:characters]).to eq(50)
      expect(hash[:provider]).to eq(:openai)
      expect(hash[:model_id]).to eq("tts-1")
      expect(hash[:voice_id]).to eq("nova")
      expect(hash[:voice_name]).to eq("Nova")
      expect(hash[:duration_ms]).to eq(500)
      expect(hash[:total_cost]).to eq(0.001)
      expect(hash[:status]).to eq(:success)
      expect(hash[:tenant_id]).to eq("tenant-123")
      # audio binary data should not be in hash to avoid large outputs
      expect(hash[:has_audio]).to be true
    end

    it "sets has_audio to false when no audio" do
      result = described_class.new(audio: nil)
      expect(result.to_h[:has_audio]).to be false
    end
  end
end
