# frozen_string_literal: true

require "rails_helper"
require "generators/ruby_llm_agents/workflow_generator"

RSpec.describe RubyLlmAgents::WorkflowGenerator, type: :generator do
  describe "basic workflow generation" do
    before { run_generator ["Content"] }

    it "creates the workflow file" do
      expect(file_exists?("app/agents/content_workflow.rb")).to be true
    end

    it "creates a class that inherits from ApplicationWorkflow" do
      content = file_content("app/agents/content_workflow.rb")
      expect(content).to include("class ContentWorkflow < ApplicationWorkflow")
    end

    it "includes a description" do
      content = file_content("app/agents/content_workflow.rb")
      expect(content).to include('description "Content workflow"')
    end

    it "includes step examples when no steps specified" do
      content = file_content("app/agents/content_workflow.rb")
      expect(content).to include("# step :research")
    end

    it "creates the application_workflow base class" do
      expect(file_exists?("app/agents/application_workflow.rb")).to be true
    end

    it "application_workflow inherits from RubyLLM::Agents::Workflow" do
      content = file_content("app/agents/application_workflow.rb")
      expect(content).to include("class ApplicationWorkflow < RubyLLM::Agents::Workflow")
    end
  end

  describe "--steps option" do
    before { run_generator ["Content", "--steps=research,draft,edit"] }

    it "includes the specified steps" do
      content = file_content("app/agents/content_workflow.rb")
      expect(content).to include("step :research")
      expect(content).to include("step :draft")
      expect(content).to include("step :edit")
    end

    it "adds after: dependencies for sequential steps" do
      content = file_content("app/agents/content_workflow.rb")
      expect(content).to include("after: :research")
      expect(content).to include("after: :draft")
    end

    it "includes flow declaration" do
      content = file_content("app/agents/content_workflow.rb")
      expect(content).to include("flow :research >> :draft >> :edit")
    end

    it "references agent classes" do
      content = file_content("app/agents/content_workflow.rb")
      expect(content).to include("ResearchAgent")
      expect(content).to include("DraftAgent")
      expect(content).to include("EditAgent")
    end
  end

  describe "does not recreate application_workflow if it exists" do
    before do
      FileUtils.mkdir_p(File.join(destination_root, "app/agents"))
      File.write(File.join(destination_root, "app/agents/application_workflow.rb"), "# existing\n")
      run_generator ["Content"]
    end

    it "keeps the existing application_workflow" do
      content = file_content("app/agents/application_workflow.rb")
      expect(content).to eq("# existing\n")
    end
  end
end
