# frozen_string_literal: true

require "rails_helper"
require "generators/ruby_llm_agents/install_generator"

RSpec.describe RubyLlmAgents::InstallGenerator, type: :generator do
  describe "default invocation" do
    before { run_generator }

    it "creates the migration file" do
      migration_files = Dir[file("db/migrate/*_create_ruby_llm_agents_executions.rb")]
      expect(migration_files).not_to be_empty
    end

    it "creates the initializer" do
      expect(file_exists?("config/initializers/ruby_llm_agents.rb")).to be true
    end

    it "creates the agents directory" do
      expect(directory_exists?("app/agents")).to be true
    end

    it "creates the agents/concerns directory" do
      expect(directory_exists?("app/agents/concerns")).to be true
    end

    it "creates application_agent.rb in agents" do
      expect(file_exists?("app/agents/application_agent.rb")).to be true
    end

    it "creates the tools directory" do
      expect(directory_exists?("app/tools")).to be true
    end

    it "mounts the dashboard engine in routes" do
      routes_content = file_content("config/routes.rb")
      expect(routes_content).to include('mount RubyLLM::Agents::Engine => "/agents"')
    end
  end

  describe "initializer content" do
    before { run_generator }

    it "contains RubyLLM::Agents.configure block" do
      content = file_content("config/initializers/ruby_llm_agents.rb")
      expect(content).to include("RubyLLM::Agents.configure do |config|")
    end

    it "contains model defaults section" do
      content = file_content("config/initializers/ruby_llm_agents.rb")
      expect(content).to include("Model Defaults")
      expect(content).to include("config.default_model")
    end

    it "contains dashboard authentication section" do
      content = file_content("config/initializers/ruby_llm_agents.rb")
      expect(content).to include("Dashboard Authentication")
      expect(content).to include("config.basic_auth_username")
    end
  end

  describe "application_agent.rb content" do
    before { run_generator }

    it "inherits from RubyLLM::Agents::Base" do
      content = file_content("app/agents/application_agent.rb")
      expect(content).to include("class ApplicationAgent < RubyLLM::Agents::Base")
    end

    it "includes usage examples" do
      content = file_content("app/agents/application_agent.rb")
      expect(content).to include("MyAgent.call")
    end
  end

  describe "skill files" do
    before { run_generator }

    it "creates AGENTS.md skill file" do
      expect(file_exists?("app/agents/AGENTS.md")).to be true
    end

    it "creates TOOLS.md skill file" do
      expect(file_exists?("app/tools/TOOLS.md")).to be true
    end
  end

  describe "--skip-migration option" do
    before { run_generator ["--skip-migration"] }

    it "does not create migration file" do
      migration_files = Dir[file("db/migrate/*_create_ruby_llm_agents_executions.rb")]
      expect(migration_files).to be_empty
    end

    it "still creates other files" do
      expect(file_exists?("config/initializers/ruby_llm_agents.rb")).to be true
      expect(file_exists?("app/agents/application_agent.rb")).to be true
    end
  end

  describe "--skip-initializer option" do
    before { run_generator ["--skip-initializer"] }

    it "does not create initializer" do
      expect(file_exists?("config/initializers/ruby_llm_agents.rb")).to be false
    end

    it "still creates other files" do
      migration_files = Dir[file("db/migrate/*_create_ruby_llm_agents_executions.rb")]
      expect(migration_files).not_to be_empty
      expect(file_exists?("app/agents/application_agent.rb")).to be true
    end
  end

  describe "--no-mount-dashboard option" do
    before { run_generator ["--no-mount-dashboard"] }

    it "does not mount the engine in routes" do
      routes_content = file_content("config/routes.rb")
      expect(routes_content).not_to include("RubyLLM::Agents::Engine")
    end

    it "still creates other files" do
      expect(file_exists?("config/initializers/ruby_llm_agents.rb")).to be true
      expect(file_exists?("app/agents/application_agent.rb")).to be true
    end
  end

  describe "combined options" do
    before { run_generator ["--skip-migration", "--skip-initializer", "--no-mount-dashboard"] }

    it "skips all optional files but still creates directory structure" do
      migration_files = Dir[file("db/migrate/*_create_ruby_llm_agents_executions.rb")]
      expect(migration_files).to be_empty
      expect(file_exists?("config/initializers/ruby_llm_agents.rb")).to be false

      routes_content = file_content("config/routes.rb")
      expect(routes_content).not_to include("RubyLLM::Agents::Engine")

      expect(directory_exists?("app/agents")).to be true
      expect(file_exists?("app/agents/application_agent.rb")).to be true
    end
  end
end
