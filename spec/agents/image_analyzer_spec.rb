# frozen_string_literal: true

require "rails_helper"

RSpec.describe RubyLLM::Agents::ImageAnalyzer do
  describe "DSL" do
    let(:test_analyzer_class) do
      Class.new(described_class) do
        model "gpt-4o"
        analysis_type :detailed
        extract_colors true
        detect_objects true
        extract_text true
        max_tags 15
        description "Test analyzer"
        version "v2"
      end
    end

    it "sets model" do
      expect(test_analyzer_class.model).to eq("gpt-4o")
    end

    it "sets analysis_type" do
      expect(test_analyzer_class.analysis_type).to eq(:detailed)
    end

    it "sets extract_colors" do
      expect(test_analyzer_class.extract_colors).to be true
    end

    it "sets detect_objects" do
      expect(test_analyzer_class.detect_objects).to be true
    end

    it "sets extract_text" do
      expect(test_analyzer_class.extract_text).to be true
    end

    it "sets max_tags" do
      expect(test_analyzer_class.max_tags).to eq(15)
    end

    it "sets description" do
      expect(test_analyzer_class.description).to eq("Test analyzer")
    end

    it "sets version" do
      expect(test_analyzer_class.version).to eq("v2")
    end

    it "validates analysis_type" do
      expect {
        Class.new(described_class) do
          analysis_type :invalid
        end
      }.to raise_error(ArgumentError, /must be one of/)
    end

    it "validates max_tags is positive" do
      expect {
        Class.new(described_class) do
          max_tags 0
        end
      }.to raise_error(ArgumentError, /positive integer/)
    end

    it "validates max_tags is an integer" do
      expect {
        Class.new(described_class) do
          max_tags "ten"
        end
      }.to raise_error(ArgumentError, /positive integer/)
    end
  end

  describe "defaults" do
    let(:default_analyzer) do
      Class.new(described_class)
    end

    it "has default analysis_type of :detailed" do
      expect(default_analyzer.analysis_type).to eq(:detailed)
    end

    it "has extract_colors false by default" do
      expect(default_analyzer.extract_colors).to be false
    end

    it "has detect_objects false by default" do
      expect(default_analyzer.detect_objects).to be false
    end

    it "has extract_text false by default" do
      expect(default_analyzer.extract_text).to be false
    end

    it "has default max_tags of 10" do
      expect(default_analyzer.max_tags).to eq(10)
    end
  end

  describe "inheritance" do
    let(:parent_class) do
      Class.new(described_class) do
        model "parent-model"
        analysis_type :all
        extract_colors true
        max_tags 20
      end
    end

    let(:child_class) do
      Class.new(parent_class)
    end

    it "inherits settings from parent" do
      expect(child_class.model).to eq("parent-model")
      expect(child_class.analysis_type).to eq(:all)
      expect(child_class.extract_colors).to be true
      expect(child_class.max_tags).to eq(20)
    end
  end

  describe ".call" do
    let(:analyzer_class) do
      Class.new(described_class) do
        model "gpt-4o"
        analysis_type :caption
      end
    end

    it "creates instance and calls execute" do
      instance = instance_double(analyzer_class)
      allow(analyzer_class).to receive(:new).and_return(instance)
      allow(instance).to receive(:call).and_return(double("result"))

      analyzer_class.call(image: "photo.jpg")

      expect(analyzer_class).to have_received(:new).with(image: "photo.jpg")
      expect(instance).to have_received(:call)
    end
  end

  describe "#initialize" do
    it "sets image and options" do
      analyzer = described_class.new(
        image: "photo.jpg",
        analysis_type: :all,
        extract_colors: true
      )

      expect(analyzer.image).to eq("photo.jpg")
      expect(analyzer.options).to eq({ analysis_type: :all, extract_colors: true })
    end
  end

  describe "caching" do
    let(:cached_analyzer) do
      Class.new(described_class) do
        model "gpt-4o"
        cache_for 1.day
      end
    end

    it "enables caching with TTL" do
      expect(cached_analyzer.cache_enabled?).to be true
      expect(cached_analyzer.cache_ttl).to eq(1.day)
    end

    let(:uncached_analyzer) do
      Class.new(described_class) do
        model "gpt-4o"
      end
    end

    it "disables caching by default" do
      expect(uncached_analyzer.cache_enabled?).to be false
    end
  end

  describe "valid analysis types" do
    %i[caption detailed tags objects colors all].each do |type|
      it "allows analysis_type :#{type}" do
        expect {
          Class.new(described_class) do
            analysis_type type
          end
        }.not_to raise_error
      end
    end
  end

  describe "custom_prompt" do
    let(:custom_prompt_analyzer) do
      Class.new(described_class) do
        custom_prompt "Describe this product in detail for an e-commerce listing"
      end
    end

    it "sets custom_prompt" do
      expect(custom_prompt_analyzer.custom_prompt).to eq(
        "Describe this product in detail for an e-commerce listing"
      )
    end

    let(:default_prompt_analyzer) do
      Class.new(described_class)
    end

    it "has nil custom_prompt by default" do
      expect(default_prompt_analyzer.custom_prompt).to be_nil
    end
  end
end
