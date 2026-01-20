# frozen_string_literal: true

require "rails_helper"
require "generators/ruby_llm_agents/speaker_generator"

RSpec.describe RubyLlmAgents::SpeakerGenerator, type: :generator do
  describe "basic speaker generation" do
    before { run_generator ["Narrator"] }

    it "creates the speaker file with correct name" do
      expect(file_exists?("app/llm/audio/speakers/narrator_speaker.rb")).to be true
    end

    it "creates a class that inherits from ApplicationSpeaker" do
      content = file_content("app/llm/audio/speakers/narrator_speaker.rb")
      expect(content).to include("class NarratorSpeaker < ApplicationSpeaker")
    end

    it "wraps the class in LLM::Audio namespace" do
      content = file_content("app/llm/audio/speakers/narrator_speaker.rb")
      expect(content).to include("module LLM")
      expect(content).to include("module Audio")
    end

    it "includes default provider configuration" do
      content = file_content("app/llm/audio/speakers/narrator_speaker.rb")
      expect(content).to include("provider :openai")
    end

    it "includes default voice configuration" do
      content = file_content("app/llm/audio/speakers/narrator_speaker.rb")
      expect(content).to include('voice "nova"')
    end
  end

  describe "--provider option" do
    before { run_generator ["Narrator", "--provider=elevenlabs"] }

    it "uses the specified provider" do
      content = file_content("app/llm/audio/speakers/narrator_speaker.rb")
      expect(content).to include("provider :elevenlabs")
    end

    it "includes ElevenLabs voice settings comment" do
      content = file_content("app/llm/audio/speakers/narrator_speaker.rb")
      expect(content).to include("# ElevenLabs voice settings")
    end
  end

  describe "--model option" do
    before { run_generator ["Narrator", "--model=tts-1-hd"] }

    it "uses the specified model" do
      content = file_content("app/llm/audio/speakers/narrator_speaker.rb")
      expect(content).to include('model "tts-1-hd"')
    end
  end

  describe "--voice option" do
    before { run_generator ["Narrator", "--voice=alloy"] }

    it "uses the specified voice" do
      content = file_content("app/llm/audio/speakers/narrator_speaker.rb")
      expect(content).to include('voice "alloy"')
    end
  end

  describe "--speed option" do
    before { run_generator ["Narrator", "--speed=1.25"] }

    it "includes speed configuration" do
      content = file_content("app/llm/audio/speakers/narrator_speaker.rb")
      expect(content).to include("speed 1.25")
    end
  end

  describe "without --speed option (default 1.0)" do
    before { run_generator ["Narrator"] }

    it "does not include speed (uses default)" do
      content = file_content("app/llm/audio/speakers/narrator_speaker.rb")
      expect(content).not_to include("speed")
    end
  end

  describe "--format option" do
    before { run_generator ["Narrator", "--format=wav"] }

    it "includes output_format configuration" do
      content = file_content("app/llm/audio/speakers/narrator_speaker.rb")
      expect(content).to include("output_format :wav")
    end
  end

  describe "without --format option (default mp3)" do
    before { run_generator ["Narrator"] }

    it "does not include output_format (uses default)" do
      content = file_content("app/llm/audio/speakers/narrator_speaker.rb")
      expect(content).not_to include("output_format")
    end
  end

  describe "--cache option" do
    before { run_generator ["Narrator", "--cache=7.days"] }

    it "includes cache configuration" do
      content = file_content("app/llm/audio/speakers/narrator_speaker.rb")
      expect(content).to include("cache_for 7.days")
    end
  end

  describe "without --cache option" do
    before { run_generator ["Narrator"] }

    it "does not include caching by default" do
      content = file_content("app/llm/audio/speakers/narrator_speaker.rb")
      expect(content).not_to include("cache_for")
    end
  end

  describe "combined options" do
    before do
      run_generator [
        "Article",
        "--provider=openai",
        "--model=tts-1-hd",
        "--voice=echo",
        "--speed=1.1",
        "--format=ogg",
        "--cache=1.week"
      ]
    end

    it "creates the speaker file" do
      expect(file_exists?("app/llm/audio/speakers/article_speaker.rb")).to be true
    end

    it "applies all options correctly" do
      content = file_content("app/llm/audio/speakers/article_speaker.rb")
      expect(content).to include("class ArticleSpeaker < ApplicationSpeaker")
      expect(content).to include("provider :openai")
      expect(content).to include('model "tts-1-hd"')
      expect(content).to include('voice "echo"')
      expect(content).to include("speed 1.1")
      expect(content).to include("output_format :ogg")
      expect(content).to include("cache_for 1.week")
    end
  end

  describe "camelCase name handling" do
    before { run_generator ["ArticleReader"] }

    it "creates file with underscored name" do
      expect(file_exists?("app/llm/audio/speakers/article_reader_speaker.rb")).to be true
    end

    it "uses the correct class name" do
      content = file_content("app/llm/audio/speakers/article_reader_speaker.rb")
      expect(content).to include("class ArticleReaderSpeaker < ApplicationSpeaker")
    end
  end

  describe "snake_case name handling" do
    before { run_generator ["audio_book"] }

    it "creates file with correct name" do
      expect(file_exists?("app/llm/audio/speakers/audio_book_speaker.rb")).to be true
    end

    it "uses the correct class name" do
      content = file_content("app/llm/audio/speakers/audio_book_speaker.rb")
      expect(content).to include("class AudioBookSpeaker < ApplicationSpeaker")
    end
  end

  describe "nested namespace" do
    before { run_generator ["content/narrator"] }

    it "creates file in nested directory" do
      expect(file_exists?("app/llm/audio/speakers/content/narrator_speaker.rb")).to be true
    end

    it "uses namespaced class name" do
      content = file_content("app/llm/audio/speakers/content/narrator_speaker.rb")
      expect(content).to include("module Content")
      expect(content).to include("class NarratorSpeaker < ApplicationSpeaker")
    end
  end

  describe "lexicon comment" do
    before { run_generator ["Narrator"] }

    it "includes commented lexicon block" do
      content = file_content("app/llm/audio/speakers/narrator_speaker.rb")
      expect(content).to include("# lexicon do")
    end
  end

  describe "--root option" do
    before { run_generator ["Narrator", "--root=ai"] }

    it "creates the speaker in the ai directory" do
      expect(file_exists?("app/ai/audio/speakers/narrator_speaker.rb")).to be true
    end

    it "uses the AI::Audio namespace" do
      content = file_content("app/ai/audio/speakers/narrator_speaker.rb")
      expect(content).to include("module AI")
      expect(content).to include("module Audio")
    end
  end
end
