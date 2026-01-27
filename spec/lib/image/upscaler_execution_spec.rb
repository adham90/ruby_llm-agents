# frozen_string_literal: true

require "rails_helper"

RSpec.describe RubyLLM::Agents::ImageUpscaler::Execution do
  # Create test upscaler class
  let(:test_upscaler_class) do
    Class.new(RubyLLM::Agents::ImageUpscaler) do
      def self.name
        "TestImageUpscaler"
      end

      version "1.0.0"
      model "real-esrgan"
      cache_for 1.hour
      scale 4
    end
  end

  let(:mock_image_result) do
    double("ImageResult",
      url: "https://example.com/upscaled.png",
      data: nil,
      mime_type: "image/png",
      mask: nil)
  end

  before do
    RubyLLM::Agents.reset_configuration!
    RubyLLM::Agents.configure do |config|
      config.track_image_generation = true
      config.async_logging = false
      config.default_upscaler_model = "real-esrgan"
    end
    # Note: RubyLLM mock doesn't have upscale_image, so respond_to?(:upscale_image) returns false naturally
    allow(RubyLLM).to receive(:paint).and_return(mock_image_result)
  end

  describe "#execute" do
    context "with valid inputs" do
      before do
        allow(RubyLLM::Agents::Execution).to receive(:create!)
      end

      it "returns an ImageUpscaleResult" do
        result = test_upscaler_class.call(image: "https://example.com/source.jpg")

        expect(result).to be_a(RubyLLM::Agents::ImageUpscaleResult)
      end

      it "contains upscaled image" do
        result = test_upscaler_class.call(image: "https://example.com/source.jpg")

        expect(result.success?).to be true
      end
    end

    context "with validation errors" do
      before do
        allow(RubyLLM::Agents::Execution).to receive(:create!)
      end

      it "returns error result when image is nil" do
        result = test_upscaler_class.call(image: nil)

        expect(result.error?).to be true
        expect(result.error_message).to include("Image cannot be blank")
      end

      it "returns error result when file does not exist" do
        result = test_upscaler_class.call(image: "/nonexistent/file.jpg")

        expect(result.error?).to be true
        expect(result.error_message).to include("does not exist")
      end
    end

    context "with error handling" do
      before do
        allow(RubyLLM::Agents::Execution).to receive(:create!)
      end

      it "returns error result when upscaling fails" do
        allow(RubyLLM).to receive(:paint).and_raise(StandardError.new("API Error"))

        result = test_upscaler_class.call(image: "https://example.com/source.jpg")

        expect(result).to be_a(RubyLLM::Agents::ImageUpscaleResult)
        expect(result.error?).to be true
        expect(result.error_message).to include("API Error")
      end
    end
  end

  describe "private methods" do
    let(:execution_test_class) do
      Class.new(RubyLLM::Agents::ImageUpscaler) do
        include RubyLLM::Agents::ImageUpscaler::Execution

        def self.name
          "ExecutionTestUpscaler"
        end

        def self.version
          "1.0.0"
        end

        def self.model
          "real-esrgan"
        end

        def self.scale
          4
        end

        def self.face_enhance
          false
        end

        def self.denoise_strength
          nil
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

        def test_build_upscale_options
          build_upscale_options
        end

        def test_resolve_scale
          resolve_scale
        end

        def test_resolve_face_enhance
          resolve_face_enhance
        end

        def test_resolve_denoise_strength
          resolve_denoise_strength
        end

        def test_cache_key_components
          cache_key_components
        end

        def test_execution_type
          execution_type
        end

        def test_calculate_output_size
          calculate_output_size
        end
      end
    end

    let(:execution_instance) do
      execution_test_class.new(image: "https://example.com/test.jpg")
    end

    describe "#execution_type" do
      it "returns 'image_upscale'" do
        expect(execution_instance.test_execution_type).to eq("image_upscale")
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

    describe "#build_upscale_options" do
      it "returns options hash" do
        opts = execution_instance.test_build_upscale_options
        expect(opts).to be_a(Hash)
      end

      it "includes face_enhance when enabled" do
        instance = execution_test_class.new(image: "https://example.com/test.jpg", face_enhance: true)
        opts = instance.test_build_upscale_options
        expect(opts[:face_enhance]).to be true
      end
    end

    describe "#resolve_scale" do
      it "returns class default when no option" do
        expect(execution_instance.test_resolve_scale).to eq(4)
      end

      it "returns option when provided" do
        instance = execution_test_class.new(image: "https://example.com/test.jpg", scale: 2)
        expect(instance.test_resolve_scale).to eq(2)
      end
    end

    describe "#resolve_face_enhance" do
      it "returns class default when no option" do
        expect(execution_instance.test_resolve_face_enhance).to be false
      end

      it "returns option when provided" do
        instance = execution_test_class.new(image: "https://example.com/test.jpg", face_enhance: true)
        expect(instance.test_resolve_face_enhance).to be true
      end
    end

    describe "#cache_key_components" do
      it "includes required components" do
        components = execution_instance.test_cache_key_components

        expect(components).to include("image_upscaler")
        expect(components).to include("ExecutionTestUpscaler")
        expect(components).to include("real-esrgan")
        expect(components).to include("4")
      end
    end

    describe "#calculate_output_size" do
      it "returns nil for URL images" do
        expect(execution_instance.test_calculate_output_size).to be_nil
      end
    end
  end
end
