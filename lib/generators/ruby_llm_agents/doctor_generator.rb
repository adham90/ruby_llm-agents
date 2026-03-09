# frozen_string_literal: true

require "rails/generators"

module RubyLlmAgents
  # Doctor generator — validates that setup is complete and working.
  #
  # Usage:
  #   rails generate ruby_llm_agents:doctor
  #   rails ruby_llm_agents:doctor   (rake task alias)
  #
  # Checks:
  #   1. API keys — at least one provider key is configured
  #   2. Migrations — required tables exist
  #   3. Routes — engine is mounted
  #   4. Background jobs — ActiveJob adapter is configured (not :async/:inline in prod)
  #   5. Agents — at least one agent file exists
  #
  class DoctorGenerator < ::Rails::Generators::Base
    desc "Validate your RubyLLM::Agents setup and print actionable fixes"

    def run_checks
      @pass = 0
      @fail = 0
      @warn = 0

      say ""
      say "RubyLLM::Agents Doctor", :bold
      say "=" * 40

      check_api_keys
      check_migrations
      check_routes
      check_background_jobs
      check_agents

      say ""
      say "=" * 40
      summary = "#{@pass} passed, #{@fail} failed, #{@warn} warnings"
      if @fail > 0
        say "Result: #{summary}", :red
      elsif @warn > 0
        say "Result: #{summary}", :yellow
      else
        say "Result: #{summary} — you're all set!", :green
      end
      say ""
    end

    private

    def check_api_keys
      say ""
      say "API Keys", :bold

      config = RubyLLM::Agents.configuration
      providers = {
        "OpenAI" => -> { config.openai_api_key },
        "Anthropic" => -> { config.anthropic_api_key },
        "Gemini" => -> { config.gemini_api_key },
        "DeepSeek" => -> { config.deepseek_api_key },
        "OpenRouter" => -> { config.openrouter_api_key },
        "Mistral" => -> { config.mistral_api_key }
      }

      configured = providers.select { |_, v| v.call.present? }.keys

      if configured.any?
        configured.each { |name| pass "#{name} API key configured" }
      else
        fail_check "No API keys configured"
        fix "Add to config/initializers/ruby_llm_agents.rb:"
        fix "  config.openai_api_key = ENV[\"OPENAI_API_KEY\"]"
        fix "Then set the environment variable in .env or credentials."
      end
    end

    def check_migrations
      say ""
      say "Database", :bold

      tables = {
        "ruby_llm_agents_executions" => "rails generate ruby_llm_agents:install && rails db:migrate",
        "ruby_llm_agents_execution_details" => "rails generate ruby_llm_agents:upgrade && rails db:migrate"
      }

      tables.each do |table, fix_cmd|
        if table_exists?(table)
          pass "Table #{table} exists"
        else
          fail_check "Table #{table} missing"
          fix fix_cmd
        end
      end
    end

    def check_routes
      say ""
      say "Routes", :bold

      routes_file = File.join(destination_root, "config/routes.rb")
      if File.exist?(routes_file)
        content = File.read(routes_file)
        if content.include?("RubyLLM::Agents::Engine")
          pass "Dashboard engine mounted"
        else
          warn_check "Dashboard engine not mounted in routes"
          fix "Add to config/routes.rb:"
          fix "  mount RubyLLM::Agents::Engine => \"/agents\""
        end
      else
        warn_check "Could not find config/routes.rb"
      end
    end

    def check_background_jobs
      say ""
      say "Background Jobs", :bold

      adapter = ActiveJob::Base.queue_adapter.class.name
      async_logging = RubyLLM::Agents.configuration.async_logging

      if !async_logging
        pass "Async logging disabled (synchronous mode)"
      elsif adapter.include?("Async") || adapter.include?("Inline")
        if Rails.env.production?
          warn_check "ActiveJob adapter is #{adapter} — execution logging may be lost in production"
          fix "Configure a persistent adapter (Sidekiq, GoodJob, SolidQueue, etc.)"
          fix "Or set config.async_logging = false for synchronous logging."
        else
          pass "ActiveJob adapter: #{adapter} (OK for development)"
        end
      else
        pass "ActiveJob adapter: #{adapter}"
      end
    end

    def check_agents
      say ""
      say "Agents", :bold

      agents_dir = File.join(destination_root, "app/agents")
      if Dir.exist?(agents_dir)
        agent_files = Dir.glob(File.join(agents_dir, "**/*_agent.rb"))
          .reject { |f| f.end_with?("application_agent.rb") }

        if agent_files.any?
          pass "Found #{agent_files.size} agent(s)"
        else
          warn_check "No agents found (only application_agent.rb)"
          fix "rails generate ruby_llm_agents:agent HelloWorld query:required"
          fix "Or: rails generate ruby_llm_agents:demo"
        end
      else
        fail_check "app/agents/ directory missing"
        fix "rails generate ruby_llm_agents:install"
      end
    end

    # Helpers

    def table_exists?(name)
      ActiveRecord::Base.connection.table_exists?(name)
    rescue => e
      say "  (Could not check database: #{e.message})", :yellow
      false
    end

    def pass(msg)
      @pass += 1
      say "  #{status_icon(:pass)} #{msg}", :green
    end

    def fail_check(msg)
      @fail += 1
      say "  #{status_icon(:fail)} #{msg}", :red
    end

    def warn_check(msg)
      @warn += 1
      say "  #{status_icon(:warn)} #{msg}", :yellow
    end

    def fix(msg)
      say "    Fix: #{msg}"
    end

    def status_icon(type)
      case type
      when :pass then "OK"
      when :fail then "FAIL"
      when :warn then "WARN"
      end
    end
  end
end
