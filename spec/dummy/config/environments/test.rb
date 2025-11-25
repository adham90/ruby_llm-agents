# frozen_string_literal: true

Rails.application.configure do
  config.cache_classes = true
  config.eager_load = false

  # Show full error reports
  config.consider_all_requests_local = true

  # Disable caching
  config.action_controller.perform_caching = false
  config.cache_store = :null_store

  # Raise exceptions instead of rendering exception templates
  config.action_dispatch.show_exceptions = :none

  # Print deprecation notices to stderr
  config.active_support.deprecation = :stderr

  # Raise exceptions for disallowed deprecations
  config.active_support.disallowed_deprecation = :raise

  # Use SQL instead of Active Record's schema dumper for test database
  config.active_record.schema_format = :ruby

  # Disable ActiveJob queuing in tests (run inline)
  config.active_job.queue_adapter = :test
end
