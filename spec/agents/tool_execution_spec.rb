# frozen_string_literal: true

require "rails_helper"

RSpec.describe RubyLLM::Agents::ToolExecution do
  describe "model" do
    it "has the correct table name" do
      expect(described_class.table_name).to eq("ruby_llm_agents_tool_executions")
    end

    it "belongs to execution" do
      assoc = described_class.reflect_on_association(:execution)
      expect(assoc).to be_present
      expect(assoc.macro).to eq(:belongs_to)
      expect(assoc.class_name).to eq("RubyLLM::Agents::Execution")
    end
  end

  describe "validations" do
    it "requires tool_name" do
      record = described_class.new(tool_name: nil)
      record.valid?
      expect(record.errors[:tool_name]).to include("can't be blank")
    end

    it "requires status" do
      record = described_class.new(status: nil)
      record.valid?
      expect(record.errors[:status]).to include("can't be blank")
    end

    it "validates status inclusion" do
      record = described_class.new(status: "invalid")
      record.valid?
      expect(record.errors[:status]).to be_present
    end

    it "accepts valid statuses" do
      %w[running success error timed_out cancelled].each do |status|
        record = described_class.new(status: status)
        record.valid?
        expect(record.errors[:status]).to be_empty, "Expected '#{status}' to be valid"
      end
    end
  end

  describe "creation with execution" do
    let(:execution) do
      RubyLLM::Agents::Execution.create!(
        agent_type: "TestAgent",
        model_id: "gpt-4o",
        status: "running",
        started_at: Time.current
      )
    end

    it "creates a tool execution record" do
      record = described_class.create!(
        execution: execution,
        tool_name: "bash",
        tool_call_id: "call_123",
        status: "running",
        input: {command: "ls"},
        started_at: Time.current
      )

      expect(record).to be_persisted
      expect(record.execution).to eq(execution)
      expect(record.tool_name).to eq("bash")
      expect(record.tool_call_id).to eq("call_123")
      expect(record.input).to eq({"command" => "ls"})
    end

    it "can be updated with result" do
      record = described_class.create!(
        execution: execution,
        tool_name: "bash",
        status: "running",
        started_at: Time.current
      )

      record.update!(
        status: "success",
        output: "file1.rb\nfile2.rb",
        output_bytes: 22,
        completed_at: Time.current,
        duration_ms: 150
      )

      record.reload
      expect(record.status).to eq("success")
      expect(record.output).to eq("file1.rb\nfile2.rb")
      expect(record.duration_ms).to eq(150)
    end

    it "supports timed_out status" do
      record = described_class.create!(
        execution: execution,
        tool_name: "slow_tool",
        status: "timed_out",
        error_message: "Timed out after 30s",
        started_at: Time.current
      )

      expect(record.status).to eq("timed_out")
      expect(record.error_message).to include("Timed out")
    end

    it "supports error status" do
      record = described_class.create!(
        execution: execution,
        tool_name: "broken_tool",
        status: "error",
        error_message: "Something went wrong",
        started_at: Time.current
      )

      expect(record.status).to eq("error")
      expect(record.error_message).to eq("Something went wrong")
    end
  end

  describe "Execution#tool_executions" do
    let(:execution) do
      RubyLLM::Agents::Execution.create!(
        agent_type: "TestAgent",
        model_id: "gpt-4o",
        status: "running",
        started_at: Time.current
      )
    end

    it "returns associated tool executions" do
      described_class.create!(
        execution: execution, tool_name: "bash", status: "success",
        iteration: 1, started_at: Time.current
      )
      described_class.create!(
        execution: execution, tool_name: "read_file", status: "success",
        iteration: 2, started_at: Time.current
      )

      expect(execution.tool_executions.count).to eq(2)
      expect(execution.tool_executions.pluck(:tool_name)).to contain_exactly("bash", "read_file")
    end

    it "destroys tool executions when execution is destroyed" do
      described_class.create!(
        execution: execution, tool_name: "bash", status: "success",
        started_at: Time.current
      )

      expect { execution.destroy }.to change(described_class, :count).by(-1)
    end
  end
end
