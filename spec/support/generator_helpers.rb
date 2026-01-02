# frozen_string_literal: true

require "rails/generators"
require "fileutils"

module GeneratorHelpers
  extend ActiveSupport::Concern
  include FileUtils

  DESTINATION_ROOT = File.expand_path("../../tmp/generators", __dir__)

  included do
    before do
      # Clean and prepare destination directory
      FileUtils.rm_rf(DESTINATION_ROOT)
      FileUtils.mkdir_p(DESTINATION_ROOT)

      # Create a minimal routes.rb for generators that modify routes
      FileUtils.mkdir_p(File.join(DESTINATION_ROOT, "config"))
      File.write(
        File.join(DESTINATION_ROOT, "config/routes.rb"),
        "Rails.application.routes.draw do\nend\n"
      )
    end

    after do
      FileUtils.rm_rf(DESTINATION_ROOT)
    end
  end

  def destination_root
    DESTINATION_ROOT
  end

  # Run a generator with given args
  # Args can include options like "--skip-migration" or "--model=gpt-4"
  def run_generator(args = [])
    args = Array(args)

    # Separate positional args from options
    positional_args = []
    options = {}

    args.each do |arg|
      if arg.start_with?("--no-")
        # Handle --no-foo as foo: false
        key = arg.sub("--no-", "").tr("-", "_").to_sym
        options[key] = false
      elsif arg.start_with?("--")
        if arg.include?("=")
          # Handle --foo=bar
          key, value = arg.sub("--", "").split("=", 2)
          key = key.tr("-", "_").to_sym
          # Try to convert numeric values
          value = value.to_f if value =~ /\A\d+\.?\d*\z/
          options[key] = value
        else
          # Handle --foo as foo: true
          key = arg.sub("--", "").tr("-", "_").to_sym
          options[key] = true
        end
      else
        positional_args << arg
      end
    end

    generator_class = described_class
    generator = generator_class.new(positional_args, options, destination_root: destination_root)
    generator.invoke_all
  end

  # Get path relative to destination root
  def file(path)
    File.join(destination_root, path)
  end

  # Read file content
  def file_content(path)
    File.read(file(path))
  end

  # Check if file exists
  def file_exists?(path)
    File.exist?(file(path))
  end

  # Check if directory exists
  def directory_exists?(path)
    File.directory?(file(path))
  end
end

RSpec.configure do |config|
  config.include GeneratorHelpers, type: :generator
end
