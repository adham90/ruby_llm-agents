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

    it "creates the llm/agents directory" do
      expect(directory_exists?("app/llm/agents")).to be true
    end

    it "creates application_agent.rb in llm/agents" do
      expect(file_exists?("app/llm/agents/application_agent.rb")).to be true
    end

    it "creates the llm/text/embedders directory" do
      expect(directory_exists?("app/llm/text/embedders")).to be true
    end

    it "creates application_embedder.rb in llm/text/embedders" do
      expect(file_exists?("app/llm/text/embedders/application_embedder.rb")).to be true
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
      content = file_content("app/llm/agents/application_agent.rb")
      expect(content).to include("class ApplicationAgent < RubyLLM::Agents::Base")
    end

    it "uses Llm namespace" do
      content = file_content("app/llm/agents/application_agent.rb")
      expect(content).to include("module Llm")
    end

    it "includes usage examples with namespace" do
      content = file_content("app/llm/agents/application_agent.rb")
      expect(content).to include("Llm::MyAgent")
    end
  end

  describe "application_embedder.rb content" do
    before { run_generator }

    it "inherits from RubyLLM::Agents::Embedder" do
      content = file_content("app/llm/text/embedders/application_embedder.rb")
      expect(content).to include("class ApplicationEmbedder < RubyLLM::Agents::Embedder")
    end

    it "uses Llm::Text namespace" do
      content = file_content("app/llm/text/embedders/application_embedder.rb")
      expect(content).to include("module Llm")
      expect(content).to include("module Text")
    end

    it "includes model configuration example" do
      content = file_content("app/llm/text/embedders/application_embedder.rb")
      expect(content).to include("text-embedding-3-small")
    end
  end

  describe "--root=ai option" do
    before { run_generator ["--root=ai"] }

    it "creates ai/agents directory" do
      expect(directory_exists?("app/ai/agents")).to be true
    end

    it "creates ai/text/embedders directory" do
      expect(directory_exists?("app/ai/text/embedders")).to be true
    end

    it "uses Ai namespace in application_agent.rb" do
      content = file_content("app/ai/agents/application_agent.rb")
      expect(content).to include("module Ai")
      expect(content).to include("Ai::MyAgent")
    end

    it "uses Ai::Text namespace in application_embedder.rb" do
      content = file_content("app/ai/text/embedders/application_embedder.rb")
      expect(content).to include("module Ai")
      expect(content).to include("module Text")
    end
  end

  describe "--root=ruby_llm --namespace=RubyLLMApp option" do
    before { run_generator ["--root=ruby_llm", "--namespace=RubyLLMApp"] }

    it "creates ruby_llm/agents directory" do
      expect(directory_exists?("app/ruby_llm/agents")).to be true
    end

    it "uses custom RubyLLMApp namespace" do
      content = file_content("app/ruby_llm/agents/application_agent.rb")
      expect(content).to include("module RubyLLMApp")
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
      expect(file_exists?("app/llm/agents/application_agent.rb")).to be true
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
      expect(file_exists?("app/llm/agents/application_agent.rb")).to be true
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
      expect(file_exists?("app/llm/agents/application_agent.rb")).to be true
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

      expect(directory_exists?("app/llm/agents")).to be true
      expect(file_exists?("app/llm/agents/application_agent.rb")).to be true
      expect(directory_exists?("app/llm/text/embedders")).to be true
      expect(file_exists?("app/llm/text/embedders/application_embedder.rb")).to be true
    end
  end
end
