# frozen_string_literal: true

require "rails_helper"

RSpec.describe RubyLLM::Agents::Speaker::Execution do
  # Mock RubyLLM.speak response
  let(:mock_response) do
    double(
      "SpeechResponse",
      audio: "binary audio data",
      model: "tts-1"
    )
  end

  let(:test_speaker) do
    Class.new(RubyLLM::Agents::Speaker) do
      provider :openai
      model "tts-1"
      voice "nova"
    end
  end

  before do
    # Disable tracking for most tests
    allow(RubyLLM::Agents.configuration).to receive(:track_speech).and_return(false)
  end

  describe "#call" do
    context "with text" do
      it "returns a SpeechResult" do
        allow(RubyLLM).to receive(:speak).and_return(mock_response)

        result = test_speaker.call(text: "Hello world")

        expect(result).to be_a(RubyLLM::Agents::SpeechResult)
      end

      it "passes text to RubyLLM.speak" do
        expect(RubyLLM).to receive(:speak)
          .with("Hello world", hash_including(model: "tts-1", voice: "nova"))
          .and_return(mock_response)

        test_speaker.call(text: "Hello world")
      end

      it "returns audio data" do
        allow(RubyLLM).to receive(:speak).and_return(mock_response)

        result = test_speaker.call(text: "Hello world")
        expect(result.audio).to eq("binary audio data")
      end

      it "tracks character count" do
        allow(RubyLLM).to receive(:speak).and_return(mock_response)

        result = test_speaker.call(text: "Hello world")
        expect(result.characters).to eq(11)
      end
    end

    context "with voice override" do
      it "passes voice to RubyLLM.speak" do
        expect(RubyLLM).to receive(:speak)
          .with(anything, hash_including(voice: "alloy"))
          .and_return(mock_response)

        test_speaker.call(text: "Hello", voice: "alloy")
      end
    end

    context "with speed override" do
      let(:speed_speaker) do
        Class.new(RubyLLM::Agents::Speaker) do
          provider :openai
          model "tts-1"
          voice "nova"
          speed 1.25
        end
      end

      it "passes speed to RubyLLM.speak" do
        expect(RubyLLM).to receive(:speak)
          .with(anything, hash_including(speed: 1.25))
          .and_return(mock_response)

        speed_speaker.call(text: "Hello")
      end

      it "allows runtime speed override" do
        expect(RubyLLM).to receive(:speak)
          .with(anything, hash_including(speed: 0.75))
          .and_return(mock_response)

        speed_speaker.call(text: "Hello", speed: 0.75)
      end
    end

    context "with model override" do
      it "allows runtime model override" do
        expect(RubyLLM).to receive(:speak)
          .with(anything, hash_including(model: "tts-1-hd"))
          .and_return(mock_response)

        test_speaker.call(text: "Hello", model: "tts-1-hd")
      end
    end

    context "with lexicon" do
      let(:lexicon_speaker) do
        Class.new(RubyLLM::Agents::Speaker) do
          provider :openai
          model "tts-1"
          voice "nova"

          lexicon do
            pronounce "API", "A P I"
            pronounce "SQL", "sequel"
          end
        end
      end

      it "applies lexicon replacements" do
        expect(RubyLLM).to receive(:speak)
          .with("The A P I uses sequel database", anything)
          .and_return(mock_response)

        lexicon_speaker.call(text: "The API uses SQL database")
      end
    end

    context "timing" do
      it "tracks duration" do
        allow(RubyLLM).to receive(:speak).and_return(mock_response)

        result = test_speaker.call(text: "Hello world")

        expect(result.duration_ms).to be >= 0
        expect(result.started_at).to be_present
        expect(result.completed_at).to be_present
      end
    end

    context "validation" do
      it "raises error when text is nil" do
        expect {
          test_speaker.call(text: nil)
        }.to raise_error(ArgumentError, /text is required/)
      end

      it "raises error when text is empty string" do
        expect {
          test_speaker.call(text: "")
        }.to raise_error(ArgumentError, /text is required/)
      end
    end
  end

  describe ".stream" do
    let(:streaming_speaker) do
      Class.new(RubyLLM::Agents::Speaker) do
        provider :openai
        model "tts-1"
        voice "nova"
        streaming true
      end
    end

    it "raises error without block" do
      expect {
        streaming_speaker.stream(text: "Hello world")
      }.to raise_error(ArgumentError, /block is required/)
    end

    it "enables streaming mode" do
      chunks = []
      chunk_response = double(audio: "chunk1", model: "tts-1")

      expect(RubyLLM).to receive(:speak) do |text, options, &block|
        expect(options[:streaming]).to be true
        chunk_response
      end

      streaming_speaker.stream(text: "Hello world") do |chunk|
        chunks << chunk
      end
    end
  end

  describe "cost calculation" do
    it "calculates cost based on character count" do
      allow(RubyLLM).to receive(:speak).and_return(mock_response)

      result = test_speaker.call(text: "Hello world! This is a test message.")

      # OpenAI TTS pricing: $15/million characters for tts-1
      expect(result.total_cost).to be > 0
    end
  end

  describe "provider-specific options" do
    context "ElevenLabs voice settings" do
      let(:elevenlabs_speaker) do
        Class.new(RubyLLM::Agents::Speaker) do
          provider :elevenlabs
          model "eleven_monolingual_v1"
          voice_id "21m00Tcm4TlvDq8ikWAM"

          voice_settings do
            stability 0.5
            similarity_boost 0.75
          end
        end
      end

      it "passes voice settings to API" do
        allow(RubyLLM).to receive(:speak) do |text, options|
          expect(options[:voice_settings]).to include(
            stability: 0.5,
            similarity_boost: 0.75
          )
          mock_response
        end

        elevenlabs_speaker.call(text: "Hello")
      end
    end
  end
end
