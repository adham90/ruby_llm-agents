# frozen_string_literal: true

require "rails_helper"

RSpec.describe RubyLLM::Agents::ImageEditor::Execution do
  # Create test editor class
  let(:test_editor_class) do
    Class.new(RubyLLM::Agents::ImageEditor) do
      def self.name
        "TestImageEditor"
      end

      version "1.0.0"
      model "dall-e-3"
      cache_for 1.hour
      size "1024x1024"
    end
  end

  let(:mock_image_result) do
    double("ImageResult",
      url: "https://example.com/edited.png",
      data: nil,
      mime_type: "image/png")
  end

  before do
    RubyLLM::Agents.reset_configuration!
    RubyLLM::Agents.configure do |config|
      config.track_image_generation = true
      config.async_logging = false
      config.default_editor_model = "dall-e-3"
    end
    # Note: RubyLLM mock doesn't have edit_image, so respond_to?(:edit_image) returns false naturally
    allow(RubyLLM).to receive(:paint).and_return(mock_image_result)
  end

  describe "#execute" do
    context "with valid inputs" do
      before do
        allow(RubyLLM::Agents::Execution).to receive(:create!)
      end

      it "returns an ImageEditResult" do
        result = test_editor_class.call(
          image: "https://example.com/source.jpg",
          mask: "https://example.com/mask.png",
          prompt: "Add a hat to the person"
        )

        expect(result).to be_a(RubyLLM::Agents::ImageEditResult)
      end

      it "contains edited image" do
        result = test_editor_class.call(
          image: "https://example.com/source.jpg",
          mask: "https://example.com/mask.png",
          prompt: "Add a hat"
        )

        expect(result.success?).to be true
      end
    end

    context "with validation errors" do
      before do
        allow(RubyLLM::Agents::Execution).to receive(:create!)
      end

      it "returns error result when image is nil" do
        result = test_editor_class.call(image: nil, mask: "https://example.com/mask.png", prompt: "Edit")

        expect(result.error?).to be true
        expect(result.error_message).to include("Image cannot be blank")
      end

      it "returns error result when mask is nil" do
        result = test_editor_class.call(image: "https://example.com/test.jpg", mask: nil, prompt: "Edit")

        expect(result.error?).to be true
        expect(result.error_message).to include("Mask cannot be blank")
      end

      it "returns error result when prompt is nil" do
        result = test_editor_class.call(image: "https://example.com/test.jpg", mask: "https://example.com/mask.png", prompt: nil)

        expect(result.error?).to be true
        expect(result.error_message).to include("Prompt cannot be blank")
      end

      it "returns error result when prompt is empty" do
        result = test_editor_class.call(image: "https://example.com/test.jpg", mask: "https://example.com/mask.png", prompt: "   ")

        expect(result.error?).to be true
        expect(result.error_message).to include("Prompt cannot be blank")
      end

      it "returns error result when image file does not exist" do
        result = test_editor_class.call(image: "/nonexistent/file.jpg", mask: "https://example.com/mask.png", prompt: "Edit")

        expect(result.error?).to be true
        expect(result.error_message).to include("Image file does not exist")
      end

      it "returns error result when mask file does not exist" do
        result = test_editor_class.call(image: "https://example.com/test.jpg", mask: "/nonexistent/mask.png", prompt: "Edit")

        expect(result.error?).to be true
        expect(result.error_message).to include("Mask file does not exist")
      end
    end

    context "with error handling" do
      before do
        allow(RubyLLM::Agents::Execution).to receive(:create!)
      end

      it "returns error result when editing fails" do
        allow(RubyLLM).to receive(:paint).and_raise(StandardError.new("API Error"))

        result = test_editor_class.call(
          image: "https://example.com/source.jpg",
          mask: "https://example.com/mask.png",
          prompt: "Edit"
        )

        expect(result).to be_a(RubyLLM::Agents::ImageEditResult)
        expect(result.error?).to be true
        expect(result.error_message).to include("API Error")
      end
    end
  end

  describe "private methods" do
    let(:execution_test_class) do
      Class.new(RubyLLM::Agents::ImageEditor) do
        include RubyLLM::Agents::ImageEditor::Execution

        def self.name
          "ExecutionTestEditor"
        end

        def self.version
          "1.0.0"
        end

        def self.model
          "dall-e-3"
        end

        def self.size
          "1024x1024"
        end

        def self.content_policy
          :standard
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

        def mask
          @options[:mask]
        end

        def prompt
          @options[:prompt]
        end

        def config
          RubyLLM::Agents.configuration
        end

        def test_validate_inputs!
          validate_inputs!
        end

        def test_validate_file_exists!(file, name)
          validate_file_exists!(file, name)
        end

        def test_build_edit_options
          build_edit_options
        end

        def test_resolve_size
          resolve_size
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
      execution_test_class.new(
        image: "https://example.com/test.jpg",
        mask: "https://example.com/mask.png",
        prompt: "Add a hat"
      )
    end

    describe "#execution_type" do
      it "returns 'image_edit'" do
        expect(execution_instance.test_execution_type).to eq("image_edit")
      end
    end

    describe "#validate_inputs!" do
      it "raises error for nil image" do
        instance = execution_test_class.new(image: nil, mask: "https://example.com/mask.png", prompt: "Test")
        expect { instance.test_validate_inputs! }.to raise_error(ArgumentError, /Image cannot be blank/)
      end

      it "raises error for nil mask" do
        instance = execution_test_class.new(image: "https://example.com/test.jpg", mask: nil, prompt: "Test")
        expect { instance.test_validate_inputs! }.to raise_error(ArgumentError, /Mask cannot be blank/)
      end

      it "raises error for nil prompt" do
        instance = execution_test_class.new(image: "https://example.com/test.jpg", mask: "https://example.com/mask.png", prompt: nil)
        expect { instance.test_validate_inputs! }.to raise_error(ArgumentError, /Prompt cannot be blank/)
      end
    end

    describe "#validate_file_exists!" do
      it "does nothing for URLs" do
        expect { execution_instance.test_validate_file_exists!("https://example.com/file.jpg", "Image") }.not_to raise_error
      end

      it "raises error for non-existent file" do
        expect { execution_instance.test_validate_file_exists!("/nonexistent.jpg", "Image") }.to raise_error(ArgumentError, /Image file does not exist/)
      end
    end

    describe "#build_edit_options" do
      it "returns options hash" do
        opts = execution_instance.test_build_edit_options
        expect(opts).to be_a(Hash)
      end
    end

    describe "#resolve_size" do
      it "returns class default when no option" do
        expect(execution_instance.test_resolve_size).to eq("1024x1024")
      end

      it "returns option when provided" do
        instance = execution_test_class.new(
          image: "https://example.com/test.jpg",
          mask: "https://example.com/mask.png",
          prompt: "Test",
          size: "512x512"
        )
        expect(instance.test_resolve_size).to eq("512x512")
      end
    end

    describe "#resolve_count" do
      it "returns 1 by default" do
        expect(execution_instance.test_resolve_count).to eq(1)
      end
    end

    describe "#cache_key_components" do
      it "includes required components" do
        components = execution_instance.test_cache_key_components

        expect(components).to include("image_editor")
        expect(components).to include("ExecutionTestEditor")
        expect(components).to include("dall-e-3")
        expect(components).to include("1024x1024")
      end
    end
  end
end
