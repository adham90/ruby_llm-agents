# frozen_string_literal: true

require "rails_helper"
require "generators/ruby_llm_agents/agent_generator"

RSpec.describe RubyLlmAgents::AgentGenerator, type: :generator do
  describe "basic agent generation" do
    before { run_generator ["SearchIntent"] }

    it "creates the agent file with correct name" do
      expect(file_exists?("app/agents/search_intent_agent.rb")).to be true
    end

    it "creates a class that inherits from ApplicationAgent" do
      content = file_content("app/agents/search_intent_agent.rb")
      expect(content).to include("class SearchIntentAgent < ApplicationAgent")
    end

    it "includes default model configuration" do
      content = file_content("app/agents/search_intent_agent.rb")
      expect(content).to include('model "gemini-2.0-flash"')
      expect(content).to include("temperature 0.0")
    end

    it "includes version" do
      content = file_content("app/agents/search_intent_agent.rb")
      expect(content).to include('version "1.0"')
    end

    it "includes prompt methods" do
      content = file_content("app/agents/search_intent_agent.rb")
      expect(content).to include("def system_prompt")
      expect(content).to include("def user_prompt")
    end
  end

  describe "with required parameter" do
    before { run_generator ["SearchIntent", "query:required"] }

    it "creates param with required: true" do
      content = file_content("app/agents/search_intent_agent.rb")
      expect(content).to include("param :query, required: true")
    end

    it "uses the param in user_prompt" do
      content = file_content("app/agents/search_intent_agent.rb")
      # The template uses the first param name in user_prompt
      expect(content).to match(/def user_prompt\s+.*query/m)
    end
  end

  describe "with default value parameter" do
    before { run_generator ["SearchIntent", "limit:10"] }

    it "creates param with default value" do
      content = file_content("app/agents/search_intent_agent.rb")
      expect(content).to include('param :limit, default: "10"')
    end
  end

  describe "with multiple parameters" do
    before { run_generator ["SearchIntent", "query:required", "limit:10", "format"] }

    it "creates all params" do
      content = file_content("app/agents/search_intent_agent.rb")
      expect(content).to include("param :query, required: true")
      expect(content).to include('param :limit, default: "10"')
      expect(content).to include("param :format")
    end
  end

  describe "--model option" do
    before { run_generator ["SearchIntent", "--model=gpt-4o"] }

    it "uses the specified model" do
      content = file_content("app/agents/search_intent_agent.rb")
      expect(content).to include('model "gpt-4o"')
    end
  end

  describe "--temperature option" do
    before { run_generator ["SearchIntent", "--temperature=0.7"] }

    it "uses the specified temperature" do
      content = file_content("app/agents/search_intent_agent.rb")
      expect(content).to include("temperature 0.7")
    end
  end

  describe "--cache option" do
    before { run_generator ["SearchIntent", "--cache=1.hour"] }

    it "includes cache configuration" do
      content = file_content("app/agents/search_intent_agent.rb")
      expect(content).to include("cache 1.hour")
    end
  end

  describe "without --cache option" do
    before { run_generator ["SearchIntent"] }

    it "includes commented cache example" do
      content = file_content("app/agents/search_intent_agent.rb")
      expect(content).to include("# cache 1.hour")
    end
  end

  describe "combined options" do
    before do
      run_generator [
        "ContentGenerator",
        "text:required",
        "max_length:500",
        "--model=claude-3-sonnet",
        "--temperature=0.5",
        "--cache=30.minutes"
      ]
    end

    it "creates the agent file" do
      expect(file_exists?("app/agents/content_generator_agent.rb")).to be true
    end

    it "applies all options correctly" do
      content = file_content("app/agents/content_generator_agent.rb")
      expect(content).to include("class ContentGeneratorAgent < ApplicationAgent")
      expect(content).to include('model "claude-3-sonnet"')
      expect(content).to include("temperature 0.5")
      expect(content).to include("cache 30.minutes")
      expect(content).to include("param :text, required: true")
      expect(content).to include('param :max_length, default: "500"')
    end
  end

  describe "camelCase name handling" do
    before { run_generator ["MyAwesomeAgent"] }

    it "creates file with underscored name" do
      expect(file_exists?("app/agents/my_awesome_agent_agent.rb")).to be true
    end

    it "uses the correct class name" do
      content = file_content("app/agents/my_awesome_agent_agent.rb")
      expect(content).to include("class MyAwesomeAgentAgent < ApplicationAgent")
    end
  end

  describe "snake_case name handling" do
    before { run_generator ["search_intent"] }

    it "creates file with correct name" do
      expect(file_exists?("app/agents/search_intent_agent.rb")).to be true
    end

    it "uses the correct class name" do
      content = file_content("app/agents/search_intent_agent.rb")
      expect(content).to include("class SearchIntentAgent < ApplicationAgent")
    end
  end

end
