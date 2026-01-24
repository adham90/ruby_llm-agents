# frozen_string_literal: true

require_relative "boot"

require "rails"
require "active_model/railtie"
require "active_record/railtie"
require "action_controller/railtie"
require "action_view/railtie"
require "active_job/railtie"
require "action_cable/engine"
require "action_mailer/railtie"

Bundler.require(*Rails.groups)

require "ruby_llm/agents"

module Dummy
  class Application < Rails::Application
    config.load_defaults Rails::VERSION::STRING.to_f
    config.eager_load = false

    # Don't generate system test files
    config.generators.system_tests = nil

    # Configure Active Record Encryption for testing
    # These are deterministic test keys - NOT for production use
    config.active_record.encryption.primary_key = "test-primary-key-that-is-at-least-32-bytes-long"
    config.active_record.encryption.deterministic_key = "test-deterministic-key-32-bytes!"
    config.active_record.encryption.key_derivation_salt = "test-key-derivation-salt-value!"
  end
end
