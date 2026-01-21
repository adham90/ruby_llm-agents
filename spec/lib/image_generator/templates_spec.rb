# frozen_string_literal: true

require "spec_helper"

RSpec.describe RubyLLM::Agents::ImageGenerator::Templates do
  describe ".apply" do
    it "substitutes a single variable" do
      template = "Hello {name}!"
      result = described_class.apply(template, name: "World")
      expect(result).to eq("Hello World!")
    end

    it "substitutes multiple variables" do
      template = "{greeting}, {name}! Welcome to {place}."
      result = described_class.apply(template, greeting: "Hello", name: "Alice", place: "Wonderland")
      expect(result).to eq("Hello, Alice! Welcome to Wonderland.")
    end

    it "leaves unmatched placeholders unchanged" do
      template = "Hello {name}, your ID is {id}"
      result = described_class.apply(template, name: "Bob")
      expect(result).to eq("Hello Bob, your ID is {id}")
    end

    it "handles empty template" do
      result = described_class.apply("", prompt: "test")
      expect(result).to eq("")
    end

    it "converts non-string values to strings" do
      template = "Count: {count}"
      result = described_class.apply(template, count: 42)
      expect(result).to eq("Count: 42")
    end

    it "does not modify the original template" do
      template = "Hello {name}!"
      original = template.dup
      described_class.apply(template, name: "World")
      expect(template).to eq(original)
    end
  end

  describe ".preset" do
    it "returns template for valid preset name as symbol" do
      template = described_class.preset(:product)
      expect(template).to include("{prompt}")
      expect(template).to include("product photography")
    end

    it "returns template for valid preset name as string" do
      template = described_class.preset("product")
      expect(template).to include("{prompt}")
    end

    it "returns nil for unknown preset" do
      expect(described_class.preset(:nonexistent)).to be_nil
    end
  end

  describe ".preset_names" do
    it "returns all preset keys as symbols" do
      names = described_class.preset_names
      expect(names).to be_an(Array)
      expect(names).to all(be_a(Symbol))
    end

    it "includes all 13 presets" do
      expected_presets = %i[
        product portrait landscape watercolor oil_painting
        digital_art anime isometric blueprint wireframe
        icon logo ui_mockup
      ]
      expect(described_class.preset_names).to match_array(expected_presets)
    end
  end

  describe ".apply_preset" do
    it "applies preset template to prompt" do
      result = described_class.apply_preset(:product, "a red sneaker")
      expect(result).to include("a red sneaker")
      expect(result).to include("product photography")
    end

    it "raises ArgumentError for unknown preset" do
      expect {
        described_class.apply_preset(:unknown_preset, "test")
      }.to raise_error(ArgumentError, /Unknown template preset: unknown_preset/)
    end

    it "handles string preset name" do
      result = described_class.apply_preset("portrait", "a person")
      expect(result).to include("a person")
      expect(result).to include("portrait")
    end
  end

  describe "PRESETS constant" do
    subject(:presets) { described_class::PRESETS }

    it "is frozen" do
      expect(presets).to be_frozen
    end

    it "contains product preset" do
      expect(presets[:product]).to include("product photography")
      expect(presets[:product]).to include("{prompt}")
    end

    it "contains portrait preset" do
      expect(presets[:portrait]).to include("portrait")
      expect(presets[:portrait]).to include("{prompt}")
    end

    it "contains landscape preset" do
      expect(presets[:landscape]).to include("landscape")
      expect(presets[:landscape]).to include("{prompt}")
    end

    it "contains watercolor preset" do
      expect(presets[:watercolor]).to include("Watercolor")
      expect(presets[:watercolor]).to include("{prompt}")
    end

    it "contains oil_painting preset" do
      expect(presets[:oil_painting]).to include("Oil painting")
      expect(presets[:oil_painting]).to include("{prompt}")
    end

    it "contains digital_art preset" do
      expect(presets[:digital_art]).to include("Digital art")
      expect(presets[:digital_art]).to include("{prompt}")
    end

    it "contains anime preset" do
      expect(presets[:anime]).to include("Anime")
      expect(presets[:anime]).to include("{prompt}")
    end

    it "contains isometric preset" do
      expect(presets[:isometric]).to include("Isometric")
      expect(presets[:isometric]).to include("{prompt}")
    end

    it "contains blueprint preset" do
      expect(presets[:blueprint]).to include("blueprint")
      expect(presets[:blueprint]).to include("{prompt}")
    end

    it "contains wireframe preset" do
      expect(presets[:wireframe]).to include("wireframe")
      expect(presets[:wireframe]).to include("{prompt}")
    end

    it "contains icon preset" do
      expect(presets[:icon]).to include("icon")
      expect(presets[:icon]).to include("{prompt}")
    end

    it "contains logo preset" do
      expect(presets[:logo]).to include("logo")
      expect(presets[:logo]).to include("{prompt}")
    end

    it "contains ui_mockup preset" do
      expect(presets[:ui_mockup]).to include("UI mockup")
      expect(presets[:ui_mockup]).to include("{prompt}")
    end
  end
end
