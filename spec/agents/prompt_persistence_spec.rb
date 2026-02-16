# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Assistant prompt persistence" do
  before do
    RubyLLM::Agents.reset_configuration!
    config = RubyLLM::Agents.configuration
    config.track_executions = true
    config.persist_prompts = true
    config.persist_responses = true
  end

  # Agent with all three prompts (system, user, assistant)
  # Uses Base (not BaseAgent) because Base makes #execute public for the pipeline
  let(:full_prompt_agent_class) do
    Class.new(RubyLLM::Agents::Base) do
      def self.name
        "FullPromptTestAgent"
      end

      model "gpt-4o"

      system "You are a JSON extractor."

      user "Extract data from: {query}"

      assistant "```json"

      param :query, required: true
    end
  end

  # Agent with system and user only, no assistant
  let(:no_assistant_agent_class) do
    Class.new(RubyLLM::Agents::Base) do
      def self.name
        "NoAssistantTestAgent"
      end

      model "gpt-4o"

      system "You are a helpful assistant."

      user "Answer: {question}"

      param :question, required: true
    end
  end

  describe "pipeline execution persists all three prompts" do
    it "stores system_prompt, user_prompt, and assistant_prompt in execution_detail" do
      full_prompt_agent_class.call(query: "test document")

      execution = RubyLLM::Agents::Execution.last
      expect(execution).to be_present
      expect(execution.status).to eq("success")

      detail = execution.detail
      expect(detail).to be_present
      expect(detail.system_prompt).to eq("You are a JSON extractor.")
      expect(detail.user_prompt).to eq("Extract data from: test document")
      expect(detail.assistant_prompt).to eq("```json")
    end

    it "stores nil assistant_prompt when agent has no assistant prefill" do
      no_assistant_agent_class.call(question: "What is Ruby?")

      execution = RubyLLM::Agents::Execution.last
      detail = execution.detail
      expect(detail).to be_present
      expect(detail.system_prompt).to eq("You are a helpful assistant.")
      expect(detail.user_prompt).to eq("Answer: What is Ruby?")
      expect(detail.assistant_prompt).to be_nil
    end
  end

  describe "persist_prompts: false skips all prompt storage" do
    before do
      RubyLLM::Agents.configuration.persist_prompts = false
    end

    it "does not store any prompts in execution_detail" do
      full_prompt_agent_class.call(query: "test data")

      execution = RubyLLM::Agents::Execution.last
      expect(execution).to be_present

      detail = execution.detail
      # Detail may or may not be created, but prompts should be nil/absent
      if detail
        expect(detail.system_prompt).to be_nil
        expect(detail.user_prompt).to be_nil
        expect(detail.assistant_prompt).to be_nil
      end
    end
  end

  describe "assistant_prompt is delegated from Execution" do
    it "delegates assistant_prompt to detail" do
      full_prompt_agent_class.call(query: "delegation test")

      execution = RubyLLM::Agents::Execution.last
      expect(execution.assistant_prompt).to eq("```json")
    end

    it "returns nil when detail is missing" do
      execution = RubyLLM::Agents::Execution.create!(
        agent_type: "TestAgent",
        model_id: "gpt-4o",
        status: "success",
        started_at: Time.current
      )
      expect(execution.assistant_prompt).to be_nil
    end
  end

  describe "cache_key_data includes assistant_prompt" do
    it "includes assistant_prompt in the cache key data" do
      agent = full_prompt_agent_class.new(query: "cache test")
      key_data = agent.cache_key_data

      expect(key_data).to have_key(:assistant_prompt)
      expect(key_data[:assistant_prompt]).to eq("```json")
    end

    it "includes nil assistant_prompt when not defined" do
      agent = no_assistant_agent_class.new(question: "cache test")
      key_data = agent.cache_key_data

      expect(key_data).to have_key(:assistant_prompt)
      expect(key_data[:assistant_prompt]).to be_nil
    end

    it "generates different cache keys for different assistant prompts" do
      agent1 = full_prompt_agent_class.new(query: "same query")

      # Create another agent class with a different assistant prompt
      different_assistant_class = Class.new(RubyLLM::Agents::BaseAgent) do
        def self.name
          "DifferentAssistantAgent"
        end

        model "gpt-4o"
        system "You are a JSON extractor."
        user "Extract data from: {query}"
        assistant '{"result":'
        param :query, required: true
      end

      agent2 = different_assistant_class.new(query: "same query")

      expect(agent1.cache_key_hash).not_to eq(agent2.cache_key_hash)
    end
  end
end
