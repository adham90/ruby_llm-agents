# frozen_string_literal: true

# SimpleCov is configured in rails_helper.rb for full Rails integration tests.
# For standalone tests that don't need Rails, SimpleCov will be started here
# if it hasn't already been started.
unless defined?(SimpleCov) && SimpleCov.running
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
end

require "ruby_llm/agents"

RSpec.configure do |config|
  # Enable flags like --only-failures and --next-failure
  config.example_status_persistence_file_path = ".rspec_status"

  # Disable RSpec exposing methods globally on `Module` and `main`
  config.disable_monkey_patching!

  config.expect_with :rspec do |c|
    c.syntax = :expect
  end
end
