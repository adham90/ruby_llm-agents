# frozen_string_literal: true

RubyLLM::Agents.configure do |config|
  config.async_logging = false # Run synchronously in tests
end
