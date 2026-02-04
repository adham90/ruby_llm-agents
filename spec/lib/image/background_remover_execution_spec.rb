# frozen_string_literal: true

require "rails_helper"

RSpec.describe RubyLLM::Agents::BackgroundRemover::Execution do
  # Create test remover class
  let(:test_remover_class) do
    Class.new(RubyLLM::Agents::BackgroundRemover) do
      def self.name
        "TestBackgroundRemover"
      end

      model "rembg"
      cache_for 1.hour
      output_format :png
    end
  end

  let(:mock_image_result) do
    double("ImageResult",
      url: "https://example.com/foreground.png",
      data: nil,
      mime_type: "image/png",
      mask: nil)
  end

  before do
    RubyLLM::Agents.reset_configuration!
    RubyLLM::Agents.configure do |config|
      config.track_image_generation = true
      config.async_logging = false
      config.default_background_remover_model = "rembg"
      config.default_background_output_format = :png
    end
    # Note: RubyLLM mock doesn't have remove_background, so respond_to?(:remove_background) returns false naturally
    allow(RubyLLM).to receive(:paint).and_return(mock_image_result)
  end

  describe "#execute" do
    context "with valid inputs" do
      before do
        allow(RubyLLM::Agents::Execution).to receive(:create!)
      end

      it "returns a BackgroundRemovalResult" do
        result = test_remover_class.call(image: "https://example.com/source.jpg")

        expect(result).to be_a(RubyLLM::Agents::BackgroundRemovalResult)
      end

      it "contains foreground image" do
        result = test_remover_class.call(image: "https://example.com/source.jpg")

        expect(result.success?).to be true
      end
    end

    context "with validation errors" do
      before do
        allow(RubyLLM::Agents::Execution).to receive(:create!)
      end

      it "returns error result when image is nil" do
        result = test_remover_class.call(image: nil)

        expect(result.error?).to be true
        expect(result.error_message).to include("Image cannot be blank")
      end

      it "returns error result when file does not exist" do
        result = test_remover_class.call(image: "/nonexistent/file.jpg")

        expect(result.error?).to be true
        expect(result.error_message).to include("does not exist")
      end
    end

    context "with error handling" do
      before do
        allow(RubyLLM::Agents::Execution).to receive(:create!)
      end

      it "returns error result when removal fails" do
        allow(RubyLLM).to receive(:paint).and_raise(StandardError.new("API Error"))

        result = test_remover_class.call(image: "https://example.com/source.jpg")

        expect(result).to be_a(RubyLLM::Agents::BackgroundRemovalResult)
        expect(result.error?).to be true
        expect(result.error_message).to include("API Error")
      end
    end
  end

  describe "private methods" do
    let(:execution_test_class) do
      Class.new(RubyLLM::Agents::BackgroundRemover) do
        include RubyLLM::Agents::BackgroundRemover::Execution

        def self.name
          "ExecutionTestRemover"
        end

        def self.model
          "rembg"
        end

        def self.output_format
          :png
        end

        def self.refine_edges
          false
        end

        def self.alpha_matting
          false
        end

        def self.foreground_threshold
          240
        end

        def self.background_threshold
          10
        end

        def self.erode_size
          0
        end

        def self.return_mask
          false
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

        def test_build_removal_options
          build_removal_options
        end

        def test_resolve_output_format
          resolve_output_format
        end

        def test_resolve_refine_edges
          resolve_refine_edges
        end

        def test_resolve_alpha_matting
          resolve_alpha_matting
        end

        def test_resolve_foreground_threshold
          resolve_foreground_threshold
        end

        def test_resolve_background_threshold
          resolve_background_threshold
        end

        def test_resolve_erode_size
          resolve_erode_size
        end

        def test_resolve_return_mask
          resolve_return_mask
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
      it "returns 'background_removal'" do
        expect(execution_instance.test_execution_type).to eq("background_removal")
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

    describe "#build_removal_options" do
      it "returns options hash with output_format" do
        opts = execution_instance.test_build_removal_options
        expect(opts).to be_a(Hash)
        expect(opts[:output_format]).to eq(:png)
      end

      it "includes refine_edges when enabled" do
        instance = execution_test_class.new(image: "https://example.com/test.jpg", refine_edges: true)
        opts = instance.test_build_removal_options
        expect(opts[:refine_edges]).to be true
      end

      it "includes alpha_matting when enabled" do
        instance = execution_test_class.new(image: "https://example.com/test.jpg", alpha_matting: true)
        opts = instance.test_build_removal_options
        expect(opts[:alpha_matting]).to be true
      end

      it "includes erode_size when > 0" do
        instance = execution_test_class.new(image: "https://example.com/test.jpg", erode_size: 5)
        opts = instance.test_build_removal_options
        expect(opts[:erode_size]).to eq(5)
      end
    end

    describe "#resolve_output_format" do
      it "returns class default when no option" do
        expect(execution_instance.test_resolve_output_format).to eq(:png)
      end

      it "returns option when provided" do
        instance = execution_test_class.new(image: "https://example.com/test.jpg", output_format: :webp)
        expect(instance.test_resolve_output_format).to eq(:webp)
      end
    end

    describe "#resolve_refine_edges" do
      it "returns class default when no option" do
        expect(execution_instance.test_resolve_refine_edges).to be false
      end

      it "returns option when provided" do
        instance = execution_test_class.new(image: "https://example.com/test.jpg", refine_edges: true)
        expect(instance.test_resolve_refine_edges).to be true
      end
    end

    describe "#resolve_alpha_matting" do
      it "returns class default when no option" do
        expect(execution_instance.test_resolve_alpha_matting).to be false
      end

      it "returns option when provided" do
        instance = execution_test_class.new(image: "https://example.com/test.jpg", alpha_matting: true)
        expect(instance.test_resolve_alpha_matting).to be true
      end
    end

    describe "#resolve_foreground_threshold" do
      it "returns class default when no option" do
        expect(execution_instance.test_resolve_foreground_threshold).to eq(240)
      end

      it "returns option when provided" do
        instance = execution_test_class.new(image: "https://example.com/test.jpg", foreground_threshold: 200)
        expect(instance.test_resolve_foreground_threshold).to eq(200)
      end
    end

    describe "#resolve_background_threshold" do
      it "returns class default when no option" do
        expect(execution_instance.test_resolve_background_threshold).to eq(10)
      end

      it "returns option when provided" do
        instance = execution_test_class.new(image: "https://example.com/test.jpg", background_threshold: 20)
        expect(instance.test_resolve_background_threshold).to eq(20)
      end
    end

    describe "#resolve_erode_size" do
      it "returns class default when no option" do
        expect(execution_instance.test_resolve_erode_size).to eq(0)
      end

      it "returns option when provided" do
        instance = execution_test_class.new(image: "https://example.com/test.jpg", erode_size: 3)
        expect(instance.test_resolve_erode_size).to eq(3)
      end
    end

    describe "#resolve_return_mask" do
      it "returns class default when no option" do
        expect(execution_instance.test_resolve_return_mask).to be false
      end

      it "returns option when provided" do
        instance = execution_test_class.new(image: "https://example.com/test.jpg", return_mask: true)
        expect(instance.test_resolve_return_mask).to be true
      end
    end

    describe "#cache_key_components" do
      it "includes required components" do
        components = execution_instance.test_cache_key_components

        expect(components).to include("background_remover")
        expect(components).to include("ExecutionTestRemover")
        expect(components).to include("rembg")
        expect(components).to include("png")
        expect(components).to include("false") # alpha_matting
        expect(components).to include("240") # foreground_threshold
      end
    end
  end
end
