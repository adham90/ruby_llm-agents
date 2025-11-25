# frozen_string_literal: true

require_relative "agents/version"
require_relative "agents/configuration"
require_relative "agents/inflections" if defined?(Rails)
require_relative "agents/engine" if defined?(Rails::Engine)

module RubyLLM
  module Agents
    class Error < StandardError; end

    class << self
      def configuration
        @configuration ||= Configuration.new
      end

      def configure
        yield(configuration)
      end

      def reset_configuration!
        @configuration = Configuration.new
      end
    end
  end
end
