# frozen_string_literal: true

require "rails_helper"

RSpec.describe RubyLLM::Agents::Workflow::DSL::Executor do
  let(:workflow_class) do
    Class.new(RubyLLM::Agents::Workflow) do
      def self.name
        "TestWorkflow"
      end

      def self.step_order
        @step_order ||= []
      end

      def self.step_configs
        @step_configs ||= {}
      end

      def self.input_schema
        nil
      end

      def self.output_schema
        nil
      end

      def self.timeout
        nil
      end

      def self.max_cost
        nil
      end
    end
  end

  let(:mock_agent) do
    Class.new do
      def self.name
        "MockAgent"
      end
    end
  end

  let(:workflow) do
    instance = workflow_class.new
    instance.instance_variable_set(:@step_results, {})

    # Define the execute_agent method on this instance
    instance.define_singleton_method(:execute_agent) do |agent, input, **opts, &block|
      @execute_agent_result || RubyLLM::Agents::Result.new(content: "result", model_id: "test")
    end

    # Define the run_hooks method on this instance
    instance.define_singleton_method(:run_hooks) do |hook_name|
      # No-op for tests
    end

    # Add a way to set custom execute_agent results
    instance.define_singleton_method(:set_execute_agent_result) do |result|
      @execute_agent_result = result
    end

    instance.define_singleton_method(:set_execute_agent_handler) do |handler|
      instance.define_singleton_method(:execute_agent) do |agent, input, **opts, &block|
        handler.call(agent, input, opts)
      end
    end

    instance
  end

  describe "#initialize" do
    it "initializes with workflow" do
      executor = described_class.new(workflow)

      expect(executor.workflow).to eq(workflow)
      expect(executor.results).to eq({})
      expect(executor.errors).to eq({})
      expect(executor.status).to eq("success")
    end
  end

  describe "#execute" do
    context "with no steps" do
      before do
        allow(workflow.class).to receive(:step_order).and_return([])
      end

      it "returns successful result with no content" do
        executor = described_class.new(workflow)
        result = executor.execute

        expect(result).to be_a(RubyLLM::Agents::Workflow::Result)
        expect(result.status).to eq("success")
        expect(result.steps).to eq({})
      end
    end

    context "with input schema validation" do
      let(:schema) do
        double("schema").tap do |s|
          allow(s).to receive(:validate!).and_return({ query: "test" })
        end
      end

      before do
        allow(workflow.class).to receive(:input_schema).and_return(schema)
        allow(workflow.class).to receive(:step_order).and_return([])
        allow(workflow).to receive(:options).and_return({ query: "test" })
      end

      it "validates input against schema" do
        expect(schema).to receive(:validate!).with({ query: "test" })

        executor = described_class.new(workflow)
        executor.execute
      end

      it "sets validated_input on workflow" do
        executor = described_class.new(workflow)
        executor.execute

        validated = workflow.instance_variable_get(:@validated_input)
        expect(validated).to be_present
      end

      it "raises validation error for invalid input" do
        allow(schema).to receive(:validate!).and_raise(
          RubyLLM::Agents::Workflow::DSL::InputSchema::ValidationError.new("Invalid input")
        )

        executor = described_class.new(workflow)

        expect { executor.execute }.to raise_error(
          RubyLLM::Agents::Workflow::DSL::InputSchema::ValidationError
        )
      end
    end

    context "with sequential steps" do
      let(:step_config) do
        RubyLLM::Agents::Workflow::DSL::StepConfig.new(
          name: :step1,
          agent: mock_agent
        )
      end

      before do
        allow(workflow.class).to receive(:step_order).and_return([:step1])
        allow(workflow.class).to receive(:step_configs).and_return({ step1: step_config })
      end

      it "executes steps in order" do
        # This test requires deeper integration with the Workflow class
        # The executor calls workflow.send(:execute_agent, ...) which requires
        # a real workflow instance with properly configured private methods
        skip "Requires integration test setup"
      end

      it "runs before and after hooks" do
        skip "Requires integration test setup"
      end
    end

    context "with parallel group" do
      let(:step1_config) do
        RubyLLM::Agents::Workflow::DSL::StepConfig.new(name: :step1, agent: mock_agent)
      end
      let(:step2_config) do
        RubyLLM::Agents::Workflow::DSL::StepConfig.new(name: :step2, agent: mock_agent)
      end

      let(:parallel_group) do
        RubyLLM::Agents::Workflow::DSL::ParallelGroup.new(name: :parallel, step_names: [:step1, :step2])
      end

      before do
        allow(workflow.class).to receive(:step_order).and_return([parallel_group])
        allow(workflow.class).to receive(:step_configs).and_return({
          step1: step1_config,
          step2: step2_config
        })
      end

      it "executes steps in parallel" do
        skip "Requires integration test setup"
      end
    end

    context "with wait step" do
      let(:wait_config) do
        RubyLLM::Agents::Workflow::DSL::WaitConfig.new(
          type: :delay,
          duration: 0.01
        )
      end

      before do
        allow(workflow.class).to receive(:step_order).and_return([wait_config])
        allow(workflow.class).to receive(:step_configs).and_return({})
      end

      it "executes wait step" do
        executor = described_class.new(workflow)
        result = executor.execute

        expect(result.status).to eq("success")
      end

      it "handles wait timeout with :fail action" do
        wait_config = RubyLLM::Agents::Workflow::DSL::WaitConfig.new(
          type: :until,
          condition: -> { false },
          poll_interval: 0.01,
          timeout: 0.02,
          on_timeout: :fail
        )

        allow(workflow.class).to receive(:step_order).and_return([wait_config])
        allow(workflow).to receive(:instance_exec).and_return(false)

        executor = described_class.new(workflow)
        result = executor.execute

        expect(result.status).to eq("error")
        expect(result.errors[:wait]).to be_present
      end
    end

    context "error handling" do
      let(:step_config) do
        RubyLLM::Agents::Workflow::DSL::StepConfig.new(
          name: :failing_step,
          agent: mock_agent
        )
      end

      before do
        allow(workflow.class).to receive(:step_order).and_return([:failing_step])
        allow(workflow.class).to receive(:step_configs).and_return({ failing_step: step_config })
      end

      it "handles step errors" do
        skip "Requires integration test setup"
      end

      it "halts on critical step failure" do
        skip "Requires integration test setup"
      end
    end

    context "with optional steps" do
      let(:optional_config) do
        RubyLLM::Agents::Workflow::DSL::StepConfig.new(
          name: :optional_step,
          agent: mock_agent,
          options: { optional: true }
        )
      end

      let(:next_config) do
        RubyLLM::Agents::Workflow::DSL::StepConfig.new(
          name: :next_step,
          agent: mock_agent
        )
      end

      before do
        allow(workflow.class).to receive(:step_order).and_return([:optional_step, :next_step])
        allow(workflow.class).to receive(:step_configs).and_return({
          optional_step: optional_config,
          next_step: next_config
        })
      end

      it "continues after optional step failure with partial status" do
        skip "Requires integration test setup"
      end
    end

    context "result building" do
      let(:step_config) do
        RubyLLM::Agents::Workflow::DSL::StepConfig.new(
          name: :step1,
          agent: mock_agent
        )
      end

      before do
        allow(workflow.class).to receive(:step_order).and_return([:step1])
        allow(workflow.class).to receive(:step_configs).and_return({ step1: step_config })
      end

      it "extracts final content from last successful step" do
        skip "Requires integration test setup"
      end

      it "includes timing information" do
        # Use no-step workflow to test timing
        allow(workflow.class).to receive(:step_order).and_return([])

        executor = described_class.new(workflow)
        result = executor.execute

        expect(result.started_at).to be_present
        expect(result.completed_at).to be_present
        expect(result.duration_ms).to be_a(Integer)
      end

      it "includes workflow metadata" do
        # Use no-step workflow to test metadata
        allow(workflow.class).to receive(:step_order).and_return([])

        executor = described_class.new(workflow)
        result = executor.execute

        expect(result.workflow_type).to eq("TestWorkflow")
      end
    end
  end
end

RSpec.describe RubyLLM::Agents::Workflow::DSL::ParallelGroupResult do
  let(:results) do
    {
      step1: RubyLLM::Agents::Result.new(content: "result1", model_id: "test", input_tokens: 10, output_tokens: 20),
      step2: RubyLLM::Agents::Result.new(content: "result2", model_id: "test", input_tokens: 15, output_tokens: 25)
    }
  end

  let(:group_result) { described_class.new(:parallel_group, results) }

  describe "#name" do
    it "returns the group name" do
      expect(group_result.name).to eq(:parallel_group)
    end
  end

  describe "#results" do
    it "returns all results" do
      expect(group_result.results).to eq(results)
    end
  end

  describe "#content" do
    it "returns content from all results" do
      expect(group_result.content).to eq({
        step1: "result1",
        step2: "result2"
      })
    end
  end

  describe "#[]" do
    it "returns individual result" do
      expect(group_result[:step1]).to eq(results[:step1])
    end
  end

  describe "#success?" do
    it "returns true when all results successful" do
      expect(group_result.success?).to be true
    end

    it "returns false when any result has error" do
      error_result = double("error_result", error?: true, content: nil)
      results_with_error = { step1: error_result }
      group = described_class.new(:test, results_with_error)

      expect(group.success?).to be false
    end
  end

  describe "#error?" do
    it "returns opposite of success?" do
      expect(group_result.error?).to be false
    end
  end

  describe "#to_h" do
    it "returns content as hash" do
      expect(group_result.to_h).to eq(group_result.content)
    end
  end

  describe "token aggregation" do
    it "sums input_tokens" do
      expect(group_result.input_tokens).to eq(25)
    end

    it "sums output_tokens" do
      expect(group_result.output_tokens).to eq(45)
    end

    it "calculates total_tokens" do
      expect(group_result.total_tokens).to eq(70)
    end
  end

  describe "method_missing" do
    it "delegates to results" do
      expect(group_result.step1).to eq(results[:step1])
    end

    it "delegates to content" do
      expect(group_result.respond_to?(:step1)).to be true
    end

    it "raises NoMethodError for unknown" do
      expect { group_result.unknown_step }.to raise_error(NoMethodError)
    end
  end
end
