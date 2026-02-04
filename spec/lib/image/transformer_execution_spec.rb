# frozen_string_literal: true

require "rails_helper"

RSpec.describe RubyLLM::Agents::ImageTransformer::Execution do
  # Create test transformer class
  let(:test_transformer_class) do
    Class.new(RubyLLM::Agents::ImageTransformer) do
      def self.name
        "TestImageTransformer"
      end

      model "sdxl"
      cache_for 1.hour
      size "1024x1024"
      strength 0.75
    end
  end

  let(:mock_image_result) do
    double("ImageResult",
      url: "https://example.com/transformed.png",
      data: nil,
      mime_type: "image/png")
  end

  before do
    RubyLLM::Agents.reset_configuration!
    RubyLLM::Agents.configure do |config|
      config.track_image_generation = true
      config.async_logging = false
      config.default_transformer_model = "sdxl"
    end
    allow(RubyLLM).to receive(:paint).and_return(mock_image_result)
  end

  describe "#execute" do
    context "with valid inputs" do
      before do
        allow(RubyLLM::Agents::Execution).to receive(:create!)
      end

      it "returns an ImageTransformResult" do
        result = test_transformer_class.call(
          image: "https://example.com/source.jpg",
          prompt: "Transform to oil painting"
        )

        expect(result).to be_a(RubyLLM::Agents::ImageTransformResult)
      end

      it "contains transformed image" do
        result = test_transformer_class.call(
          image: "https://example.com/source.jpg",
          prompt: "Transform to oil painting"
        )

        expect(result.success?).to be true
      end
    end

    context "with validation errors" do
      before do
        allow(RubyLLM::Agents::Execution).to receive(:create!)
      end

      it "returns error result when image is nil" do
        result = test_transformer_class.call(image: nil, prompt: "Transform")

        expect(result.error?).to be true
        expect(result.error_message).to include("Image cannot be blank")
      end

      it "returns error result when prompt is nil" do
        result = test_transformer_class.call(image: "https://example.com/test.jpg", prompt: nil)

        expect(result.error?).to be true
        expect(result.error_message).to include("Prompt cannot be blank")
      end

      it "returns error result when prompt is empty" do
        result = test_transformer_class.call(image: "https://example.com/test.jpg", prompt: "   ")

        expect(result.error?).to be true
        expect(result.error_message).to include("Prompt cannot be blank")
      end

      it "returns error result when file does not exist" do
        result = test_transformer_class.call(image: "/nonexistent/file.jpg", prompt: "Transform")

        expect(result.error?).to be true
        expect(result.error_message).to include("does not exist")
      end

      it "returns error result when prompt exceeds max length" do
        long_prompt = "a" * 5000
        result = test_transformer_class.call(image: "https://example.com/test.jpg", prompt: long_prompt)

        expect(result.error?).to be true
        expect(result.error_message).to include("exceeds maximum length")
      end
    end

    context "with error handling" do
      before do
        allow(RubyLLM::Agents::Execution).to receive(:create!)
      end

      it "returns error result when transformation fails" do
        allow(RubyLLM).to receive(:paint).and_raise(StandardError.new("API Error"))

        result = test_transformer_class.call(
          image: "https://example.com/source.jpg",
          prompt: "Transform"
        )

        expect(result).to be_a(RubyLLM::Agents::ImageTransformResult)
        expect(result.error?).to be true
        expect(result.error_message).to include("API Error")
      end
    end
  end

  describe "private methods" do
    let(:execution_test_class) do
      Class.new(RubyLLM::Agents::ImageTransformer) do
        include RubyLLM::Agents::ImageTransformer::Execution

        def self.name
          "ExecutionTestTransformer"
        end

        def self.model
          "sdxl"
        end

        def self.size
          "1024x1024"
        end

        def self.strength
          0.75
        end

        def self.preserve_composition
          true
        end

        def self.negative_prompt
          nil
        end

        def self.guidance_scale
          nil
        end

        def self.steps
          nil
        end

        def self.content_policy
          :standard
        end

        def self.template_string
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

        def prompt
          @options[:prompt]
        end

        def config
          RubyLLM::Agents.configuration
        end

        def test_validate_inputs!
          validate_inputs!
        end

        def test_apply_template(text)
          apply_template(text)
        end

        def test_build_transform_options
          build_transform_options
        end

        def test_resolve_size
          resolve_size
        end

        def test_resolve_strength
          resolve_strength
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
        prompt: "Transform to watercolor"
      )
    end

    describe "#execution_type" do
      it "returns 'image_transform'" do
        expect(execution_instance.test_execution_type).to eq("image_transform")
      end
    end

    describe "#validate_inputs!" do
      it "raises error for nil image" do
        instance = execution_test_class.new(image: nil, prompt: "Test")
        expect { instance.test_validate_inputs! }.to raise_error(ArgumentError, /Image cannot be blank/)
      end

      it "raises error for nil prompt" do
        instance = execution_test_class.new(image: "https://example.com/test.jpg", prompt: nil)
        expect { instance.test_validate_inputs! }.to raise_error(ArgumentError, /Prompt cannot be blank/)
      end

      it "raises error for empty prompt" do
        instance = execution_test_class.new(image: "https://example.com/test.jpg", prompt: "  ")
        expect { instance.test_validate_inputs! }.to raise_error(ArgumentError, /Prompt cannot be blank/)
      end
    end

    describe "#apply_template" do
      it "returns text unchanged when no template" do
        result = execution_instance.test_apply_template("My prompt")
        expect(result).to eq("My prompt")
      end

      it "applies template when set" do
        allow(execution_test_class).to receive(:template_string).and_return("Create: {prompt}")
        result = execution_instance.test_apply_template("a beautiful sunset")
        expect(result).to eq("Create: a beautiful sunset")
      end
    end

    describe "#build_transform_options" do
      it "returns empty hash with default config" do
        opts = execution_instance.test_build_transform_options
        expect(opts).to include(:preserve_composition)
      end
    end

    describe "#resolve_size" do
      it "returns class default when no option" do
        expect(execution_instance.test_resolve_size).to eq("1024x1024")
      end

      it "returns option when provided" do
        instance = execution_test_class.new(
          image: "https://example.com/test.jpg",
          prompt: "Test",
          size: "512x512"
        )
        expect(instance.test_resolve_size).to eq("512x512")
      end
    end

    describe "#resolve_strength" do
      it "returns class default when no option" do
        expect(execution_instance.test_resolve_strength).to eq(0.75)
      end

      it "returns option when provided" do
        instance = execution_test_class.new(
          image: "https://example.com/test.jpg",
          prompt: "Test",
          strength: 0.5
        )
        expect(instance.test_resolve_strength).to eq(0.5)
      end
    end

    describe "#resolve_count" do
      it "returns 1 by default" do
        expect(execution_instance.test_resolve_count).to eq(1)
      end

      it "returns option when provided" do
        instance = execution_test_class.new(
          image: "https://example.com/test.jpg",
          prompt: "Test",
          count: 3
        )
        expect(instance.test_resolve_count).to eq(3)
      end
    end

    describe "#cache_key_components" do
      it "includes required components" do
        components = execution_instance.test_cache_key_components

        expect(components).to include("image_transformer")
        expect(components).to include("ExecutionTestTransformer")
        expect(components).to include("sdxl")
        expect(components).to include("1024x1024")
      end
    end
  end
end
