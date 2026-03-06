# frozen_string_literal: true

require "rails_helper"

RSpec.describe RubyLLM::Agents::ExecutionDetail, type: :model do
  # Use the factory which auto-creates a detail record
  let(:execution) { create(:execution) }

  describe "associations" do
    it "belongs to execution" do
      expect(execution.detail).to be_a(described_class)
      expect(execution.detail.execution).to eq(execution)
    end
  end

  describe "table name" do
    it "uses the correct table" do
      expect(described_class.table_name).to eq("ruby_llm_agents_execution_details")
    end
  end

  describe "storing prompts" do
    it "stores system_prompt" do
      execution.detail.update!(system_prompt: "You are a helpful assistant")
      expect(execution.detail.reload.system_prompt).to eq("You are a helpful assistant")
    end

    it "stores user_prompt" do
      execution.detail.update!(user_prompt: "What is Ruby?")
      expect(execution.detail.reload.user_prompt).to eq("What is Ruby?")
    end

    it "stores assistant_prompt" do
      execution.detail.update!(assistant_prompt: "Let me think...")
      expect(execution.detail.reload.assistant_prompt).to eq("Let me think...")
    end
  end

  describe "storing response" do
    it "stores response as JSON" do
      response_data = {"content" => "Hello!", "model" => "gpt-4"}
      execution.detail.update!(response: response_data)
      expect(execution.detail.reload.response).to eq(response_data)
    end
  end

  describe "storing tool_calls" do
    it "stores tool_calls as JSON array" do
      tool_calls_data = [
        {"id" => "call_1", "name" => "search", "arguments" => {"q" => "test"}}
      ]
      execution.detail.update!(tool_calls: tool_calls_data)
      expect(execution.detail.reload.tool_calls).to eq(tool_calls_data)
    end

    it "defaults to empty array" do
      # The factory creates a detail with tool_calls: []
      expect(execution.detail.tool_calls).to eq([])
    end
  end

  describe "storing attempts" do
    it "stores attempts as JSON array" do
      attempts_data = [
        {"model" => "gpt-4", "status" => "error"},
        {"model" => "gpt-3.5-turbo", "status" => "success"}
      ]
      execution.detail.update!(attempts: attempts_data)
      expect(execution.detail.reload.attempts).to eq(attempts_data)
    end

    it "defaults to empty array" do
      expect(execution.detail.attempts).to eq([])
    end
  end

  describe "storing parameters" do
    it "stores parameters as JSON" do
      params_data = {"query" => "test", "limit" => 10}
      execution.detail.update!(parameters: params_data)
      expect(execution.detail.reload.parameters).to eq(params_data)
    end

    it "defaults to empty hash when not set" do
      # Create an execution without factory detail callback
      raw_execution = RubyLLM::Agents::Execution.create!(
        agent_type: "TestAgent", model_id: "gpt-4", status: "success",
        started_at: 1.minute.ago, completed_at: Time.current
      )
      raw_execution.create_detail!
      expect(raw_execution.detail.parameters).to eq({})
    end
  end

  describe "storing error_message" do
    it "stores error_message as text" do
      execution.detail.update!(error_message: "Something went wrong")
      expect(execution.detail.reload.error_message).to eq("Something went wrong")
    end
  end

  describe "storing fallback_chain" do
    it "stores fallback_chain as JSON" do
      chain = [{"model" => "gpt-4", "error" => "rate limited"}, {"model" => "gpt-3.5-turbo"}]
      execution.detail.update!(fallback_chain: chain)
      expect(execution.detail.reload.fallback_chain).to eq(chain)
    end
  end

  describe "storing routing data" do
    it "stores routed_to" do
      execution.detail.update!(routed_to: "SupportAgent")
      expect(execution.detail.reload.routed_to).to eq("SupportAgent")
    end

    it "stores classification_result" do
      result = {"route" => "support", "confidence" => 0.95}
      execution.detail.update!(classification_result: result)
      expect(execution.detail.reload.classification_result).to eq(result)
    end
  end
end
