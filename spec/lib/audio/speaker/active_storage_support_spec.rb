# frozen_string_literal: true

require "rails_helper"

RSpec.describe RubyLLM::Agents::Speaker::ActiveStorageSupport do
  # Create a test speaker class that includes the concern
  let(:speaker_class) do
    Class.new(RubyLLM::Agents::Speaker) do
      include RubyLLM::Agents::Speaker::ActiveStorageSupport

      provider :openai
      model "tts-1-hd"
      voice "nova"
    end
  end

  # Mock record with ActiveStorage attachment
  let(:mock_blob) do
    double("ActiveStorage::Blob",
      key: "abc123",
      url: "https://storage.example.com/abc123.mp3")
  end
  let(:mock_attachment) do
    double("ActiveStorage::Attached::One", blob: mock_blob)
  end
  let(:mock_record) do
    double("Record", narration: mock_attachment)
  end

  # Mock successful speech result
  let(:successful_result) do
    RubyLLM::Agents::SpeechResult.new(
      audio: "binary audio data",
      format: :mp3,
      file_size: 17,
      characters: 11,
      text_length: 11,
      provider: :openai,
      model_id: "tts-1-hd",
      voice_id: "nova",
      voice_name: "nova",
      duration_ms: 500,
      total_cost: 0.001,
      status: :success
    )
  end

  let(:wav_result) do
    RubyLLM::Agents::SpeechResult.new(
      audio: "wav audio data",
      format: :wav,
      file_size: 14,
      characters: 11,
      provider: :openai,
      status: :success
    )
  end

  let(:ogg_result) do
    RubyLLM::Agents::SpeechResult.new(
      audio: "ogg audio data",
      format: :ogg,
      file_size: 14,
      characters: 11,
      provider: :openai,
      status: :success
    )
  end

  let(:failed_result) do
    RubyLLM::Agents::SpeechResult.new(
      error_class: "StandardError",
      error_message: "Voice not found",
      status: :failed
    )
  end

  describe ".speak_and_attach" do
    before do
      allow(speaker_class).to receive(:call).and_return(successful_result)
    end

    context "with successful result" do
      it "calls the speaker with text" do
        allow(mock_attachment).to receive(:attach)

        expect(speaker_class).to receive(:call).with(text: "Hello world")

        speaker_class.speak_and_attach(
          text: "Hello world",
          record: mock_record,
          attachment_name: :narration
        )
      end

      it "returns the result" do
        allow(mock_attachment).to receive(:attach)

        result = speaker_class.speak_and_attach(
          text: "Hello world",
          record: mock_record,
          attachment_name: :narration
        )

        expect(result).to eq(successful_result)
      end

      it "attaches audio with correct content type" do
        expect(mock_attachment).to receive(:attach).with(
          io: instance_of(StringIO),
          filename: match(/^speech_\d+\.mp3$/),
          content_type: "audio/mpeg"
        )

        speaker_class.speak_and_attach(
          text: "Hello world",
          record: mock_record,
          attachment_name: :narration
        )
      end

      it "sets audio_key on result from blob" do
        allow(mock_attachment).to receive(:attach)

        result = speaker_class.speak_and_attach(
          text: "Hello world",
          record: mock_record,
          attachment_name: :narration
        )

        expect(result.audio_key).to eq("abc123")
      end

      it "sets audio_url on result from blob" do
        allow(mock_attachment).to receive(:attach)

        result = speaker_class.speak_and_attach(
          text: "Hello world",
          record: mock_record,
          attachment_name: :narration
        )

        expect(result.audio_url).to eq("https://storage.example.com/abc123.mp3")
      end

      it "passes the audio binary data to StringIO" do
        allow(mock_attachment).to receive(:attach) do |args|
          expect(args[:io].read).to eq("binary audio data")
        end

        speaker_class.speak_and_attach(
          text: "Hello world",
          record: mock_record,
          attachment_name: :narration
        )
      end
    end

    context "with custom filename" do
      it "uses provided filename" do
        allow(mock_attachment).to receive(:attach)

        expect(mock_attachment).to receive(:attach).with(
          io: instance_of(StringIO),
          filename: "custom_narration.mp3",
          content_type: "audio/mpeg"
        )

        speaker_class.speak_and_attach(
          text: "Hello world",
          record: mock_record,
          attachment_name: :narration,
          filename: "custom_narration.mp3"
        )
      end
    end

    context "with different output formats" do
      it "generates .wav filename for wav format" do
        allow(speaker_class).to receive(:call).and_return(wav_result)
        allow(mock_attachment).to receive(:attach)

        expect(mock_attachment).to receive(:attach).with(
          io: instance_of(StringIO),
          filename: match(/^speech_\d+\.wav$/),
          content_type: "audio/wav"
        )

        speaker_class.speak_and_attach(
          text: "Hello world",
          record: mock_record,
          attachment_name: :narration
        )
      end

      it "generates .ogg filename for ogg format" do
        allow(speaker_class).to receive(:call).and_return(ogg_result)
        allow(mock_attachment).to receive(:attach)

        expect(mock_attachment).to receive(:attach).with(
          io: instance_of(StringIO),
          filename: match(/^speech_\d+\.ogg$/),
          content_type: "audio/ogg"
        )

        speaker_class.speak_and_attach(
          text: "Hello world",
          record: mock_record,
          attachment_name: :narration
        )
      end
    end

    context "with failed result" do
      before do
        allow(speaker_class).to receive(:call).and_return(failed_result)
      end

      it "returns result unchanged without attaching" do
        expect(mock_attachment).not_to receive(:attach)

        result = speaker_class.speak_and_attach(
          text: "Hello world",
          record: mock_record,
          attachment_name: :narration
        )

        expect(result).to eq(failed_result)
      end
    end

    context "when blob does not respond to url" do
      let(:legacy_blob) do
        obj = Object.new
        obj.define_singleton_method(:key) { "abc123" }
        obj.define_singleton_method(:service_url) { "https://storage.example.com/abc123.mp3" }
        obj
      end
      let(:legacy_attachment) do
        double("ActiveStorage::Attached::One", blob: legacy_blob)
      end
      let(:legacy_record) do
        double("Record", narration: legacy_attachment)
      end

      it "falls back to service_url" do
        allow(legacy_attachment).to receive(:attach)

        result = speaker_class.speak_and_attach(
          text: "Hello world",
          record: legacy_record,
          attachment_name: :narration
        )

        expect(result.audio_url).to eq("https://storage.example.com/abc123.mp3")
      end
    end
  end

  describe "filename generation" do
    it "generates filename with timestamp and format extension" do
      allow(Time).to receive(:current).and_return(Time.at(1234567890))
      allow(speaker_class).to receive(:call).and_return(successful_result)
      allow(mock_attachment).to receive(:attach)

      speaker_class.speak_and_attach(
        text: "test",
        record: mock_record,
        attachment_name: :narration
      )

      expect(mock_attachment).to have_received(:attach).with(
        io: anything,
        filename: "speech_1234567890.mp3",
        content_type: anything
      )
    end
  end
end
