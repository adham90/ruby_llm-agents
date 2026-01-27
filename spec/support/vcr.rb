# frozen_string_literal: true

require "vcr"
require "webmock/rspec"

VCR.configure do |config|
  config.cassette_library_dir = "spec/cassettes"
  config.hook_into :webmock
  config.configure_rspec_metadata!

  # Allow HTTP connections when no cassette is in use
  # This prevents VCR from blocking requests in tests that don't use cassettes
  config.allow_http_connections_when_no_cassette = true

  # Allow localhost connections for database, etc.
  config.ignore_localhost = true

  # Ignore requests to external services that aren't part of our tests
  config.ignore_request do |request|
    # Ignore LiteLLM pricing data fetches
    request.uri.include?("raw.githubusercontent.com/BerriAI/litellm")
  end

  # Filter sensitive data
  config.filter_sensitive_data("<OPENAI_API_KEY>") { ENV["OPENAI_API_KEY"] }
  config.filter_sensitive_data("<ANTHROPIC_API_KEY>") { ENV["ANTHROPIC_API_KEY"] }
  config.filter_sensitive_data("<GOOGLE_API_KEY>") { ENV["GOOGLE_API_KEY"] }

  # Default cassette options
  config.default_cassette_options = {
    record: :new_episodes,
    match_requests_on: [:method, :uri, :body]
  }
end

# Allow WebMock to be used without VCR for some tests
WebMock.allow_net_connect!(allow_localhost: true)
