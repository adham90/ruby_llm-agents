# frozen_string_literal: true

module RubyLLM
  module Agents
    # Base error class for RubyLLM::Agents
    class Error < StandardError; end

    # ============================================================
    # Configuration Errors
    # ============================================================

    # Raised for configuration issues
    class ConfigurationError < Error; end

    # ============================================================
    # Speech/Audio Errors
    # ============================================================

    # Raised when a TTS provider is not supported
    class UnsupportedProviderError < Error
      attr_reader :provider

      def initialize(message = nil, provider: nil)
        @provider = provider
        super(message || "Provider :#{provider} is not supported for this operation")
      end
    end

    # Raised when the TTS API returns an error response
    class SpeechApiError < Error
      attr_reader :status, :response_body

      def initialize(message = nil, status: nil, response_body: nil)
        @status = status
        @response_body = response_body
        super(message || "Speech API error (status: #{status})")
      end
    end
  end
end
