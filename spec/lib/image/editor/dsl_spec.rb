# frozen_string_literal: true

require "rails_helper"

RSpec.describe RubyLLM::Agents::ImageEditor::DSL do
  let(:editor_class) do
    Class.new(RubyLLM::Agents::ImageEditor) do
      def self.name
        "TestEditor"
      end
    end
  end

  before do
    RubyLLM::Agents.reset_configuration!
    RubyLLM::Agents.configure do |c|
      c.default_editor_model = "gpt-image-1"
      c.default_image_size = "1024x1024"
    end
  end

  describe "#size" do
    it "sets and gets the size" do
      editor_class.size "512x512"
      expect(editor_class.size).to eq("512x512")
    end

    it "defaults to config default_image_size" do
      expect(editor_class.size).to eq("1024x1024")
    end
  end

  describe "#content_policy" do
    it "sets and gets the content policy" do
      editor_class.content_policy :strict
      expect(editor_class.content_policy).to eq(:strict)
    end

    it "defaults to :standard" do
      expect(editor_class.content_policy).to eq(:standard)
    end

    it "accepts all valid policy levels" do
      [:none, :standard, :moderate, :strict].each do |level|
        editor_class.content_policy level
        expect(editor_class.content_policy).to eq(level)
      end
    end
  end

  describe "default_model" do
    it "uses default_editor_model from config" do
      expect(editor_class.model).to eq("gpt-image-1")
    end

    it "falls back to default_image_model when not configured" do
      RubyLLM::Agents.reset_configuration!
      RubyLLM::Agents.configure do |c|
        c.default_image_model = "fallback-model"
      end
      expect(editor_class.model).to eq("fallback-model")
    end
  end

  describe "combined with inherited methods" do
    it "can configure all options" do
      editor_class.model "custom-editor"
      editor_class.version "v2"
      editor_class.size "2048x2048"
      editor_class.content_policy :moderate
      editor_class.cache_for 7200

      expect(editor_class.model).to eq("custom-editor")
      expect(editor_class.version).to eq("v2")
      expect(editor_class.size).to eq("2048x2048")
      expect(editor_class.content_policy).to eq(:moderate)
      expect(editor_class.cache_ttl).to eq(7200)
    end
  end
end
