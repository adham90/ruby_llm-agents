# frozen_string_literal: true

RubyLLM.configure do |config|
  config.openai_api_key = "open_ai_config_key"

  # or for Claude:
  # config.anthropic_api_key = ENV['ANTHROPIC_API_KEY']

  # Inception Labs Mercury (diffusion LLM):
  # config.inception_api_key = ENV['INCEPTION_API_KEY']
end
