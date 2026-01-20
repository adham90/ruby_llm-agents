# frozen_string_literal: true

require "rails_helper"

RSpec.describe RubyLLM::Agents::ImageVariator do
  describe "DSL" do
    let(:test_variator_class) do
      Class.new(described_class) do
        model "gpt-image-1"
        size "1024x1024"
        variation_strength 0.3
        description "Test variator"
        version "v2"
      end
    end

    it "sets model" do
      expect(test_variator_class.model).to eq("gpt-image-1")
    end

    it "sets size" do
      expect(test_variator_class.size).to eq("1024x1024")
    end

    it "sets variation_strength" do
      expect(test_variator_class.variation_strength).to eq(0.3)
    end

    it "sets description" do
      expect(test_variator_class.description).to eq("Test variator")
    end

    it "sets version" do
      expect(test_variator_class.version).to eq("v2")
    end

    it "validates variation_strength range" do
      expect {
        Class.new(described_class) do
          variation_strength 1.5
        end
      }.to raise_error(ArgumentError, /between 0.0 and 1.0/)
    end

    it "validates variation_strength is not negative" do
      expect {
        Class.new(described_class) do
          variation_strength(-0.5)
        end
      }.to raise_error(ArgumentError, /between 0.0 and 1.0/)
    end
  end

  describe "inheritance" do
    let(:parent_class) do
      Class.new(described_class) do
        model "parent-model"
        size "512x512"
        variation_strength 0.4
      end
    end

    let(:child_class) do
      Class.new(parent_class)
    end

    it "inherits settings from parent" do
      expect(child_class.model).to eq("parent-model")
      expect(child_class.size).to eq("512x512")
      expect(child_class.variation_strength).to eq(0.4)
    end
  end

  describe ".call" do
    let(:variator_class) do
      Class.new(described_class) do
        model "gpt-image-1"
        size "1024x1024"
      end
    end

    it "creates instance and calls execute" do
      instance = instance_double(variator_class)
      allow(variator_class).to receive(:new).and_return(instance)
      allow(instance).to receive(:call).and_return(double("result"))

      variator_class.call(image: "test.png")

      expect(variator_class).to have_received(:new).with(image: "test.png")
      expect(instance).to have_received(:call)
    end
  end

  describe "#initialize" do
    it "sets image and options" do
      variator = described_class.new(image: "logo.png", count: 4)

      expect(variator.image).to eq("logo.png")
      expect(variator.options).to eq({ count: 4 })
    end
  end

  describe "caching" do
    let(:cached_variator) do
      Class.new(described_class) do
        model "gpt-image-1"
        cache_for 1.hour
      end
    end

    it "enables caching with TTL" do
      expect(cached_variator.cache_enabled?).to be true
      expect(cached_variator.cache_ttl).to eq(1.hour)
    end

    let(:uncached_variator) do
      Class.new(described_class) do
        model "gpt-image-1"
      end
    end

    it "disables caching by default" do
      expect(uncached_variator.cache_enabled?).to be false
    end
  end
end
