# frozen_string_literal: true

module RubyLLM
  module Agents
    class Speaker
      # ActiveStorage integration for speakers
      #
      # Provides convenience methods for generating audio and directly
      # attaching it to ActiveStorage attachments.
      #
      # @example Attaching to a model
      #   class Article < ApplicationRecord
      #     has_one_attached :narration
      #   end
      #
      #   class ArticleNarrator < RubyLLM::Agents::Speaker
      #     include RubyLLM::Agents::Speaker::ActiveStorageSupport
      #
      #     provider :openai
      #     model 'tts-1-hd'
      #     voice 'nova'
      #   end
      #
      #   article = Article.find(1)
      #   result = ArticleNarrator.speak_and_attach(
      #     text: article.body,
      #     record: article,
      #     attachment_name: :narration
      #   )
      #
      module ActiveStorageSupport
        extend ActiveSupport::Concern

        class_methods do
          # Generate audio and attach it to a record
          #
          # @param text [String] Text to convert to speech
          # @param record [ActiveRecord::Base] The record to attach to
          # @param attachment_name [Symbol] Name of the attachment (e.g., :narration)
          # @param options [Hash] Additional options for generation
          # @return [SpeechResult] The speech result with audio_url set
          def speak_and_attach(text:, record:, attachment_name:, **options)
            result = call(text: text, **options)

            return result unless result.success?

            attach_audio_to_record(result, record, attachment_name, options)

            result
          end

          private

          def attach_audio_to_record(result, record, attachment_name, options)
            attachment = record.public_send(attachment_name)
            filename = options[:filename] || generate_audio_filename(result)

            attachment.attach(
              io: StringIO.new(result.audio),
              filename: filename,
              content_type: result.content_type
            )

            result.audio_key = attachment.blob.key if attachment.respond_to?(:blob) && attachment.blob
            result.audio_url = blob_url(attachment) if attachment.respond_to?(:blob) && attachment.blob
          end

          def blob_url(attachment)
            if attachment.blob.respond_to?(:url)
              attachment.blob.url
            elsif attachment.blob.respond_to?(:service_url)
              attachment.blob.service_url
            end
          rescue => _e
            nil
          end

          def generate_audio_filename(result)
            timestamp = Time.current.to_i
            ext = result.format || :mp3
            "speech_#{timestamp}.#{ext}"
          end
        end
      end
    end
  end
end
