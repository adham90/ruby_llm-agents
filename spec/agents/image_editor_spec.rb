# frozen_string_literal: true

require "rails_helper"

RSpec.describe RubyLLM::Agents::ImageEditor do
  describe "DSL" do
    let(:test_editor_class) do
      Class.new(described_class) do
        model "gpt-image-1"
        size "1024x1024"
        description "Test editor"
      end
    end

    it "sets model" do
      expect(test_editor_class.model).to eq("gpt-image-1")
    end

    it "sets size" do
      expect(test_editor_class.size).to eq("1024x1024")
    end

    it "sets description" do
      expect(test_editor_class.description).to eq("Test editor")
    end
  end

  describe "inheritance" do
    let(:parent_class) do
      Class.new(described_class) do
        model "parent-model"
        size "512x512"
      end
    end

    let(:child_class) do
      Class.new(parent_class)
    end

    it "inherits settings from parent" do
      expect(child_class.model).to eq("parent-model")
      expect(child_class.size).to eq("512x512")
    end
  end

  describe ".call" do
    let(:editor_class) do
      Class.new(described_class) do
        model "gpt-image-1"
      end
    end

    it "creates instance and calls execute" do
      instance = instance_double(editor_class)
      allow(editor_class).to receive(:new).and_return(instance)
      allow(instance).to receive(:call).and_return(double("result"))

      editor_class.call(image: "test.png", mask: "mask.png", prompt: "Edit this")

      expect(editor_class).to have_received(:new).with(
        image: "test.png",
        mask: "mask.png",
        prompt: "Edit this"
      )
      expect(instance).to have_received(:call)
    end
  end

  describe "#initialize" do
    it "sets image, mask, prompt and options" do
      editor = described_class.new(
        image: "photo.png",
        mask: "mask.png",
        prompt: "Replace background",
        count: 2
      )

      expect(editor.image).to eq("photo.png")
      expect(editor.mask).to eq("mask.png")
      expect(editor.prompt).to eq("Replace background")
      expect(editor.options).to eq({ count: 2 })
    end
  end

  describe "caching" do
    let(:cached_editor) do
      Class.new(described_class) do
        model "gpt-image-1"
        cache_for 2.hours
      end
    end

    it "enables caching with TTL" do
      expect(cached_editor.cache_enabled?).to be true
      expect(cached_editor.cache_ttl).to eq(2.hours)
    end
  end
end
