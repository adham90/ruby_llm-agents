# frozen_string_literal: true

# Start SimpleCov FIRST, before any code is loaded
require "simplecov"

SimpleCov.start do
  # Track only the main library code
  track_files "lib/**/*.rb"

  # Exclude test, vendor, and config files
  add_filter "/spec/"
  add_filter "/vendor/"
  add_filter "/db/"

  # Group by functional areas
  add_group "Core Library", "lib/ruby_llm/agents/core"
  add_group "Pipeline", "lib/ruby_llm/agents/pipeline"
  add_group "Infrastructure", "lib/ruby_llm/agents/infrastructure"
  add_group "Workflow", "lib/ruby_llm/agents/workflow"
  add_group "Image", "lib/ruby_llm/agents/image"
  add_group "Audio", "lib/ruby_llm/agents/audio"
  add_group "Text", "lib/ruby_llm/agents/text"
  add_group "Results", "lib/ruby_llm/agents/results"

  # Enable branch coverage
  enable_coverage :branch

  # Set coverage targets
  minimum_coverage line: 9, branch: 50
  minimum_coverage_by_file line: 0, branch: 0
end

ENV["RAILS_ENV"] = "test"

require_relative "dummy/config/environment"

require "rspec/rails"
require "factory_bot_rails"
require "database_cleaner/active_record"
require "securerandom"

# Register turbo_stream MIME type if not already registered
Mime::Type.register "text/vnd.turbo-stream.html", :turbo_stream unless Mime::Type.lookup_by_extension(:turbo_stream)

# Manually load gem classes that are loaded via config.to_prepare in the engine
# This is needed because RSpec loads spec files before to_prepare callbacks run
require "ruby_llm/agents/infrastructure/execution_logger_job"
require "ruby_llm/agents/core/instrumentation"
require "ruby_llm/agents/core/resolved_config"
require "ruby_llm/agents/core/base"

# Force loading of autoloaded constants that specs reference
# This must happen after Rails.application.initialize! and before specs load
RubyLLM::Agents::Execution

# Load support files
Dir[File.join(__dir__, "support/**/*.rb")].sort.each { |f| require f }

RSpec.configure do |config|
  # Silence deprecation warnings in tests by default
  config.before(:suite) do
    RubyLLM::Agents::Deprecations.silenced = true
  end

  # Include FactoryBot methods
  config.include FactoryBot::Syntax::Methods

  # Tell FactoryBot where to find factories
  FactoryBot.definition_file_paths = [File.join(__dir__, "factories")]
  FactoryBot.find_definitions

  # Use transactional fixtures
  config.use_transactional_fixtures = true

  # Infer spec type from file location
  config.infer_spec_type_from_file_location!

  # Define :migration spec type for spec/migrations/ directory
  config.define_derived_metadata(file_path: %r{spec/migrations/}) do |metadata|
    metadata[:type] = :migration
  end

  # Filter Rails from backtraces
  config.filter_rails_from_backtrace!

  # Database cleaner setup
  config.before(:suite) do
    # Load schema into in-memory database
    ActiveRecord::Schema.verbose = false
    load File.join(__dir__, "dummy/db/schema.rb")

    DatabaseCleaner.strategy = :transaction
    DatabaseCleaner.clean_with(:truncation)
  end

  # Migration tests manage their own schema and need truncation strategy
  config.around(:each, type: :migration) do |example|
    DatabaseCleaner.strategy = :truncation
    DatabaseCleaner.cleaning do
      example.run
    end
    # Restore default strategy after migration tests
    DatabaseCleaner.strategy = :transaction
  end

  config.around(:each, type: ->(v) { v != :migration }) do |example|
    DatabaseCleaner.cleaning do
      example.run
    end
  end

  # After migration tests, reload the schema for other tests
  config.after(:each, type: :migration) do
    # Only reload if there are more tests to run that need the schema
    ActiveRecord::Schema.verbose = false
    load File.join(__dir__, "dummy/db/schema.rb")
  rescue StandardError
    # Ignore errors during schema reload
  end
end
