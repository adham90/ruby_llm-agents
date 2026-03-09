# frozen_string_literal: true

require "rails/generators"

module RubyLlmAgents
  # Demo generator — scaffolds a working HelloAgent with a smoke-test script.
  #
  # Usage:
  #   rails generate ruby_llm_agents:demo
  #
  # Creates:
  #   - app/agents/hello_agent.rb        — minimal working agent
  #   - bin/smoke_test_agent             — one-command verification script
  #
  class DemoGenerator < ::Rails::Generators::Base
    source_root File.expand_path("templates", __dir__)

    def ensure_base_class
      agents_dir = "app/agents"
      empty_directory agents_dir

      base_class_path = "#{agents_dir}/application_agent.rb"
      unless File.exist?(File.join(destination_root, base_class_path))
        template "application_agent.rb.tt", base_class_path
      end
    end

    def create_hello_agent
      create_file "app/agents/hello_agent.rb", <<~RUBY
        # frozen_string_literal: true

        class HelloAgent < ApplicationAgent
          system "You are a friendly assistant. Keep responses under 2 sentences."

          prompt "Say hello to {name} and tell them one fun fact."
        end
      RUBY
    end

    def create_smoke_test
      create_file "bin/smoke_test_agent", <<~RUBY
        #!/usr/bin/env ruby
        # frozen_string_literal: true

        # Smoke test — verifies your RubyLLM::Agents setup end-to-end.
        #
        # Usage:
        #   bin/rails runner bin/smoke_test_agent
        #
        puts "Running RubyLLM::Agents smoke test..."
        puts ""

        # 1. Check configuration
        config = RubyLLM::Agents.configuration
        model = config.default_model
        puts "Default model: \#{model}"

        # 2. Dry-run (no API call)
        puts ""
        puts "Dry run:"
        dry = HelloAgent.call(name: "World", dry_run: true)
        puts "  System prompt: \#{dry.system_prompt[0..80]}..."
        puts "  User prompt:   \#{dry.user_prompt}"
        puts "  Model:         \#{dry.model}"
        puts "  Dry run OK!"

        # 3. Live call
        puts ""
        puts "Live call (calling \#{model})..."
        begin
          result = HelloAgent.call(name: "World")
          puts "  Response: \#{result.content}"
          puts ""
          puts "Success! Your setup is working."
        rescue => e
          puts "  Error: \#{e.class}: \#{e.message}"
          puts ""
          puts "The dry run worked but the live call failed."
          puts "This usually means your API key is missing or invalid."
          puts ""
          puts "Run 'rails ruby_llm_agents:doctor' for detailed diagnostics."
          exit 1
        end
      RUBY

      chmod "bin/smoke_test_agent", 0o755
    end

    def show_next_steps
      say ""
      say "Demo agent created!", :green
      say ""
      say "Try it:"
      say "  bin/rails runner bin/smoke_test_agent"
      say ""
      say "Or in the Rails console:"
      say "  HelloAgent.call(name: \"World\")"
      say "  HelloAgent.call(name: \"World\", dry_run: true)"
      say ""
    end
  end
end
