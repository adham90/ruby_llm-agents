# frozen_string_literal: true

require "rails_helper"

RSpec.describe RubyLLM::Agents::BackgroundRemover do
  describe "DSL" do
    let(:test_remover_class) do
      Class.new(described_class) do
        model "segment-anything"
        output_format :webp
        refine_edges true
        alpha_matting true
        foreground_threshold 0.6
        background_threshold 0.4
        erode_size 2
        return_mask true
        description "Test remover"
      end
    end

    it "sets model" do
      expect(test_remover_class.model).to eq("segment-anything")
    end

    it "sets output_format" do
      expect(test_remover_class.output_format).to eq(:webp)
    end

    it "sets refine_edges" do
      expect(test_remover_class.refine_edges).to be true
    end

    it "sets alpha_matting" do
      expect(test_remover_class.alpha_matting).to be true
    end

    it "sets foreground_threshold" do
      expect(test_remover_class.foreground_threshold).to eq(0.6)
    end

    it "sets background_threshold" do
      expect(test_remover_class.background_threshold).to eq(0.4)
    end

    it "sets erode_size" do
      expect(test_remover_class.erode_size).to eq(2)
    end

    it "sets return_mask" do
      expect(test_remover_class.return_mask).to be true
    end

    it "sets description" do
      expect(test_remover_class.description).to eq("Test remover")
    end

    it "validates output_format" do
      expect {
        Class.new(described_class) do
          output_format :jpg
        end
      }.to raise_error(ArgumentError, /must be one of/)
    end

    it "validates foreground_threshold range" do
      expect {
        Class.new(described_class) do
          foreground_threshold 1.5
        end
      }.to raise_error(ArgumentError, /between 0.0 and 1.0/)
    end

    it "validates background_threshold range" do
      expect {
        Class.new(described_class) do
          background_threshold(-0.1)
        end
      }.to raise_error(ArgumentError, /between 0.0 and 1.0/)
    end

    it "validates erode_size is non-negative" do
      expect {
        Class.new(described_class) do
          erode_size(-1)
        end
      }.to raise_error(ArgumentError, /non-negative integer/)
    end
  end

  describe "defaults" do
    let(:default_remover) do
      Class.new(described_class)
    end

    it "has default output_format of :png" do
      expect(default_remover.output_format).to eq(:png)
    end

    it "has refine_edges false by default" do
      expect(default_remover.refine_edges).to be false
    end

    it "has alpha_matting false by default" do
      expect(default_remover.alpha_matting).to be false
    end

    it "has default foreground_threshold of 0.5" do
      expect(default_remover.foreground_threshold).to eq(0.5)
    end

    it "has default background_threshold of 0.5" do
      expect(default_remover.background_threshold).to eq(0.5)
    end

    it "has default erode_size of 0" do
      expect(default_remover.erode_size).to eq(0)
    end

    it "has return_mask false by default" do
      expect(default_remover.return_mask).to be false
    end
  end

  describe "inheritance" do
    let(:parent_class) do
      Class.new(described_class) do
        model "parent-remover"
        output_format :webp
        alpha_matting true
      end
    end

    let(:child_class) do
      Class.new(parent_class)
    end

    it "inherits settings from parent" do
      expect(child_class.model).to eq("parent-remover")
      expect(child_class.output_format).to eq(:webp)
      expect(child_class.alpha_matting).to be true
    end
  end

  describe ".call" do
    let(:remover_class) do
      Class.new(described_class) do
        model "rembg"
        output_format :png
      end
    end

    it "creates instance and calls execute" do
      instance = instance_double(remover_class)
      allow(remover_class).to receive(:new).and_return(instance)
      allow(instance).to receive(:call).and_return(double("result"))

      remover_class.call(image: "photo.jpg")

      expect(remover_class).to have_received(:new).with(image: "photo.jpg")
      expect(instance).to have_received(:call)
    end
  end

  describe "#initialize" do
    it "sets image and options" do
      remover = described_class.new(
        image: "photo.jpg",
        alpha_matting: true,
        return_mask: true
      )

      expect(remover.image).to eq("photo.jpg")
      expect(remover.options).to eq({ alpha_matting: true, return_mask: true })
    end
  end

  describe "caching" do
    let(:cached_remover) do
      Class.new(described_class) do
        model "rembg"
        cache_for 1.day
      end
    end

    it "enables caching with TTL" do
      expect(cached_remover.cache_enabled?).to be true
      expect(cached_remover.cache_ttl).to eq(1.day)
    end

    let(:uncached_remover) do
      Class.new(described_class) do
        model "rembg"
      end
    end

    it "disables caching by default" do
      expect(uncached_remover.cache_enabled?).to be false
    end
  end

  describe "valid output formats" do
    %i[png webp].each do |format|
      it "allows output_format :#{format}" do
        expect {
          Class.new(described_class) do
            output_format format
          end
        }.not_to raise_error
      end
    end
  end
end
