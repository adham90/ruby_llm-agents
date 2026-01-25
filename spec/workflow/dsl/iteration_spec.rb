# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Iteration support" do
  describe "StepConfig iteration methods" do
    describe "#iteration?" do
      it "returns true when each: is present" do
        config = RubyLLM::Agents::Workflow::DSL::StepConfig.new(
          name: :process,
          options: { each: -> { [1, 2, 3] } }
        )
        expect(config.iteration?).to be true
      end

      it "returns false when each: is absent" do
        config = RubyLLM::Agents::Workflow::DSL::StepConfig.new(
          name: :process,
          options: {}
        )
        expect(config.iteration?).to be false
      end
    end

    describe "#each_source" do
      it "returns the each proc" do
        proc = -> { [1, 2, 3] }
        config = RubyLLM::Agents::Workflow::DSL::StepConfig.new(
          name: :process,
          options: { each: proc }
        )
        expect(config.each_source).to eq(proc)
      end
    end

    describe "#iteration_concurrency" do
      it "returns the concurrency value" do
        config = RubyLLM::Agents::Workflow::DSL::StepConfig.new(
          name: :process,
          options: { each: -> { [] }, concurrency: 5 }
        )
        expect(config.iteration_concurrency).to eq(5)
      end

      it "returns nil when not set" do
        config = RubyLLM::Agents::Workflow::DSL::StepConfig.new(
          name: :process,
          options: { each: -> { [] } }
        )
        expect(config.iteration_concurrency).to be_nil
      end
    end

    describe "#iteration_fail_fast?" do
      it "returns true when fail_fast is true" do
        config = RubyLLM::Agents::Workflow::DSL::StepConfig.new(
          name: :process,
          options: { each: -> { [] }, fail_fast: true }
        )
        expect(config.iteration_fail_fast?).to be true
      end

      it "returns false by default" do
        config = RubyLLM::Agents::Workflow::DSL::StepConfig.new(
          name: :process,
          options: { each: -> { [] } }
        )
        expect(config.iteration_fail_fast?).to be false
      end
    end

    describe "#continue_on_error?" do
      it "returns true when continue_on_error is true" do
        config = RubyLLM::Agents::Workflow::DSL::StepConfig.new(
          name: :process,
          options: { each: -> { [] }, continue_on_error: true }
        )
        expect(config.continue_on_error?).to be true
      end

      it "returns false by default" do
        config = RubyLLM::Agents::Workflow::DSL::StepConfig.new(
          name: :process,
          options: { each: -> { [] } }
        )
        expect(config.continue_on_error?).to be false
      end
    end
  end

  describe "IterationResult" do
    let(:item_results) do
      [
        double(content: "result1", error?: false, input_tokens: 10, output_tokens: 5, cached_tokens: 0, input_cost: 0.01, output_cost: 0.005, total_cost: 0.015),
        double(content: "result2", error?: false, input_tokens: 15, output_tokens: 8, cached_tokens: 2, input_cost: 0.02, output_cost: 0.008, total_cost: 0.028),
        double(content: "result3", error?: false, input_tokens: 12, output_tokens: 6, cached_tokens: 1, input_cost: 0.015, output_cost: 0.006, total_cost: 0.021)
      ]
    end

    let(:result) do
      RubyLLM::Agents::Workflow::IterationResult.new(
        step_name: :process_items,
        item_results: item_results,
        errors: {}
      )
    end

    describe "#content" do
      it "returns array of item contents" do
        expect(result.content).to eq(%w[result1 result2 result3])
      end
    end

    describe "#success?" do
      it "returns true when all items succeed and no errors" do
        expect(result.success?).to be true
      end

      it "returns false when there are errors" do
        result_with_errors = RubyLLM::Agents::Workflow::IterationResult.new(
          step_name: :process,
          item_results: item_results,
          errors: { 0 => StandardError.new("failed") }
        )
        expect(result_with_errors.success?).to be false
      end
    end

    describe "#successful_count" do
      it "counts successful items" do
        expect(result.successful_count).to eq(3)
      end
    end

    describe "#failed_count" do
      it "counts failed items" do
        result_with_errors = RubyLLM::Agents::Workflow::IterationResult.new(
          step_name: :process,
          item_results: [double(content: "ok", error?: false)],
          errors: { 1 => StandardError.new("failed") }
        )
        expect(result_with_errors.failed_count).to eq(1)
      end
    end

    describe "#total_count" do
      it "returns total items including errors" do
        expect(result.total_count).to eq(3)
      end
    end

    describe "metric aggregation" do
      it "sums input_tokens across items" do
        expect(result.input_tokens).to eq(37)
      end

      it "sums output_tokens across items" do
        expect(result.output_tokens).to eq(19)
      end

      it "sums total_tokens" do
        expect(result.total_tokens).to eq(56)
      end

      it "sums cached_tokens across items" do
        expect(result.cached_tokens).to eq(3)
      end

      it "sums total_cost across items" do
        expect(result.total_cost).to eq(0.064)
      end
    end

    describe "#to_h" do
      it "includes all result data" do
        hash = result.to_h
        expect(hash[:step_name]).to eq(:process_items)
        expect(hash[:total_count]).to eq(3)
        expect(hash[:successful_count]).to eq(3)
        expect(hash[:failed_count]).to eq(0)
        expect(hash[:success]).to be true
      end
    end

    describe "Enumerable support" do
      it "supports each" do
        contents = []
        result.each { |r| contents << r.content }
        expect(contents).to eq(%w[result1 result2 result3])
      end

      it "supports map" do
        contents = result.map(&:content)
        expect(contents).to eq(%w[result1 result2 result3])
      end

      it "supports index access" do
        expect(result[0].content).to eq("result1")
        expect(result[2].content).to eq("result3")
      end
    end

    describe ".empty" do
      it "creates an empty result" do
        empty = RubyLLM::Agents::Workflow::IterationResult.empty(:process)
        expect(empty.step_name).to eq(:process)
        expect(empty.item_results).to eq([])
        expect(empty.success?).to be true
        expect(empty.total_count).to eq(0)
      end
    end
  end

  describe "IterationExecutor" do
    let(:workflow_class) do
      Class.new(RubyLLM::Agents::Workflow) do
        step :process_items,
             each: -> { input.items } do |item|
          { processed: item, timestamp: Time.current }
        end
      end
    end

    let(:workflow) { workflow_class.new(items: %w[a b c]) }

    it "handles empty collections" do
      empty_workflow = workflow_class.new(items: [])
      result = empty_workflow.call
      expect(result.steps[:process_items]).to be_a(RubyLLM::Agents::Workflow::IterationResult)
      expect(result.steps[:process_items].total_count).to eq(0)
    end
  end

  describe "IterationContext" do
    it "provides access to item and index" do
      workflow = double("workflow", input: OpenStruct.new)
      config = RubyLLM::Agents::Workflow::DSL::StepConfig.new(name: :test)
      previous_result = nil
      item = { data: "test" }
      index = 5

      context = RubyLLM::Agents::Workflow::DSL::IterationContext.new(
        workflow, config, previous_result, item, index
      )

      expect(context.item).to eq(item)
      expect(context.index).to eq(index)
      expect(context.current_item).to eq(item)
      expect(context.current_index).to eq(index)
    end
  end
end
