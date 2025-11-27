# frozen_string_literal: true

require "rails_helper"

RSpec.describe RubyLLM::Agents::ExecutionLoggerJob, type: :job do
  include ActiveJob::TestHelper

  let(:execution_data) do
    {
      agent_type: "TestAgent",
      agent_version: "1.0",
      model_id: "gpt-4",
      temperature: 0.5,
      started_at: 1.minute.ago,
      completed_at: Time.current,
      duration_ms: 1500,
      status: "success",
      input_tokens: 100,
      output_tokens: 50,
      total_tokens: 150,
      parameters: { query: "test" },
      response: { content: "response" }
    }
  end

  describe "#perform" do
    it "creates an execution record" do
      expect {
        described_class.new.perform(execution_data)
      }.to change(RubyLLM::Agents::Execution, :count).by(1)
    end

    it "saves execution with correct data" do
      described_class.new.perform(execution_data)
      execution = RubyLLM::Agents::Execution.last

      expect(execution.agent_type).to eq("TestAgent")
      expect(execution.status).to eq("success")
    end

    context "with token data" do
      it "calculates costs" do
        expect_any_instance_of(RubyLLM::Agents::Execution).to receive(:calculate_costs!)

        described_class.new.perform(execution_data)
      end
    end

    context "without token data" do
      let(:execution_data_no_tokens) do
        execution_data.merge(input_tokens: nil, output_tokens: nil)
      end

      it "does not calculate costs" do
        expect_any_instance_of(RubyLLM::Agents::Execution).not_to receive(:calculate_costs!)

        described_class.new.perform(execution_data_no_tokens)
      end
    end
  end

  describe "anomaly detection" do
    context "with high cost execution" do
      let(:expensive_data) do
        execution_data.merge(total_cost: 10.0)
      end

      before do
        RubyLLM::Agents.configuration.anomaly_cost_threshold = 5.0
      end

      it "logs anomaly warning" do
        expect(Rails.logger).to receive(:warn).with(/Execution anomaly detected/)
        described_class.new.perform(expensive_data)
      end
    end

    context "with slow execution" do
      let(:slow_data) do
        execution_data.merge(duration_ms: 15_000)
      end

      before do
        RubyLLM::Agents.configuration.anomaly_duration_threshold = 10_000
      end

      it "logs anomaly warning" do
        expect(Rails.logger).to receive(:warn).with(/Execution anomaly detected/)
        described_class.new.perform(slow_data)
      end
    end

    context "with failed execution" do
      let(:failed_data) do
        execution_data.merge(status: "error", error_class: "StandardError", error_message: "Failed")
      end

      it "logs anomaly warning" do
        expect(Rails.logger).to receive(:warn).with(/Execution anomaly detected/)
        described_class.new.perform(failed_data)
      end
    end
  end

  describe "job configuration" do
    it "uses default queue" do
      expect(described_class.new.queue_name).to eq("default")
    end

    it "is configured for retry" do
      # retry_on creates exception handlers that can be inspected
      expect(described_class.rescue_handlers).to be_present
    end
  end

  describe "async enqueuing" do
    it "can be enqueued" do
      expect {
        described_class.perform_later(execution_data)
      }.to have_enqueued_job(described_class)
    end

    it "enqueues with correct arguments" do
      expect {
        described_class.perform_later(execution_data)
      }.to have_enqueued_job(described_class).with(execution_data)
    end
  end
end
