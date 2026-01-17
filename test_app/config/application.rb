require_relative "boot"

require "rails"
# Pick the frameworks you want:
require "active_model/railtie"
require "active_job/railtie"
require "active_record/railtie"
# require "active_storage/engine"
require "action_controller/railtie"
# require "action_mailer/railtie"
# require "action_mailbox/engine"
# require "action_text/engine"
require "action_view/railtie"
require "action_cable/engine"
# require "rails/test_unit/railtie"

# Require the gems listed in Gemfile, including any gems
# you've limited to :test, :development, or :production.
Bundler.require(*Rails.groups)

module TestApp
  class Application < Rails::Application
    # Initialize configuration defaults for originally generated Rails version.
    config.load_defaults 8.1

    # Configure Active Record Encryption for API keys
    # In production, use Rails credentials or environment variables
    config.active_record.encryption.primary_key = ENV.fetch("RAILS_ENCRYPTION_PRIMARY_KEY", "test-primary-key-that-is-at-least-32-bytes-long")
    config.active_record.encryption.deterministic_key = ENV.fetch("RAILS_ENCRYPTION_DETERMINISTIC_KEY", "test-deterministic-key-32-bytes!")
    config.active_record.encryption.key_derivation_salt = ENV.fetch("RAILS_ENCRYPTION_KEY_DERIVATION_SALT", "test-key-derivation-salt-value!")

    # Please, add to the `ignore` list any other `lib` subdirectories that do
    # not contain `.rb` files, or that should not be reloaded or eager loaded.
    # Common ones are `templates`, `generators`, or `middleware`, for example.
    config.autoload_lib(ignore: %w[assets tasks])

    # Configuration for the application, engines, and railties goes here.
    #
    # These settings can be overridden in specific environments using the files
    # in config/environments, which are processed later.
    #
    # config.time_zone = "Central Time (US & Canada)"
    # config.eager_load_paths << Rails.root.join("extras")

    # Don't generate system test files.
    config.generators.system_tests = nil
  end
end
