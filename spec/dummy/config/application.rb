# frozen_string_literal: true

require_relative "boot"

require "rails"
require "active_model/railtie"
require "active_record/railtie"
require "action_controller/railtie"
require "action_view/railtie"
require "active_job/railtie"

Bundler.require(*Rails.groups)

require "ruby_llm/agents"

module Dummy
  class Application < Rails::Application
    config.load_defaults Rails::VERSION::STRING.to_f
    config.eager_load = false

    # Don't generate system test files
    config.generators.system_tests = nil
  end
end
