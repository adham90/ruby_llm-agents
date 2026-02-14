# frozen_string_literal: true

require "rails_helper"

RSpec.describe RubyLLM::Agents::ImageAnalyzer::Execution do
  # Create test analyzer class that uses the Execution module
  let(:test_analyzer_class) do
    Class.new(RubyLLM::Agents::ImageAnalyzer) do
      def self.name
        "TestImageAnalyzer"
      end

      model "gpt-4o"
      cache_for 1.hour
      analysis_type :detailed
      max_tags 10
    end
  end

  let(:mock_chat) { double("RubyLLM::Chat") }
  let(:mock_response) do
    double("Response",
      content: '{"caption": "A test image", "description": "Detailed description", "tags": ["tag1", "tag2"]}')
  end

  before do
    RubyLLM::Agents.reset_configuration!
    RubyLLM::Agents.configure do |config|
      config.track_image_generation = true
      config.async_logging = false
      config.default_analyzer_model = "gpt-4o"
      config.default_analysis_type = :detailed
      config.default_analyzer_max_tags = 10
    end
    allow(RubyLLM).to receive(:chat).and_return(mock_chat)
    allow(mock_chat).to receive(:ask).and_return(mock_response)
  end

  describe "#execute" do
    context "with valid image URL" do
      before do
        allow(RubyLLM::Agents::Execution).to receive(:create!)
      end

      it "returns an ImageAnalysisResult" do
        result = test_analyzer_class.call(image: "https://example.com/test.jpg")

        expect(result).to be_a(RubyLLM::Agents::ImageAnalysisResult)
      end

      it "extracts caption from response" do
        result = test_analyzer_class.call(image: "https://example.com/test.jpg")

        expect(result.caption).to eq("A test image")
      end

      it "extracts tags from response" do
        result = test_analyzer_class.call(image: "https://example.com/test.jpg")

        expect(result.tags).to eq(["tag1", "tag2"])
      end
    end

    context "with validation errors" do
      before do
        allow(RubyLLM::Agents::Execution).to receive(:create!)
      end

      it "returns error result when image is nil" do
        result = test_analyzer_class.call(image: nil)

        expect(result.error?).to be true
        expect(result.error_message).to include("Image cannot be blank")
      end

      it "returns error result when file does not exist" do
        result = test_analyzer_class.call(image: "/path/to/nonexistent/file.jpg")

        expect(result.error?).to be true
        expect(result.error_message).to include("does not exist")
      end
    end

    context "with error handling" do
      before do
        allow(RubyLLM::Agents::Execution).to receive(:create!)
      end

      it "returns error result when analysis fails" do
        allow(mock_chat).to receive(:ask).and_raise(StandardError.new("API Error"))

        result = test_analyzer_class.call(image: "https://example.com/test.jpg")

        expect(result).to be_a(RubyLLM::Agents::ImageAnalysisResult)
        expect(result.error?).to be true
        expect(result.error_message).to include("API Error")
      end
    end
  end

  describe "private methods" do
    let(:execution_test_class) do
      Class.new(RubyLLM::Agents::ImageAnalyzer) do
        include RubyLLM::Agents::ImageAnalyzer::Execution

        def self.name
          "ExecutionTestAnalyzer"
        end

        def self.model
          "gpt-4o"
        end

        def self.analysis_type
          :detailed
        end

        def self.max_tags
          10
        end

        def self.extract_colors
          false
        end

        def self.detect_objects
          false
        end

        def self.extract_text
          false
        end

        def self.custom_prompt
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

        def test_build_analysis_prompt
          build_analysis_prompt
        end

        def test_build_json_schema
          build_json_schema
        end

        def test_parse_analysis_response(response)
          parse_analysis_response(response)
        end

        def test_normalize_tags(tags)
          normalize_tags(tags)
        end

        def test_normalize_objects(objects)
          normalize_objects(objects)
        end

        def test_normalize_colors(colors)
          normalize_colors(colors)
        end

        def test_detect_mime_type(path)
          detect_mime_type(path)
        end

        def test_extract_caption_from_text(content)
          extract_caption_from_text(content)
        end

        def test_extract_tags_from_text(content)
          extract_tags_from_text(content)
        end

        def test_cache_key_components
          cache_key_components
        end

        def test_execution_type
          execution_type
        end
      end
    end

    let(:execution_instance) { execution_test_class.new(image: "https://example.com/test.jpg") }

    describe "#execution_type" do
      it "returns 'image_analysis'" do
        expect(execution_instance.test_execution_type).to eq("image_analysis")
      end
    end

    describe "#validate_image!" do
      it "raises error for nil image" do
        instance = execution_test_class.new(image: nil)
        expect { instance.test_validate_image! }.to raise_error(ArgumentError, /cannot be blank/)
      end

      it "raises error for non-existent file path" do
        instance = execution_test_class.new(image: "/nonexistent/path.jpg")
        expect { instance.test_validate_image! }.to raise_error(ArgumentError, /does not exist/)
      end

      it "does not raise error for URL" do
        instance = execution_test_class.new(image: "https://example.com/image.jpg")
        expect { instance.test_validate_image! }.not_to raise_error
      end
    end

    describe "#build_analysis_prompt" do
      it "builds prompt for detailed analysis" do
        prompt = execution_instance.test_build_analysis_prompt
        expect(prompt).to include("detailed description")
      end

      it "includes JSON schema in prompt" do
        prompt = execution_instance.test_build_analysis_prompt
        expect(prompt).to include("Format your response as JSON")
      end
    end

    describe "#build_json_schema" do
      it "returns JSON schema string" do
        schema = execution_instance.test_build_json_schema
        expect(schema).to include("caption")
        expect(schema).to include("tags")
        expect(schema).to include("objects")
      end
    end

    describe "#parse_analysis_response" do
      it "parses valid JSON response" do
        response = double("Response", content: '{"caption": "Test", "tags": ["a", "b"]}')
        result = execution_instance.test_parse_analysis_response(response)

        expect(result[:caption]).to eq("Test")
        expect(result[:tags]).to eq(["a", "b"])
      end

      it "falls back to text parsing for invalid JSON" do
        response = double("Response", content: "This is just text without JSON")
        result = execution_instance.test_parse_analysis_response(response)

        expect(result[:description]).to eq("This is just text without JSON")
      end
    end

    describe "#normalize_tags" do
      it "returns empty array for non-array input" do
        expect(execution_instance.test_normalize_tags(nil)).to eq([])
        expect(execution_instance.test_normalize_tags("string")).to eq([])
      end

      it "normalizes and limits tags" do
        tags = Array.new(20) { |i| "tag#{i}" }
        result = execution_instance.test_normalize_tags(tags)

        expect(result.size).to eq(10) # max_tags
      end

      it "strips whitespace from tags" do
        result = execution_instance.test_normalize_tags(["  tag1  ", " tag2 "])
        expect(result).to eq(["tag1", "tag2"])
      end
    end

    describe "#normalize_objects" do
      it "returns empty array for non-array input" do
        expect(execution_instance.test_normalize_objects(nil)).to eq([])
      end

      it "normalizes object data" do
        objects = [{ name: "car", location: "center", confidence: "HIGH" }]
        result = execution_instance.test_normalize_objects(objects)

        expect(result.first[:name]).to eq("car")
        expect(result.first[:confidence]).to eq("high") # downcased
      end

      it "skips non-hash items" do
        result = execution_instance.test_normalize_objects(["invalid", { name: "valid" }])
        expect(result.size).to eq(1)
      end
    end

    describe "#normalize_colors" do
      it "returns empty array for non-array input" do
        expect(execution_instance.test_normalize_colors(nil)).to eq([])
      end

      it "normalizes color data" do
        colors = [{ hex: "#FF0000", name: "red", percentage: "25" }]
        result = execution_instance.test_normalize_colors(colors)

        expect(result.first[:hex]).to eq("#FF0000")
        expect(result.first[:percentage]).to eq(25.0) # converted to float
      end
    end

    describe "#detect_mime_type" do
      it "detects JPEG" do
        expect(execution_instance.test_detect_mime_type("image.jpg")).to eq("image/jpeg")
        expect(execution_instance.test_detect_mime_type("image.jpeg")).to eq("image/jpeg")
      end

      it "detects PNG" do
        expect(execution_instance.test_detect_mime_type("image.png")).to eq("image/png")
      end

      it "detects GIF" do
        expect(execution_instance.test_detect_mime_type("image.gif")).to eq("image/gif")
      end

      it "detects WebP" do
        expect(execution_instance.test_detect_mime_type("image.webp")).to eq("image/webp")
      end

      it "defaults to PNG for unknown extensions" do
        expect(execution_instance.test_detect_mime_type("image.unknown")).to eq("image/png")
      end
    end

    describe "#extract_caption_from_text" do
      it "extracts first sentence as caption" do
        text = "This is the caption. More text follows here."
        result = execution_instance.test_extract_caption_from_text(text)

        expect(result).to eq("This is the caption")
      end

      it "truncates long captions" do
        long_text = "A" * 300 + ". More text."
        result = execution_instance.test_extract_caption_from_text(long_text)

        expect(result.length).to be <= 200
      end
    end

    describe "#extract_tags_from_text" do
      it "extracts tags from bullet points" do
        text = "- tag1\n- tag2\n- tag3"
        result = execution_instance.test_extract_tags_from_text(text)

        expect(result).to include("tag1", "tag2", "tag3")
      end

      it "extracts tags from 'tags:' label" do
        text = "Tags: apple, banana, cherry"
        result = execution_instance.test_extract_tags_from_text(text)

        expect(result).to include("apple", "banana", "cherry")
      end
    end

    describe "#cache_key_components" do
      it "includes required components" do
        components = execution_instance.test_cache_key_components

        expect(components).to include("image_analyzer")
        expect(components).to include("ExecutionTestAnalyzer")
        expect(components).to include("gpt-4o")
      end
    end
  end
end
