# frozen_string_literal: true

require "rails_helper"

RSpec.describe RubyLLM::Agents::ImageAnalyzer::DSL do
  let(:analyzer_class) do
    Class.new(RubyLLM::Agents::ImageAnalyzer) do
      def self.name
        "TestAnalyzer"
      end
    end
  end

  before do
    RubyLLM::Agents.reset_configuration!
    RubyLLM::Agents.configure do |c|
      c.default_analyzer_model = "gpt-4o"
    end
  end

  describe "#analysis_type" do
    it "sets and gets the analysis type" do
      analyzer_class.analysis_type :caption
      expect(analyzer_class.analysis_type).to eq(:caption)
    end

    it "defaults to :detailed" do
      expect(analyzer_class.analysis_type).to eq(:detailed)
    end

    it "validates analysis type" do
      expect {
        analyzer_class.analysis_type :invalid
      }.to raise_error(ArgumentError, /Analysis type must be one of/)
    end

    it "accepts all valid types" do
      [:caption, :detailed, :tags, :objects, :colors, :all].each do |type|
        analyzer_class.analysis_type type
        expect(analyzer_class.analysis_type).to eq(type)
      end
    end
  end

  describe "#extract_colors" do
    it "sets and gets extract_colors" do
      analyzer_class.extract_colors true
      expect(analyzer_class.extract_colors).to be true
    end

    it "defaults to false" do
      expect(analyzer_class.extract_colors).to be false
    end

    it "allows setting to false" do
      analyzer_class.extract_colors true
      analyzer_class.extract_colors false
      expect(analyzer_class.extract_colors).to be false
    end
  end

  describe "#detect_objects" do
    it "sets and gets detect_objects" do
      analyzer_class.detect_objects true
      expect(analyzer_class.detect_objects).to be true
    end

    it "defaults to false" do
      expect(analyzer_class.detect_objects).to be false
    end
  end

  describe "#extract_text" do
    it "sets and gets extract_text" do
      analyzer_class.extract_text true
      expect(analyzer_class.extract_text).to be true
    end

    it "defaults to false" do
      expect(analyzer_class.extract_text).to be false
    end
  end

  describe "#custom_prompt" do
    it "sets and gets custom_prompt" do
      analyzer_class.custom_prompt "Describe the image in detail"
      expect(analyzer_class.custom_prompt).to eq("Describe the image in detail")
    end

    it "returns nil by default" do
      expect(analyzer_class.custom_prompt).to be_nil
    end
  end

  describe "#max_tags" do
    it "sets and gets max_tags" do
      analyzer_class.max_tags 25
      expect(analyzer_class.max_tags).to eq(25)
    end

    it "defaults to 10" do
      expect(analyzer_class.max_tags).to eq(10)
    end

    it "validates max_tags is positive integer" do
      expect {
        analyzer_class.max_tags 0
      }.to raise_error(ArgumentError, /must be a positive integer/)

      expect {
        analyzer_class.max_tags(-5)
      }.to raise_error(ArgumentError, /must be a positive integer/)

      expect {
        analyzer_class.max_tags 5.5
      }.to raise_error(ArgumentError, /must be a positive integer/)
    end
  end

  describe "default_model" do
    it "uses default_analyzer_model from config" do
      expect(analyzer_class.model).to eq("gpt-4o")
    end

    it "falls back to gpt-4o when not configured" do
      RubyLLM::Agents.reset_configuration!
      expect(analyzer_class.model).to eq("gpt-4o")
    end
  end

  describe "combined configuration" do
    it "allows full configuration" do
      analyzer_class.analysis_type :all
      analyzer_class.extract_colors true
      analyzer_class.detect_objects true
      analyzer_class.extract_text true
      analyzer_class.max_tags 50
      analyzer_class.custom_prompt "Analyze everything"

      expect(analyzer_class.analysis_type).to eq(:all)
      expect(analyzer_class.extract_colors).to be true
      expect(analyzer_class.detect_objects).to be true
      expect(analyzer_class.extract_text).to be true
      expect(analyzer_class.max_tags).to eq(50)
      expect(analyzer_class.custom_prompt).to eq("Analyze everything")
    end
  end
end
