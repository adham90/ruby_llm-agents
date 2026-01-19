# frozen_string_literal: true

require "rails_helper"

RSpec.describe RubyLLM::Agents::TranscriptionResult do
  describe "#initialize" do
    it "sets text" do
      result = described_class.new(text: "Hello world")
      expect(result.text).to eq("Hello world")
    end

    it "sets segments" do
      segments = [
        { start: 0.0, end: 1.0, text: "Hello" },
        { start: 1.0, end: 2.0, text: "world" }
      ]
      result = described_class.new(segments: segments)
      expect(result.segments).to eq(segments)
    end

    it "sets words" do
      words = [
        { start: 0.0, end: 0.5, text: "Hello" },
        { start: 0.5, end: 1.0, text: "world" }
      ]
      result = described_class.new(words: words)
      expect(result.words).to eq(words)
    end

    it "sets audio metadata" do
      result = described_class.new(
        audio_duration: 120.5,
        audio_format: "mp3",
        language: "en",
        detected_language: "en"
      )

      expect(result.audio_duration).to eq(120.5)
      expect(result.audio_format).to eq("mp3")
      expect(result.language).to eq("en")
      expect(result.detected_language).to eq("en")
    end

    it "sets execution metadata" do
      started = Time.current
      completed = started + 2.seconds

      result = described_class.new(
        model_id: "whisper-1",
        duration_ms: 2000,
        total_cost: 0.006,
        status: :success,
        tenant_id: "tenant-123",
        started_at: started,
        completed_at: completed
      )

      expect(result.model_id).to eq("whisper-1")
      expect(result.duration_ms).to eq(2000)
      expect(result.total_cost).to eq(0.006)
      expect(result.status).to eq(:success)
      expect(result.tenant_id).to eq("tenant-123")
      expect(result.started_at).to eq(started)
      expect(result.completed_at).to eq(completed)
    end

    it "sets speaker diarization data" do
      speakers = ["Speaker 1", "Speaker 2"]
      speaker_segments = [
        { speaker: "Speaker 1", start: 0.0, end: 5.0, text: "Hello" },
        { speaker: "Speaker 2", start: 5.0, end: 10.0, text: "Hi there" }
      ]

      result = described_class.new(
        speakers: speakers,
        speaker_segments: speaker_segments
      )

      expect(result.speakers).to eq(speakers)
      expect(result.speaker_segments).to eq(speaker_segments)
    end

    it "sets error info" do
      result = described_class.new(
        error_class: "ArgumentError",
        error_message: "Invalid audio format"
      )

      expect(result.error_class).to eq("ArgumentError")
      expect(result.error_message).to eq("Invalid audio format")
    end

    it "defaults status to :success" do
      result = described_class.new(text: "Hello")
      expect(result.status).to eq(:success)
    end
  end

  describe "#success?" do
    it "returns true when no error" do
      result = described_class.new(text: "Hello")
      expect(result.success?).to be true
    end

    it "returns false when error_class is set" do
      result = described_class.new(error_class: "StandardError")
      expect(result.success?).to be false
    end
  end

  describe "#error?" do
    it "returns false when no error" do
      result = described_class.new(text: "Hello")
      expect(result.error?).to be false
    end

    it "returns true when error_class is set" do
      result = described_class.new(error_class: "StandardError")
      expect(result.error?).to be true
    end
  end

  describe "#srt" do
    it "generates SRT format from segments" do
      result = described_class.new(
        text: "Hello world",
        segments: [
          { start: 0.0, end: 2.5, text: "Hello world" },
          { start: 3.0, end: 5.5, text: "How are you?" }
        ]
      )

      srt = result.srt
      expect(srt).to include("1")
      expect(srt).to include("00:00:00,000 --> 00:00:02,500")
      expect(srt).to include("Hello world")
      expect(srt).to include("2")
      expect(srt).to include("00:00:03,000 --> 00:00:05,500")
      expect(srt).to include("How are you?")
    end

    it "returns empty string when no segments" do
      result = described_class.new(text: "Hello")
      expect(result.srt).to eq("")
    end
  end

  describe "#vtt" do
    it "generates VTT format from segments" do
      result = described_class.new(
        text: "Hello world",
        segments: [
          { start: 0.0, end: 2.5, text: "Hello world" },
          { start: 3.0, end: 5.5, text: "How are you?" }
        ]
      )

      vtt = result.vtt
      expect(vtt).to start_with("WEBVTT")
      expect(vtt).to include("00:00:00.000 --> 00:00:02.500")
      expect(vtt).to include("Hello world")
      expect(vtt).to include("00:00:03.000 --> 00:00:05.500")
      expect(vtt).to include("How are you?")
    end

    it "returns WEBVTT header when no segments" do
      result = described_class.new(text: "Hello")
      expect(result.vtt).to eq("WEBVTT\n\n")
    end
  end

  describe "#words_per_minute" do
    it "calculates words per minute" do
      result = described_class.new(
        text: "Hello world how are you today my friend",
        audio_duration: 60.0
      )

      expect(result.words_per_minute).to eq(8)
    end

    it "returns nil when no audio duration" do
      result = described_class.new(text: "Hello")
      expect(result.words_per_minute).to be_nil
    end

    it "returns nil when audio duration is zero" do
      result = described_class.new(text: "Hello", audio_duration: 0)
      expect(result.words_per_minute).to be_nil
    end
  end

  describe "#segment_at" do
    it "finds segment at given timestamp" do
      result = described_class.new(
        segments: [
          { start: 0.0, end: 5.0, text: "First segment" },
          { start: 5.0, end: 10.0, text: "Second segment" },
          { start: 10.0, end: 15.0, text: "Third segment" }
        ]
      )

      segment = result.segment_at(7.5)
      expect(segment[:text]).to eq("Second segment")
    end

    it "returns nil when no segment at timestamp" do
      result = described_class.new(
        segments: [
          { start: 0.0, end: 5.0, text: "First segment" }
        ]
      )

      expect(result.segment_at(10.0)).to be_nil
    end

    it "returns nil when no segments" do
      result = described_class.new(text: "Hello")
      expect(result.segment_at(0.0)).to be_nil
    end
  end

  describe "#text_between" do
    it "extracts text between timestamps" do
      result = described_class.new(
        segments: [
          { start: 0.0, end: 5.0, text: "First segment." },
          { start: 5.0, end: 10.0, text: "Second segment." },
          { start: 10.0, end: 15.0, text: "Third segment." }
        ]
      )

      text = result.text_between(2.0, 12.0)
      expect(text).to include("First segment.")
      expect(text).to include("Second segment.")
      expect(text).to include("Third segment.")
    end

    it "returns empty string when no matching segments" do
      result = described_class.new(
        segments: [
          { start: 0.0, end: 5.0, text: "First segment" }
        ]
      )

      expect(result.text_between(10.0, 15.0)).to eq("")
    end
  end

  describe "#to_h" do
    it "returns all attributes as hash" do
      started = Time.current
      completed = started + 2.seconds

      result = described_class.new(
        text: "Hello world",
        segments: [{ start: 0.0, end: 1.0, text: "Hello world" }],
        words: [{ start: 0.0, end: 0.5, text: "Hello" }],
        audio_duration: 1.0,
        audio_format: "mp3",
        language: "en",
        model_id: "whisper-1",
        duration_ms: 500,
        total_cost: 0.001,
        status: :success,
        started_at: started,
        completed_at: completed,
        tenant_id: "tenant-123"
      )

      hash = result.to_h

      expect(hash[:text]).to eq("Hello world")
      expect(hash[:segments]).to be_an(Array)
      expect(hash[:words]).to be_an(Array)
      expect(hash[:audio_duration]).to eq(1.0)
      expect(hash[:audio_format]).to eq("mp3")
      expect(hash[:language]).to eq("en")
      expect(hash[:model_id]).to eq("whisper-1")
      expect(hash[:duration_ms]).to eq(500)
      expect(hash[:total_cost]).to eq(0.001)
      expect(hash[:status]).to eq(:success)
      expect(hash[:tenant_id]).to eq("tenant-123")
    end
  end
end
