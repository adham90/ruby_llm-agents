# frozen_string_literal: true

# Extends RubyLLM::Configuration with Inception API key support.
# This allows users to configure: config.inception_api_key = ENV['INCEPTION_API_KEY']
module RubyLLM
  class Configuration
    attr_accessor :inception_api_key unless method_defined?(:inception_api_key)
  end
end
