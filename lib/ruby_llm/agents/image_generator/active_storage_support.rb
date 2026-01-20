# frozen_string_literal: true

module RubyLLM
  module Agents
    class ImageGenerator
      # ActiveStorage integration for image generators
      #
      # Provides convenience methods for generating images and directly
      # attaching them to ActiveStorage attachments.
      #
      # @example Attaching to a model
      #   class Product < ApplicationRecord
      #     has_one_attached :hero_image
      #   end
      #
      #   class ProductImageGenerator < RubyLLM::Agents::ImageGenerator
      #     include RubyLLM::Agents::ImageGenerator::ActiveStorageSupport
      #
      #     model "gpt-image-1"
      #     size "1024x1024"
      #   end
      #
      #   product = Product.find(1)
      #   result = ProductImageGenerator.generate_and_attach(
      #     prompt: "Professional product photo of a red sneaker",
      #     record: product,
      #     attachment_name: :hero_image
      #   )
      #
      module ActiveStorageSupport
        extend ActiveSupport::Concern

        class_methods do
          # Generate an image and attach it to a record
          #
          # @param prompt [String] The generation prompt
          # @param record [ActiveRecord::Base] The record to attach to
          # @param attachment_name [Symbol] Name of the attachment (e.g., :avatar)
          # @param options [Hash] Additional options for generation
          # @return [ImageGenerationResult] The generation result
          def generate_and_attach(prompt:, record:, attachment_name:, **options)
            result = call(prompt: prompt, **options)

            return result unless result.success?

            attach_result_to_record(result, record, attachment_name, options)

            result
          end

          # Generate multiple images and attach them to a has_many_attached
          #
          # @param prompt [String] The generation prompt
          # @param record [ActiveRecord::Base] The record to attach to
          # @param attachment_name [Symbol] Name of the attachment (e.g., :photos)
          # @param count [Integer] Number of images to generate
          # @param options [Hash] Additional options for generation
          # @return [ImageGenerationResult] The generation result
          def generate_and_attach_multiple(prompt:, record:, attachment_name:, count: 1, **options)
            result = call(prompt: prompt, count: count, **options)

            return result unless result.success?

            attachment = record.public_send(attachment_name)

            result.images.each_with_index do |image, idx|
              attach_image_to_collection(image, attachment, idx, result)
            end

            result
          end

          private

          def attach_result_to_record(result, record, attachment_name, options)
            attachment = record.public_send(attachment_name)
            filename = options[:filename] || generate_filename

            if result.base64?
              attachment.attach(
                io: StringIO.new(result.to_blob),
                filename: filename,
                content_type: result.mime_type || "image/png"
              )
            else
              attach_from_url(attachment, result.url, filename)
            end
          end

          def attach_image_to_collection(image, attachment, index, result)
            filename = generate_filename(index)

            if image.respond_to?(:data) && image.data
              attachment.attach(
                io: StringIO.new(image.to_blob),
                filename: filename,
                content_type: image.mime_type || "image/png"
              )
            elsif image.respond_to?(:url) && image.url
              attach_from_url(attachment, image.url, filename)
            end
          end

          def attach_from_url(attachment, url, filename)
            require "open-uri"

            downloaded = URI.parse(url).open
            attachment.attach(
              io: downloaded,
              filename: filename,
              content_type: "image/png"
            )
          end

          def generate_filename(index = nil)
            timestamp = Time.current.to_i
            if index
              "generated_#{timestamp}_#{index + 1}.png"
            else
              "generated_#{timestamp}.png"
            end
          end
        end
      end
    end
  end
end
