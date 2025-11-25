# frozen_string_literal: true

module RubyLLM
  module Agents
    class Engine < ::Rails::Engine
      isolate_namespace RubyLLM::Agents

      # Use to_prepare to load classes after autoloading is set up
      # This ensures app/models are available when referenced
      config.to_prepare do
        require_relative "execution_logger_job"
        require_relative "instrumentation"
        require_relative "base"
      end

      # Configure generators
      config.generators do |g|
        g.test_framework :rspec
        g.fixture_replacement :factory_bot
        g.factory_bot dir: "spec/factories"
      end

      # Add app/agents to autoload paths for host app (must be done before initialization)
      initializer "ruby_llm_agents.autoload_agents", before: :set_autoload_paths do |app|
        agents_path = app.root.join("app/agents")
        if agents_path.exist?
          Rails.autoloaders.main.push_dir(agents_path.to_s)
        end
      end
    end
  end
end
