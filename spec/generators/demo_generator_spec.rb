# frozen_string_literal: true

require "rails_helper"
require "generators/ruby_llm_agents/demo_generator"

RSpec.describe RubyLlmAgents::DemoGenerator, type: :generator do
  describe "default invocation" do
    before { run_generator }

    it "creates the hello agent" do
      expect(file_exists?("app/agents/hello_agent.rb")).to be true
    end

    it "creates the smoke test script" do
      expect(file_exists?("bin/smoke_test_agent")).to be true
    end

    it "creates application_agent.rb if missing" do
      expect(file_exists?("app/agents/application_agent.rb")).to be true
    end
  end

  describe "hello agent content" do
    before { run_generator }

    it "inherits from ApplicationAgent" do
      content = file_content("app/agents/hello_agent.rb")
      expect(content).to include("class HelloAgent < ApplicationAgent")
    end

    it "uses modern DSL with system and prompt" do
      content = file_content("app/agents/hello_agent.rb")
      expect(content).to include("system ")
      expect(content).to include("prompt ")
    end

    it "uses {name} placeholder syntax" do
      content = file_content("app/agents/hello_agent.rb")
      expect(content).to include("{name}")
    end
  end

  describe "smoke test content" do
    before { run_generator }

    it "uses HelloAgent.call" do
      content = file_content("bin/smoke_test_agent")
      expect(content).to include("HelloAgent.call")
    end

    it "includes dry_run check" do
      content = file_content("bin/smoke_test_agent")
      expect(content).to include("dry_run: true")
    end

    it "includes error handling with doctor reference" do
      content = file_content("bin/smoke_test_agent")
      expect(content).to include("ruby_llm_agents:doctor")
    end
  end
end
