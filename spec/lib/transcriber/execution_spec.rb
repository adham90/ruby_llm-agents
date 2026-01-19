# frozen_string_literal: true

require "rails_helper"

RSpec.describe RubyLLM::Agents::Transcriber::Execution do
  # Mock RubyLLM.transcribe response
  let(:mock_response) do
    double(
      "TranscriptionResponse",
      text: "Hello world",
      segments: [
        { start: 0.0, end: 1.0, text: "Hello" },
        { start: 1.0, end: 2.0, text: "world" }
      ],
      words: nil,
      language: "en",
      duration: 2.0,
      model: "whisper-1"
    )
  end

  let(:test_transcriber) do
    Class.new(RubyLLM::Agents::Transcriber) do
      model "whisper-1"
    end
  end

  before do
    # Disable tracking for most tests
    allow(RubyLLM::Agents.configuration).to receive(:track_transcriptions).and_return(false)
  end

  describe "#call" do
    context "with file path" do
      it "returns a TranscriptionResult" do
        allow(RubyLLM).to receive(:transcribe).and_return(mock_response)

        result = test_transcriber.call(audio: "recording.mp3")

        expect(result).to be_a(RubyLLM::Agents::TranscriptionResult)
      end

      it "passes audio to RubyLLM.transcribe" do
        expect(RubyLLM).to receive(:transcribe)
          .with(anything, hash_including(model: "whisper-1"))
          .and_return(mock_response)

        test_transcriber.call(audio: "recording.mp3")
      end

      it "returns correct text" do
        allow(RubyLLM).to receive(:transcribe).and_return(mock_response)

        result = test_transcriber.call(audio: "recording.mp3")
        expect(result.text).to eq("Hello world")
      end

      it "returns segments" do
        allow(RubyLLM).to receive(:transcribe).and_return(mock_response)

        result = test_transcriber.call(audio: "recording.mp3")
        expect(result.segments).to eq([
          { start: 0.0, end: 1.0, text: "Hello" },
          { start: 1.0, end: 2.0, text: "world" }
        ])
      end
    end

    context "with language override" do
      it "passes language to RubyLLM.transcribe" do
        transcriber_with_lang = Class.new(RubyLLM::Agents::Transcriber) do
          model "whisper-1"
          language "es"
        end

        expect(RubyLLM).to receive(:transcribe)
          .with(anything, hash_including(language: "es"))
          .and_return(mock_response)

        transcriber_with_lang.call(audio: "recording.mp3")
      end

      it "allows runtime language override" do
        expect(RubyLLM).to receive(:transcribe)
          .with(anything, hash_including(language: "fr"))
          .and_return(mock_response)

        test_transcriber.call(audio: "recording.mp3", language: "fr")
      end
    end

    context "with model override" do
      it "allows runtime model override" do
        expect(RubyLLM).to receive(:transcribe)
          .with(anything, hash_including(model: "gpt-4o-transcribe"))
          .and_return(mock_response)

        test_transcriber.call(audio: "recording.mp3", model: "gpt-4o-transcribe")
      end
    end

    context "with postprocessing" do
      let(:postprocessing_transcriber) do
        Class.new(RubyLLM::Agents::Transcriber) do
          model "whisper-1"

          def postprocess_text(text)
            text.upcase
          end
        end
      end

      it "applies postprocessing after transcription" do
        allow(RubyLLM).to receive(:transcribe).and_return(mock_response)

        result = postprocessing_transcriber.call(audio: "recording.mp3")
        expect(result.text).to eq("HELLO WORLD")
      end
    end

    context "with prompt" do
      let(:prompted_transcriber) do
        Class.new(RubyLLM::Agents::Transcriber) do
          model "whisper-1"

          def prompt
            "Technical discussion about Ruby programming"
          end
        end
      end

      it "passes prompt to RubyLLM.transcribe" do
        expect(RubyLLM).to receive(:transcribe)
          .with(anything, hash_including(prompt: "Technical discussion about Ruby programming"))
          .and_return(mock_response)

        prompted_transcriber.call(audio: "recording.mp3")
      end
    end

    context "timing" do
      it "tracks duration" do
        allow(RubyLLM).to receive(:transcribe).and_return(mock_response)

        result = test_transcriber.call(audio: "recording.mp3")

        expect(result.duration_ms).to be >= 0
        expect(result.started_at).to be_present
        expect(result.completed_at).to be_present
      end
    end

    context "validation" do
      it "raises error when audio is nil" do
        expect {
          test_transcriber.call(audio: nil)
        }.to raise_error(ArgumentError, /audio is required/)
      end

      it "raises error when audio is empty string" do
        expect {
          test_transcriber.call(audio: "")
        }.to raise_error(ArgumentError, /audio is required/)
      end
    end
  end

  describe "cost calculation" do
    it "calculates cost based on audio duration" do
      response_with_duration = double(
        text: "Hello",
        segments: [],
        words: nil,
        language: "en",
        duration: 60.0,
        model: "whisper-1"
      )
      allow(RubyLLM).to receive(:transcribe).and_return(response_with_duration)

      result = test_transcriber.call(audio: "recording.mp3")

      # Whisper pricing: $0.006 per minute
      # 60 seconds = 1 minute = $0.006
      expect(result.total_cost).to be > 0
    end
  end
end
