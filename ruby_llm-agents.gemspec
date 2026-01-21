# frozen_string_literal: true

require_relative "lib/ruby_llm/agents/core/version"

Gem::Specification.new do |spec|
  spec.name = "ruby_llm-agents"
  spec.version = RubyLLM::Agents::VERSION
  spec.authors = ["adham90"]
  spec.email = ["hi@adham.dev"]

  spec.summary = "Agent framework for building LLM-powered agents with RubyLLM"
  spec.description = "A Rails engine for creating, managing, and monitoring LLM-powered agents. " \
                     "Includes a DSL for agent configuration, execution tracking, cost analytics, " \
                     "and a mountable dashboard UI."
  spec.homepage = "https://github.com/adham90/ruby_llm-agents"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.1.0"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = spec.homepage
  spec.metadata["changelog_uri"] = "#{spec.homepage}/blob/main/CHANGELOG.md"

  # Specify which files should be added to the gem when it is released.
  spec.files = Dir.chdir(__dir__) do
    Dir["{app,config,db,lib}/**/*", "LICENSE.txt", "README.md"]
  end
  spec.require_paths = ["lib"]

  # Runtime dependencies
  spec.add_dependency "rails", ">= 7.0"
  spec.add_dependency "ruby_llm", ">= 1.11.0"
  spec.add_dependency "csv"      # Required for Ruby 3.4+ (no longer bundled)
  spec.add_dependency "ostruct"  # Required for Ruby 4.0+ (no longer bundled)

  # Optional dependencies (not required, but enhance functionality)
  # For async/fiber support: gem 'async', '~> 2.0'

  # Development dependencies are in Gemfile
end
