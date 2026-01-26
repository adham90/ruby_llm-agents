# frozen_string_literal: true

require "rails_helper"

RSpec.describe RubyLLM::Agents::Workflow::DSL::IterationExecutor do
  let(:mock_agent) do
    Class.new do
      def self.name
        "MockAgent"
      end
    end
  end

  let(:workflow) do
    double("workflow").tap do |w|
      allow(w).to receive(:instance_exec) { |&block| block&.call }
      allow(w).to receive(:send)
      allow(w).to receive(:input).and_return(OpenStruct.new(items: [1, 2, 3]))
      allow(w).to receive(:execution_id).and_return("exec-123")
      allow(w).to receive(:workflow_id).and_return("wf-123")
      allow(w).to receive(:class).and_return(double(name: "TestWorkflow"))
      allow(w).to receive(:instance_variable_get).with(:@recursion_depth).and_return(0)
      allow(w).to receive(:instance_variable_get).with(:@accumulated_cost).and_return(0.0)
      allow(w).to receive(:instance_variable_set)
    end
  end

  describe "#execute" do
    context "with empty items" do
      it "returns empty IterationResult" do
        config = RubyLLM::Agents::Workflow::DSL::StepConfig.new(
          name: :process_items,
          agent: mock_agent,
          options: { each: -> { [] } }
        )

        executor = described_class.new(workflow, config, nil)
        result = executor.execute

        expect(result).to be_a(RubyLLM::Agents::Workflow::IterationResult)
        expect(result.item_results).to be_empty
        expect(result.success?).to be true
      end
    end

    context "sequential iteration" do
      it "processes items sequentially" do
        config = RubyLLM::Agents::Workflow::DSL::StepConfig.new(
          name: :process_items,
          agent: mock_agent,
          options: { each: -> { [1, 2, 3] } }
        )

        results = []
        allow(workflow).to receive(:send).with(:execute_agent, mock_agent, anything, anything) do |_, input, _|
          item = input[:item] || input.values.first
          results << item
          RubyLLM::Agents::Result.new(content: "processed #{item}", model_id: "test")
        end

        executor = described_class.new(workflow, config, nil)
        result = executor.execute

        expect(result.item_results.size).to eq(3)
        expect(results).to eq([1, 2, 3])
      end

      it "stops on error with fail_fast" do
        config = RubyLLM::Agents::Workflow::DSL::StepConfig.new(
          name: :process_items,
          agent: mock_agent,
          options: {
            each: -> { [1, 2, 3] },
            fail_fast: true
          }
        )

        processed = []
        allow(workflow).to receive(:send).with(:execute_agent, mock_agent, anything, anything) do |_, input, _|
          item = input[:item] || input.values.first
          processed << item
          raise StandardError, "failed on #{item}" if item == 2
          RubyLLM::Agents::Result.new(content: "processed #{item}", model_id: "test")
        end

        executor = described_class.new(workflow, config, nil)
        result = executor.execute

        expect(processed).to eq([1, 2])
        expect(result.errors).to have_key(1)
      end

      it "continues on error with continue_on_error" do
        config = RubyLLM::Agents::Workflow::DSL::StepConfig.new(
          name: :process_items,
          agent: mock_agent,
          options: {
            each: -> { [1, 2, 3] },
            continue_on_error: true
          }
        )

        allow(workflow).to receive(:send).with(:execute_agent, mock_agent, anything, anything) do |_, input, _|
          item = input[:item] || input.values.first
          raise StandardError, "failed" if item == 2
          RubyLLM::Agents::Result.new(content: "processed #{item}", model_id: "test")
        end

        executor = described_class.new(workflow, config, nil)
        result = executor.execute

        expect(result.item_results.size).to eq(2)
        expect(result.errors).to have_key(1)
      end
    end

    context "parallel iteration" do
      it "processes items in parallel" do
        config = RubyLLM::Agents::Workflow::DSL::StepConfig.new(
          name: :process_items,
          agent: mock_agent,
          options: {
            each: -> { [1, 2, 3] },
            concurrency: 3
          }
        )

        allow(workflow).to receive(:send).with(:execute_agent, mock_agent, anything, anything) do |_, input, _|
          item = input[:item] || input.values.first
          RubyLLM::Agents::Result.new(content: "processed #{item}", model_id: "test")
        end

        executor = described_class.new(workflow, config, nil)
        result = executor.execute

        expect(result.item_results.size).to eq(3)
      end
    end

    context "with custom block" do
      it "executes block for each item" do
        config = RubyLLM::Agents::Workflow::DSL::StepConfig.new(
          name: :process_items,
          options: { each: -> { [1, 2, 3] } },
          block: proc { |item| item * 2 }
        )

        executor = described_class.new(workflow, config, nil)

        # Mock the IterationContext to execute the block
        allow_any_instance_of(RubyLLM::Agents::Workflow::DSL::IterationContext).to receive(:instance_exec) do |ctx, item, &block|
          block.call(item)
        end

        result = executor.execute

        expect(result.item_results.size).to eq(3)
        expect(result.item_results.map(&:content)).to eq([2, 4, 6])
      end
    end

    context "with input mapper" do
      it "uses input mapper to build item input" do
        config = RubyLLM::Agents::Workflow::DSL::StepConfig.new(
          name: :process_items,
          agent: mock_agent,
          options: {
            each: -> { [{ id: 1 }, { id: 2 }] },
            input: -> { { query: item[:id].to_s } }
          }
        )

        captured_inputs = []
        allow(workflow).to receive(:send).with(:execute_agent, mock_agent, anything, anything) do |_, input, _|
          captured_inputs << input
          RubyLLM::Agents::Result.new(content: "result", model_id: "test")
        end

        # Mock the IterationInputContext
        allow_any_instance_of(RubyLLM::Agents::Workflow::DSL::IterationInputContext).to receive(:instance_exec) do |ctx, &block|
          { query: ctx.item[:id].to_s }
        end

        executor = described_class.new(workflow, config, nil)
        executor.execute

        expect(captured_inputs).to all(have_key(:query))
      end
    end

    context "error handling" do
      it "raises IterationSourceError when source resolution fails" do
        config = RubyLLM::Agents::Workflow::DSL::StepConfig.new(
          name: :process_items,
          agent: mock_agent,
          options: { each: -> { raise "source error" } }
        )

        allow(workflow).to receive(:instance_exec).and_raise(StandardError, "source error")

        executor = described_class.new(workflow, config, nil)

        expect { executor.execute }.to raise_error(
          RubyLLM::Agents::Workflow::DSL::IterationSourceError,
          /Failed to resolve iteration source/
        )
      end
    end
  end
end

RSpec.describe RubyLLM::Agents::Workflow::DSL::IterationContext do
  let(:workflow) { double("workflow") }
  let(:config) { RubyLLM::Agents::Workflow::DSL::StepConfig.new(name: :test) }
  let(:previous_result) { double("result", content: "previous") }
  let(:item) { { id: 1, name: "test" } }
  let(:index) { 0 }

  let(:context) { described_class.new(workflow, config, previous_result, item, index) }

  describe "#item and #current_item" do
    it "returns the current item" do
      expect(context.item).to eq(item)
      expect(context.current_item).to eq(item)
    end
  end

  describe "#index and #current_index" do
    it "returns the current index" do
      expect(context.index).to eq(index)
      expect(context.current_index).to eq(index)
    end
  end
end

RSpec.describe RubyLLM::Agents::Workflow::DSL::IterationInputContext do
  let(:workflow) do
    double("workflow").tap do |w|
      allow(w).to receive(:input).and_return(OpenStruct.new(query: "test"))
      allow(w).to receive(:respond_to?).and_return(false)
    end
  end

  let(:item) { { id: 1, name: "test" } }
  let(:index) { 5 }

  let(:context) { described_class.new(workflow, item, index) }

  describe "#item" do
    it "returns the current item" do
      expect(context.item).to eq(item)
    end
  end

  describe "#index" do
    it "returns the current index" do
      expect(context.index).to eq(5)
    end
  end

  describe "#input" do
    it "returns workflow input" do
      expect(context.input.query).to eq("test")
    end
  end

  describe "method delegation" do
    it "delegates to workflow" do
      allow(workflow).to receive(:respond_to?).with(:step_results, true).and_return(true)
      allow(workflow).to receive(:send).with(:step_results).and_return({ step1: "result" })

      expect(context.step_results).to eq({ step1: "result" })
    end
  end
end
