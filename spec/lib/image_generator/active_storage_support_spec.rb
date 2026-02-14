# frozen_string_literal: true

require "rails_helper"

RSpec.describe RubyLLM::Agents::ImageGenerator::ActiveStorageSupport do
  # Create a test generator class that includes the concern
  let(:generator_class) do
    Class.new(RubyLLM::Agents::ImageGenerator) do
      include RubyLLM::Agents::ImageGenerator::ActiveStorageSupport

      model "gpt-image-1"
      size "1024x1024"
    end
  end

  # Mock record with ActiveStorage attachments
  let(:mock_attachment) { double("ActiveStorage::Attached::One") }
  let(:mock_attachments) { double("ActiveStorage::Attached::Many") }
  let(:mock_record) do
    double("Record",
      hero_image: mock_attachment,
      photos: mock_attachments
    )
  end

  # Mock successful image result
  let(:successful_result) do
    mock_result = double("ImageGenerationResult")
    allow(mock_result).to receive(:success?).and_return(true)
    allow(mock_result).to receive(:base64?).and_return(false)
    allow(mock_result).to receive(:url).and_return("https://example.com/image.png")
    allow(mock_result).to receive(:mime_type).and_return("image/png")
    allow(mock_result).to receive(:to_blob).and_return("\x89PNG\r\n")
    mock_result
  end

  let(:base64_result) do
    mock_result = double("ImageGenerationResult")
    allow(mock_result).to receive(:success?).and_return(true)
    allow(mock_result).to receive(:base64?).and_return(true)
    allow(mock_result).to receive(:url).and_return(nil)
    allow(mock_result).to receive(:mime_type).and_return("image/png")
    allow(mock_result).to receive(:to_blob).and_return("\x89PNG\r\n")
    mock_result
  end

  let(:failed_result) do
    mock_result = double("ImageGenerationResult")
    allow(mock_result).to receive(:success?).and_return(false)
    mock_result
  end

  describe ".generate_and_attach" do
    before do
      allow(generator_class).to receive(:call).and_return(successful_result)
    end

    context "with successful URL result" do
      it "calls the generator with prompt" do
        allow(mock_attachment).to receive(:attach)

        # Mock URI and open for URL download
        downloaded_io = StringIO.new("\x89PNG\r\n")
        allow(URI).to receive(:parse).and_return(double(open: downloaded_io))

        expect(generator_class).to receive(:call).with(prompt: "test prompt")

        generator_class.generate_and_attach(
          prompt: "test prompt",
          record: mock_record,
          attachment_name: :hero_image
        )
      end

      it "returns the result" do
        allow(mock_attachment).to receive(:attach)
        downloaded_io = StringIO.new("\x89PNG\r\n")
        allow(URI).to receive(:parse).and_return(double(open: downloaded_io))

        result = generator_class.generate_and_attach(
          prompt: "test prompt",
          record: mock_record,
          attachment_name: :hero_image
        )

        expect(result).to eq(successful_result)
      end

      it "attaches image from URL" do
        downloaded_io = StringIO.new("\x89PNG\r\n")
        allow(URI).to receive(:parse).and_return(double(open: downloaded_io))

        expect(mock_attachment).to receive(:attach).with(
          io: downloaded_io,
          filename: match(/^generated_\d+\.png$/),
          content_type: "image/png"
        )

        generator_class.generate_and_attach(
          prompt: "test prompt",
          record: mock_record,
          attachment_name: :hero_image
        )
      end
    end

    context "with successful base64 result" do
      before do
        allow(generator_class).to receive(:call).and_return(base64_result)
      end

      it "attaches image from base64 data" do
        expect(mock_attachment).to receive(:attach) do |args|
          expect(args[:io]).to be_a(StringIO)
          expect(args[:filename]).to match(/^generated_\d+\.png$/)
          expect(args[:content_type]).to eq("image/png")
        end

        generator_class.generate_and_attach(
          prompt: "test prompt",
          record: mock_record,
          attachment_name: :hero_image
        )
      end
    end

    context "with custom filename" do
      it "uses provided filename" do
        allow(generator_class).to receive(:call).and_return(base64_result)

        expect(mock_attachment).to receive(:attach).with(
          io: instance_of(StringIO),
          filename: "custom_image.png",
          content_type: "image/png"
        )

        generator_class.generate_and_attach(
          prompt: "test prompt",
          record: mock_record,
          attachment_name: :hero_image,
          filename: "custom_image.png"
        )
      end
    end

    context "with failed result" do
      before do
        allow(generator_class).to receive(:call).and_return(failed_result)
      end

      it "returns result unchanged without attaching" do
        expect(mock_attachment).not_to receive(:attach)

        result = generator_class.generate_and_attach(
          prompt: "test prompt",
          record: mock_record,
          attachment_name: :hero_image
        )

        expect(result).to eq(failed_result)
      end
    end
  end

  describe ".generate_and_attach_multiple" do
    let(:mock_image_1) do
      double("Image1",
        data: "base64data1",
        url: "https://example.com/1.png",
        to_blob: "\x89PNG1",
        mime_type: "image/png"
      )
    end

    let(:mock_image_2) do
      double("Image2",
        data: nil,
        url: "https://example.com/2.png",
        to_blob: "\x89PNG2",
        mime_type: "image/png"
      )
    end

    let(:multi_image_result) do
      mock_result = double("MultiImageResult")
      allow(mock_result).to receive(:success?).and_return(true)
      allow(mock_result).to receive(:images).and_return([mock_image_1, mock_image_2])
      mock_result
    end

    before do
      allow(generator_class).to receive(:call).and_return(multi_image_result)
    end

    it "calls generator with count parameter" do
      allow(mock_attachments).to receive(:attach)
      downloaded_io = StringIO.new("\x89PNG\r\n")
      allow(URI).to receive(:parse).and_return(double(open: downloaded_io))

      expect(generator_class).to receive(:call).with(
        prompt: "test prompt",
        count: 3
      )

      generator_class.generate_and_attach_multiple(
        prompt: "test prompt",
        record: mock_record,
        attachment_name: :photos,
        count: 3
      )
    end

    it "attaches multiple images" do
      downloaded_io = StringIO.new("\x89PNG\r\n")
      allow(URI).to receive(:parse).and_return(double(open: downloaded_io))

      expect(mock_attachments).to receive(:attach).twice

      generator_class.generate_and_attach_multiple(
        prompt: "test prompt",
        record: mock_record,
        attachment_name: :photos,
        count: 2
      )
    end

    it "generates indexed filenames" do
      downloaded_io = StringIO.new("\x89PNG\r\n")
      allow(URI).to receive(:parse).and_return(double(open: downloaded_io))

      # First image (base64)
      expect(mock_attachments).to receive(:attach).with(
        io: instance_of(StringIO),
        filename: match(/^generated_\d+_1\.png$/),
        content_type: "image/png"
      )

      # Second image (URL)
      expect(mock_attachments).to receive(:attach).with(
        io: downloaded_io,
        filename: match(/^generated_\d+_2\.png$/),
        content_type: "image/png"
      )

      generator_class.generate_and_attach_multiple(
        prompt: "test prompt",
        record: mock_record,
        attachment_name: :photos,
        count: 2
      )
    end

    context "with failed result" do
      before do
        allow(generator_class).to receive(:call).and_return(failed_result)
      end

      it "returns result unchanged without attaching" do
        expect(mock_attachments).not_to receive(:attach)

        result = generator_class.generate_and_attach_multiple(
          prompt: "test prompt",
          record: mock_record,
          attachment_name: :photos,
          count: 2
        )

        expect(result).to eq(failed_result)
      end
    end
  end

  describe "private .generate_filename" do
    it "generates filename with timestamp" do
      # Access private method through the class
      allow(Time).to receive(:current).and_return(Time.at(1234567890))

      # We can't easily test private methods directly, but we can verify
      # through the public interface that timestamps are used
      allow(generator_class).to receive(:call).and_return(base64_result)
      allow(mock_attachment).to receive(:attach)

      generator_class.generate_and_attach(
        prompt: "test",
        record: mock_record,
        attachment_name: :hero_image
      )

      expect(mock_attachment).to have_received(:attach).with(
        io: anything,
        filename: match(/generated_\d+\.png/),
        content_type: anything
      )
    end
  end
end
