# frozen_string_literal: true

require "rails_helper"
require "generators/ruby_llm_agents/transcriber_generator"

RSpec.describe RubyLlmAgents::TranscriberGenerator, type: :generator do
  describe "basic transcriber generation" do
    before { run_generator ["Meeting"] }

    it "creates the transcriber file with correct name" do
      expect(file_exists?("app/transcribers/meeting_transcriber.rb")).to be true
    end

    it "creates a class that inherits from ApplicationTranscriber" do
      content = file_content("app/transcribers/meeting_transcriber.rb")
      expect(content).to include("class MeetingTranscriber < ApplicationTranscriber")
    end

    it "includes default model configuration" do
      content = file_content("app/transcribers/meeting_transcriber.rb")
      expect(content).to include('model "whisper-1"')
    end
  end

  describe "--model option" do
    before { run_generator ["Meeting", "--model=gpt-4o-transcribe"] }

    it "uses the specified model" do
      content = file_content("app/transcribers/meeting_transcriber.rb")
      expect(content).to include('model "gpt-4o-transcribe"')
    end
  end

  describe "--language option" do
    before { run_generator ["Meeting", "--language=es"] }

    it "includes language configuration" do
      content = file_content("app/transcribers/meeting_transcriber.rb")
      expect(content).to include('language "es"')
    end
  end

  describe "without --language option" do
    before { run_generator ["Meeting"] }

    it "does not include language (auto-detect)" do
      content = file_content("app/transcribers/meeting_transcriber.rb")
      expect(content).not_to include("language")
    end
  end

  describe "--output_format option" do
    before { run_generator ["Meeting", "--output-format=json"] }

    it "includes output_format configuration" do
      content = file_content("app/transcribers/meeting_transcriber.rb")
      expect(content).to include("output_format :json")
    end
  end

  describe "without --output_format option (default text)" do
    before { run_generator ["Meeting"] }

    it "does not include output_format (uses default)" do
      content = file_content("app/transcribers/meeting_transcriber.rb")
      expect(content).not_to include("output_format")
    end
  end

  describe "--cache option" do
    before { run_generator ["Meeting", "--cache=30.days"] }

    it "includes cache configuration" do
      content = file_content("app/transcribers/meeting_transcriber.rb")
      expect(content).to include("cache_for 30.days")
    end
  end

  describe "without --cache option" do
    before { run_generator ["Meeting"] }

    it "does not include caching by default" do
      content = file_content("app/transcribers/meeting_transcriber.rb")
      expect(content).not_to include("cache_for")
    end
  end

  describe "combined options" do
    before do
      run_generator [
        "Interview",
        "--model=gpt-4o-transcribe",
        "--language=en",
        "--output-format=srt",
        "--cache=7.days"
      ]
    end

    it "creates the transcriber file" do
      expect(file_exists?("app/transcribers/interview_transcriber.rb")).to be true
    end

    it "applies all options correctly" do
      content = file_content("app/transcribers/interview_transcriber.rb")
      expect(content).to include("class InterviewTranscriber < ApplicationTranscriber")
      expect(content).to include('model "gpt-4o-transcribe"')
      expect(content).to include('language "en"')
      expect(content).to include("output_format :srt")
      expect(content).to include("cache_for 7.days")
    end
  end

  describe "camelCase name handling" do
    before { run_generator ["PodcastEpisode"] }

    it "creates file with underscored name" do
      expect(file_exists?("app/transcribers/podcast_episode_transcriber.rb")).to be true
    end

    it "uses the correct class name" do
      content = file_content("app/transcribers/podcast_episode_transcriber.rb")
      expect(content).to include("class PodcastEpisodeTranscriber < ApplicationTranscriber")
    end
  end

  describe "snake_case name handling" do
    before { run_generator ["voice_memo"] }

    it "creates file with correct name" do
      expect(file_exists?("app/transcribers/voice_memo_transcriber.rb")).to be true
    end

    it "uses the correct class name" do
      content = file_content("app/transcribers/voice_memo_transcriber.rb")
      expect(content).to include("class VoiceMemoTranscriber < ApplicationTranscriber")
    end
  end

  describe "nested namespace" do
    before { run_generator ["media/podcast"] }

    it "creates file in nested directory" do
      expect(file_exists?("app/transcribers/media/podcast_transcriber.rb")).to be true
    end

    it "uses namespaced class name" do
      content = file_content("app/transcribers/media/podcast_transcriber.rb")
      expect(content).to include("class Media::PodcastTranscriber < ApplicationTranscriber")
    end
  end

  describe "prompt comment" do
    before { run_generator ["Meeting"] }

    it "includes commented prompt method" do
      content = file_content("app/transcribers/meeting_transcriber.rb")
      expect(content).to include("# def prompt")
    end
  end

  describe "postprocess_text comment" do
    before { run_generator ["Meeting"] }

    it "includes commented postprocess_text method" do
      content = file_content("app/transcribers/meeting_transcriber.rb")
      expect(content).to include("# def postprocess_text(text)")
    end
  end

  describe "ApplicationTranscriber creation" do
    before { run_generator ["Meeting"] }

    it "creates ApplicationTranscriber if it doesn't exist" do
      expect(file_exists?("app/transcribers/application_transcriber.rb")).to be true
    end

    it "ApplicationTranscriber inherits from RubyLLM::Agents::Transcriber" do
      content = file_content("app/transcribers/application_transcriber.rb")
      expect(content).to include("class ApplicationTranscriber < RubyLLM::Agents::Transcriber")
    end
  end
end
