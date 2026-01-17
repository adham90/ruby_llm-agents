# frozen_string_literal: true

ENV["RAILS_ENV"] = "test"

require_relative "dummy/config/environment"

require "rspec/rails"
require "factory_bot_rails"
require "database_cleaner/active_record"

# Register turbo_stream MIME type if not already registered
Mime::Type.register "text/vnd.turbo-stream.html", :turbo_stream unless Mime::Type.lookup_by_extension(:turbo_stream)

# Manually load gem classes that are loaded via config.to_prepare in the engine
# This is needed because RSpec loads spec files before to_prepare callbacks run
require "ruby_llm/agents/execution_logger_job"
require "ruby_llm/agents/instrumentation"
require "ruby_llm/agents/resolved_config"
require "ruby_llm/agents/base"

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

  config.around(:each) do |example|
    DatabaseCleaner.cleaning do
      example.run
    end
  end
end
