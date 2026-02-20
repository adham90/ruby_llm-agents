# frozen_string_literal: true

require "rails_helper"

RSpec.describe "RubyLLM::Agents Error Classes" do
  describe RubyLLM::Agents::Error do
    it "inherits from StandardError" do
      expect(RubyLLM::Agents::Error.superclass).to eq(StandardError)
    end

    it "can be raised with a message" do
      expect {
        raise RubyLLM::Agents::Error, "test error"
      }.to raise_error(RubyLLM::Agents::Error, "test error")
    end
  end

  describe RubyLLM::Agents::ConfigurationError do
    it "inherits from Error" do
      expect(RubyLLM::Agents::ConfigurationError.superclass).to eq(RubyLLM::Agents::Error)
    end
  end

  describe RubyLLM::Agents::UnsupportedProviderError do
    it "inherits from Error" do
      expect(RubyLLM::Agents::UnsupportedProviderError.superclass).to eq(RubyLLM::Agents::Error)
    end

    it "generates default message with provider" do
      error = RubyLLM::Agents::UnsupportedProviderError.new(provider: :azure)
      expect(error.message).to eq("Provider :azure is not supported for this operation")
    end

    it "stores provider attribute" do
      error = RubyLLM::Agents::UnsupportedProviderError.new(provider: :azure)
      expect(error.provider).to eq(:azure)
    end
  end

  describe RubyLLM::Agents::SpeechApiError do
    it "inherits from Error" do
      expect(RubyLLM::Agents::SpeechApiError.superclass).to eq(RubyLLM::Agents::Error)
    end

    it "generates default message with status" do
      error = RubyLLM::Agents::SpeechApiError.new(status: 429)
      expect(error.message).to eq("Speech API error (status: 429)")
    end

    it "stores status and response_body attributes" do
      error = RubyLLM::Agents::SpeechApiError.new(status: 500, response_body: "Internal Error")
      expect(error.status).to eq(500)
      expect(error.response_body).to eq("Internal Error")
    end
  end
end
