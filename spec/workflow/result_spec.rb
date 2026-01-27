# frozen_string_literal: true

require "rails_helper"

RSpec.describe RubyLLM::Agents::Workflow::Result do
  let(:mock_step_result) do
    ->(content, cost: 0.001, tokens: 100) do
      RubyLLM::Agents::Result.new(
        content: content,
        input_tokens: tokens,
        output_tokens: tokens / 2,
        total_cost: cost,
        model_id: "gpt-4o"
      )
    end
  end

  describe "initialization" do
    it "creates result with content" do
      result = described_class.new(content: { key: "value" })
      expect(result.content).to eq(key: "value")
    end

    it "sets workflow metadata" do
      result = described_class.new(
        content: "test",
        workflow_type: "TestPipeline",
        workflow_id: "abc-123"
      )
      expect(result.workflow_type).to eq("TestPipeline")
      expect(result.workflow_id).to eq("abc-123")
    end

    it "stores step results" do
      step1 = mock_step_result.call("step1")
      step2 = mock_step_result.call("step2")

      result = described_class.new(
        content: "final",
        steps: { extract: step1, validate: step2 }
      )

      expect(result.steps[:extract].content).to eq("step1")
      expect(result.steps[:validate].content).to eq("step2")
    end

    it "stores branch results" do
      branch1 = mock_step_result.call("branch1")
      branch2 = mock_step_result.call("branch2")

      result = described_class.new(
        content: "final",
        branches: { sentiment: branch1, summary: branch2 }
      )

      expect(result.branches[:sentiment].content).to eq("branch1")
      expect(result.branches[:summary].content).to eq("branch2")
    end

    it "stores routing information" do
      result = described_class.new(
        content: "routed",
        routed_to: :billing,
        classification: { route: :billing, method: "rule" }
      )

      expect(result.routed_to).to eq(:billing)
      expect(result.classification[:route]).to eq(:billing)
    end

    it "sets timing information" do
      started = Time.current
      completed = started + 2.seconds

      result = described_class.new(
        content: "test",
        started_at: started,
        completed_at: completed,
        duration_ms: 2000
      )

      expect(result.started_at).to eq(started)
      expect(result.completed_at).to eq(completed)
      expect(result.duration_ms).to eq(2000)
    end

    it "sets status" do
      result = described_class.new(content: "test", status: "error")
      expect(result.status).to eq("error")
    end

    it "defaults status to success" do
      result = described_class.new(content: "test")
      expect(result.status).to eq("success")
    end

    it "stores error information" do
      result = described_class.new(
        content: nil,
        status: "error",
        error_class: "RuntimeError",
        error_message: "Something went wrong"
      )

      expect(result.error_class).to eq("RuntimeError")
      expect(result.error_message).to eq("Something went wrong")
    end

    it "stores errors hash" do
      error = StandardError.new("Step failed")
      result = described_class.new(
        content: nil,
        errors: { step1: error }
      )

      expect(result.errors[:step1]).to eq(error)
    end
  end

  describe "aggregate metrics" do
    let(:step1) { mock_step_result.call("s1", cost: 0.001, tokens: 100) }
    let(:step2) { mock_step_result.call("s2", cost: 0.002, tokens: 200) }
    let(:step3) { mock_step_result.call("s3", cost: 0.003, tokens: 150) }

    describe "#total_cost" do
      it "sums costs from all steps" do
        result = described_class.new(
          content: "final",
          steps: { a: step1, b: step2, c: step3 }
        )

        expect(result.total_cost).to eq(0.006)
      end

      it "sums costs from all branches" do
        result = described_class.new(
          content: "final",
          branches: { a: step1, b: step2 }
        )

        expect(result.total_cost).to eq(0.003)
      end

      it "includes classifier result in total" do
        classifier = mock_step_result.call("billing", cost: 0.0001)

        result = described_class.new(
          content: "final",
          branches: { billing: step1 },
          classifier_result: classifier
        )

        expect(result.total_cost).to eq(0.0011)
      end
    end

    describe "#total_tokens" do
      it "sums tokens from all steps" do
        result = described_class.new(
          content: "final",
          steps: { a: step1, b: step2 }
        )

        # step1: 100 input + 50 output = 150
        # step2: 200 input + 100 output = 300
        expect(result.total_tokens).to eq(450)
      end
    end

    describe "#input_tokens" do
      it "sums input tokens from all steps" do
        result = described_class.new(
          content: "final",
          steps: { a: step1, b: step2 }
        )

        expect(result.input_tokens).to eq(300) # 100 + 200
      end
    end

    describe "#output_tokens" do
      it "sums output tokens from all steps" do
        result = described_class.new(
          content: "final",
          steps: { a: step1, b: step2 }
        )

        expect(result.output_tokens).to eq(150) # 50 + 100
      end
    end

    describe "#classification_cost" do
      it "returns classifier result cost" do
        classifier = mock_step_result.call("billing", cost: 0.0005)

        result = described_class.new(
          content: "final",
          classifier_result: classifier
        )

        expect(result.classification_cost).to eq(0.0005)
      end

      it "returns 0 when no classifier" do
        result = described_class.new(content: "final")
        expect(result.classification_cost).to eq(0.0)
      end
    end
  end

  describe "status helpers" do
    describe "#success?" do
      it "returns true when status is success" do
        result = described_class.new(content: "test", status: "success")
        expect(result.success?).to be true
      end

      it "returns false when status is not success" do
        result = described_class.new(content: "test", status: "error")
        expect(result.success?).to be false
      end
    end

    describe "#error?" do
      it "returns true when status is error" do
        result = described_class.new(content: nil, status: "error")
        expect(result.error?).to be true
      end

      it "returns false when status is not error" do
        result = described_class.new(content: "test", status: "success")
        expect(result.error?).to be false
      end
    end

    describe "#partial?" do
      it "returns true when status is partial" do
        result = described_class.new(content: "test", status: "partial")
        expect(result.partial?).to be true
      end

      it "returns false when status is not partial" do
        result = described_class.new(content: "test", status: "success")
        expect(result.partial?).to be false
      end
    end
  end

  describe "pipeline helpers" do
    let(:success_result) do
      r = mock_step_result.call("ok")
      allow(r).to receive(:success?).and_return(true)
      allow(r).to receive(:error?).and_return(false)
      r
    end

    let(:error_result) do
      r = mock_step_result.call(nil)
      allow(r).to receive(:success?).and_return(false)
      allow(r).to receive(:error?).and_return(true)
      r
    end

    describe "#all_steps_successful?" do
      it "returns true when all steps succeeded" do
        result = described_class.new(
          content: "final",
          steps: { a: success_result, b: success_result }
        )

        expect(result.all_steps_successful?).to be true
      end

      it "returns false when any step failed" do
        result = described_class.new(
          content: "final",
          steps: { a: success_result, b: error_result }
        )

        expect(result.all_steps_successful?).to be false
      end

      it "returns true when no steps" do
        result = described_class.new(content: "final")
        expect(result.all_steps_successful?).to be true
      end
    end

    describe "#failed_steps" do
      it "returns names of failed steps" do
        result = described_class.new(
          content: "final",
          steps: { a: success_result, b: error_result, c: error_result }
        )

        expect(result.failed_steps).to contain_exactly(:b, :c)
      end

      it "returns empty when all succeeded" do
        result = described_class.new(
          content: "final",
          steps: { a: success_result }
        )

        expect(result.failed_steps).to be_empty
      end
    end
  end

  describe "parallel helpers" do
    let(:success_result) do
      r = mock_step_result.call("ok")
      allow(r).to receive(:success?).and_return(true)
      allow(r).to receive(:error?).and_return(false)
      r
    end

    let(:error_result) do
      r = mock_step_result.call(nil)
      allow(r).to receive(:success?).and_return(false)
      allow(r).to receive(:error?).and_return(true)
      r
    end

    describe "#all_branches_successful?" do
      it "returns true when all branches succeeded" do
        result = described_class.new(
          content: "final",
          branches: { a: success_result, b: success_result }
        )

        expect(result.all_branches_successful?).to be true
      end

      it "returns false when any branch failed" do
        result = described_class.new(
          content: "final",
          branches: { a: success_result, b: error_result }
        )

        expect(result.all_branches_successful?).to be false
      end
    end

    describe "#failed_branches" do
      it "returns names of failed branches" do
        result = described_class.new(
          content: "final",
          branches: { a: success_result, b: error_result }
        )

        expect(result.failed_branches).to include(:b)
      end

      it "includes branches with errors" do
        result = described_class.new(
          content: "final",
          branches: { a: success_result },
          errors: { b: StandardError.new("failed") }
        )

        expect(result.failed_branches).to include(:b)
      end
    end

    describe "#successful_branches" do
      it "returns names of successful branches" do
        result = described_class.new(
          content: "final",
          branches: { a: success_result, b: error_result, c: success_result }
        )

        expect(result.successful_branches).to contain_exactly(:a, :c)
      end
    end
  end

  describe "#to_h" do
    it "serializes all data to hash" do
      step = mock_step_result.call("step")

      result = described_class.new(
        content: { final: "content" },
        workflow_type: "TestPipeline",
        workflow_id: "abc-123",
        steps: { extract: step },
        status: "success",
        duration_ms: 1500
      )

      hash = result.to_h

      expect(hash[:content]).to eq(final: "content")
      expect(hash[:workflow_type]).to eq("TestPipeline")
      expect(hash[:workflow_id]).to eq("abc-123")
      expect(hash[:steps][:extract]).to be_a(Hash)
      expect(hash[:status]).to eq("success")
      expect(hash[:duration_ms]).to eq(1500)
    end
  end

  describe "content delegation" do
    it "delegates [] to content" do
      result = described_class.new(content: { key: "value" })
      expect(result[:key]).to eq("value")
    end

    it "delegates dig to content" do
      result = described_class.new(content: { nested: { deep: "value" } })
      expect(result.dig(:nested, :deep)).to eq("value")
    end

    it "delegates keys to content" do
      result = described_class.new(content: { a: 1, b: 2 })
      expect(result.keys).to eq(%i[a b])
    end

    it "delegates values to content" do
      result = described_class.new(content: { a: 1, b: 2 })
      expect(result.values).to eq([1, 2])
    end

    it "delegates each to content" do
      result = described_class.new(content: { a: 1, b: 2 })
      pairs = []
      result.each { |k, v| pairs << [k, v] }
      expect(pairs).to eq([[:a, 1], [:b, 2]])
    end

    it "delegates map to content" do
      result = described_class.new(content: { a: 1, b: 2 })
      expect(result.map { |k, v| [k, v * 2] }).to eq([[:a, 2], [:b, 4]])
    end
  end

  describe "#skipped_steps" do
    let(:skipped_result) { RubyLLM::Agents::Workflow::SkippedResult.new(:skipped_step) }
    let(:success_result) { mock_step_result.call("ok") }

    it "returns names of skipped steps" do
      result = described_class.new(
        content: "final",
        steps: { a: success_result, b: skipped_result }
      )

      expect(result.skipped_steps).to contain_exactly(:b)
    end

    it "returns empty when no steps skipped" do
      result = described_class.new(
        content: "final",
        steps: { a: success_result }
      )

      expect(result.skipped_steps).to be_empty
    end
  end

  describe "#to_json" do
    it "serializes to JSON" do
      result = described_class.new(
        content: { key: "value" },
        workflow_type: "TestWorkflow",
        status: "success"
      )

      json = result.to_json
      parsed = JSON.parse(json)

      expect(parsed["content"]["key"]).to eq("value")
      expect(parsed["workflow_type"]).to eq("TestWorkflow")
      expect(parsed["status"]).to eq("success")
    end
  end

  describe "to_h with errors" do
    it "transforms errors to hashes" do
      error = StandardError.new("Something failed")
      result = described_class.new(
        content: nil,
        status: "error",
        errors: { step1: error }
      )

      hash = result.to_h
      expect(hash[:errors][:step1][:class]).to eq("StandardError")
      expect(hash[:errors][:step1][:message]).to eq("Something failed")
    end
  end
end

RSpec.describe RubyLLM::Agents::Workflow::SkippedResult do
  describe "initialization" do
    it "creates with step name" do
      result = described_class.new(:validate)
      expect(result.step_name).to eq(:validate)
    end

    it "stores reason" do
      result = described_class.new(:validate, reason: "condition not met")
      expect(result.reason).to eq("condition not met")
    end
  end

  describe "status methods" do
    let(:result) { described_class.new(:step) }

    it "returns nil content" do
      expect(result.content).to be_nil
    end

    it "returns true for success?" do
      expect(result.success?).to be true
    end

    it "returns false for error?" do
      expect(result.error?).to be false
    end

    it "returns true for skipped?" do
      expect(result.skipped?).to be true
    end
  end

  describe "metric methods" do
    let(:result) { described_class.new(:step) }

    it "returns 0 for all token counts" do
      expect(result.input_tokens).to eq(0)
      expect(result.output_tokens).to eq(0)
      expect(result.total_tokens).to eq(0)
      expect(result.cached_tokens).to eq(0)
    end

    it "returns 0.0 for all costs" do
      expect(result.input_cost).to eq(0.0)
      expect(result.output_cost).to eq(0.0)
      expect(result.total_cost).to eq(0.0)
    end
  end

  describe "#to_h" do
    it "serializes to hash" do
      result = described_class.new(:validate, reason: "skipped")
      hash = result.to_h

      expect(hash[:skipped]).to be true
      expect(hash[:step_name]).to eq(:validate)
      expect(hash[:reason]).to eq("skipped")
    end
  end
end
