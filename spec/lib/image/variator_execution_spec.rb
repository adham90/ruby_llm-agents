# frozen_string_literal: true

require "rails_helper"

RSpec.describe RubyLLM::Agents::ImageVariator::Execution do
  # Create test variator class
  let(:test_variator_class) do
    Class.new(RubyLLM::Agents::ImageVariator) do
      def self.name
        "TestImageVariator"
      end

      model "dall-e-3"
      cache_for 1.hour
      size "1024x1024"
      variation_strength 0.5
    end
  end

  let(:mock_image_result) do
    double("ImageResult",
      url: "https://example.com/variation.png",
      data: nil,
      mime_type: "image/png")
  end

  before do
    RubyLLM::Agents.reset_configuration!
    RubyLLM::Agents.configure do |config|
      config.track_image_generation = true
      config.async_logging = false
      config.default_variator_model = "dall-e-3"
    end
    # Note: RubyLLM mock doesn't have create_image_variation, so respond_to?(:create_image_variation) returns false naturally
    allow(RubyLLM).to receive(:paint).and_return(mock_image_result)
  end

  describe "#execute" do
    context "with valid inputs" do
      before do
        allow(RubyLLM::Agents::Execution).to receive(:create!)
      end

      it "returns an ImageVariationResult" do
        result = test_variator_class.call(image: "https://example.com/source.jpg")

        expect(result).to be_a(RubyLLM::Agents::ImageVariationResult)
      end

      it "contains variation image" do
        result = test_variator_class.call(image: "https://example.com/source.jpg")

        expect(result.success?).to be true
      end
    end

    context "with validation errors" do
      before do
        allow(RubyLLM::Agents::Execution).to receive(:create!)
      end

      it "returns error result when image is nil" do
        result = test_variator_class.call(image: nil)

        expect(result.error?).to be true
        expect(result.error_message).to include("Image cannot be blank")
      end

      it "returns error result when file does not exist" do
        result = test_variator_class.call(image: "/nonexistent/file.jpg")

        expect(result.error?).to be true
        expect(result.error_message).to include("does not exist")
      end
    end

    context "with error handling" do
      before do
        allow(RubyLLM::Agents::Execution).to receive(:create!)
      end

      it "returns error result when variation fails" do
        allow(RubyLLM).to receive(:paint).and_raise(StandardError.new("API Error"))

        result = test_variator_class.call(image: "https://example.com/source.jpg")

        expect(result).to be_a(RubyLLM::Agents::ImageVariationResult)
        expect(result.error?).to be true
        expect(result.error_message).to include("API Error")
      end
    end
  end

  describe "private methods" do
    let(:execution_test_class) do
      Class.new(RubyLLM::Agents::ImageVariator) do
        include RubyLLM::Agents::ImageVariator::Execution

        def self.name
          "ExecutionTestVariator"
        end

        def self.model
          "dall-e-3"
        end

        def self.size
          "1024x1024"
        end

        def self.variation_strength
          0.5
        end

        def self.cache_enabled?
          true
        end

        def self.cache_ttl
          1.hour
        end

        attr_accessor :options

        def initialize(opts = {})
          @options = opts
          @tenant_id = nil
        end

        def image
          @options[:image]
        end

        def test_validate_image!
          validate_image!
        end

        def test_build_variation_options
          build_variation_options
        end

        def test_resolve_size
          resolve_size
        end

        def test_resolve_variation_strength
          resolve_variation_strength
        end

        def test_resolve_count
          resolve_count
        end

        def test_cache_key_components
          cache_key_components
        end

        def test_execution_type
          execution_type
        end
      end
    end

    let(:execution_instance) do
      execution_test_class.new(image: "https://example.com/test.jpg")
    end

    describe "#execution_type" do
      it "returns 'image_variation'" do
        expect(execution_instance.test_execution_type).to eq("image_variation")
      end
    end

    describe "#validate_image!" do
      it "raises error for nil image" do
        instance = execution_test_class.new(image: nil)
        expect { instance.test_validate_image! }.to raise_error(ArgumentError, /Image cannot be blank/)
      end

      it "raises error for non-existent file" do
        instance = execution_test_class.new(image: "/nonexistent/file.jpg")
        expect { instance.test_validate_image! }.to raise_error(ArgumentError, /does not exist/)
      end

      it "accepts URL" do
        instance = execution_test_class.new(image: "https://example.com/test.jpg")
        expect { instance.test_validate_image! }.not_to raise_error
      end
    end

    describe "#build_variation_options" do
      it "returns options hash" do
        opts = execution_instance.test_build_variation_options
        expect(opts).to be_a(Hash)
      end

      it "includes assume_model_exists when option provided" do
        instance = execution_test_class.new(image: "https://example.com/test.jpg", assume_model_exists: true)
        opts = instance.test_build_variation_options
        expect(opts[:assume_model_exists]).to be true
      end
    end

    describe "#resolve_size" do
      it "returns class default when no option" do
        expect(execution_instance.test_resolve_size).to eq("1024x1024")
      end

      it "returns option when provided" do
        instance = execution_test_class.new(image: "https://example.com/test.jpg", size: "512x512")
        expect(instance.test_resolve_size).to eq("512x512")
      end
    end

    describe "#resolve_variation_strength" do
      it "returns class default when no option" do
        expect(execution_instance.test_resolve_variation_strength).to eq(0.5)
      end

      it "returns option when provided" do
        instance = execution_test_class.new(image: "https://example.com/test.jpg", variation_strength: 0.8)
        expect(instance.test_resolve_variation_strength).to eq(0.8)
      end
    end

    describe "#resolve_count" do
      it "returns 1 by default" do
        expect(execution_instance.test_resolve_count).to eq(1)
      end

      it "returns option when provided" do
        instance = execution_test_class.new(image: "https://example.com/test.jpg", count: 3)
        expect(instance.test_resolve_count).to eq(3)
      end
    end

    describe "#cache_key_components" do
      it "includes required components" do
        components = execution_instance.test_cache_key_components

        expect(components).to include("image_variator")
        expect(components).to include("ExecutionTestVariator")
        expect(components).to include("dall-e-3")
        expect(components).to include("1024x1024")
        expect(components).to include("0.5")
      end
    end
  end
end
