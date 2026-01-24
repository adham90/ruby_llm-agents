# frozen_string_literal: true

require "rails_helper"

RSpec.describe RubyLLM::Agents::Workflow do
  describe "class-level DSL" do
    let(:workflow_class) do
      Class.new(described_class) do
        def self.name
          "TestWorkflow"
        end
      end
    end

    describe ".version" do
      it "sets and returns version" do
        workflow_class.version "2.0"
        expect(workflow_class.version).to eq("2.0")
      end

      it "defaults to 1.0" do
        expect(workflow_class.version).to eq("1.0")
      end
    end

    describe ".timeout" do
      it "sets and returns timeout" do
        workflow_class.timeout 300
        expect(workflow_class.timeout).to eq(300)
      end

      it "converts ActiveSupport::Duration to integer" do
        workflow_class.timeout 5.minutes
        expect(workflow_class.timeout).to eq(300)
      end

      it "returns nil by default" do
        expect(workflow_class.timeout).to be_nil
      end
    end

    describe ".max_cost" do
      it "sets and returns max_cost" do
        workflow_class.max_cost 1.50
        expect(workflow_class.max_cost).to eq(1.50)
      end

      it "converts to float" do
        workflow_class.max_cost "2"
        expect(workflow_class.max_cost).to eq(2.0)
      end

      it "returns nil by default" do
        expect(workflow_class.max_cost).to be_nil
      end
    end

    describe ".description" do
      it "sets and returns description" do
        workflow_class.description "A test workflow"
        expect(workflow_class.description).to eq("A test workflow")
      end

      it "returns nil by default" do
        expect(workflow_class.description).to be_nil
      end
    end
  end

  describe "#initialize" do
    let(:workflow_class) do
      Class.new(described_class) do
        def self.name
          "TestWorkflow"
        end

        def call
          # Implementation not needed for these tests
        end
      end
    end

    it "stores options" do
      workflow = workflow_class.new(input: "test", custom: "value")
      expect(workflow.options[:input]).to eq("test")
      expect(workflow.options[:custom]).to eq("value")
    end

    it "generates unique workflow_id" do
      workflow1 = workflow_class.new
      workflow2 = workflow_class.new

      expect(workflow1.workflow_id).to be_present
      expect(workflow2.workflow_id).to be_present
      expect(workflow1.workflow_id).not_to eq(workflow2.workflow_id)
    end

    it "sets execution_id to nil initially" do
      workflow = workflow_class.new
      expect(workflow.execution_id).to be_nil
    end
  end

  describe "#call" do
    it "raises NotImplementedError for base class" do
      workflow = described_class.new

      expect { workflow.call }.to raise_error(NotImplementedError)
    end
  end

  describe ".call" do
    let(:workflow_class) do
      Class.new(described_class) do
        def self.name
          "TestWorkflow"
        end

        def call
          @options[:input] + " processed"
        end
      end
    end

    it "instantiates and calls workflow" do
      result = workflow_class.call(input: "test")
      expect(result).to eq("test processed")
    end
  end

  describe "cost threshold enforcement" do
    let(:mock_result) { double("Result", total_cost: 0.5) }

    let(:workflow_class) do
      result = mock_result
      Class.new(described_class) do
        max_cost 1.0

        define_method(:call) do
          # Simulate executing agents
          3.times { execute_agent(Class.new, {}, step_name: :step) }
        end

        define_method(:self_result) { result }
      end
    end

    before do
      # Mock execute_agent to return result with cost
      allow_any_instance_of(workflow_class).to receive(:execute_agent) do |workflow, _agent_class, _input, step_name:|
        workflow.instance_variable_set(:@accumulated_cost, workflow.instance_variable_get(:@accumulated_cost) + 0.5)
        workflow.send(:check_cost_threshold!)
        mock_result
      end
    end

    it "raises WorkflowCostExceededError when cost exceeds max_cost" do
      workflow = workflow_class.new

      expect { workflow.call }.to raise_error(RubyLLM::Agents::WorkflowCostExceededError) do |error|
        expect(error.accumulated_cost).to be > 1.0
        expect(error.max_cost).to eq(1.0)
      end
    end
  end

  describe RubyLLM::Agents::WorkflowCostExceededError do
    it "stores accumulated_cost and max_cost" do
      error = described_class.new("Cost exceeded", accumulated_cost: 2.5, max_cost: 1.0)

      expect(error.accumulated_cost).to eq(2.5)
      expect(error.max_cost).to eq(1.0)
      expect(error.message).to eq("Cost exceeded")
    end
  end

  describe "workflow execution metadata" do
    let(:workflow_class) do
      Class.new(described_class) do
        def self.name
          "MetadataTestWorkflow"
        end

        def call
          @metadata_test = {
            workflow_id: workflow_id,
            execution_id: execution_id,
            root_execution_id: root_execution_id
          }
        end

        attr_reader :metadata_test
      end
    end

    it "provides workflow_id during execution" do
      workflow = workflow_class.new
      workflow.call

      expect(workflow.metadata_test[:workflow_id]).to eq(workflow.workflow_id)
    end
  end

  describe "step hooks" do
    let(:workflow_class) do
      Class.new(described_class) do
        def self.name
          "HookTestWorkflow"
        end

        def before_process(context)
          context.merge(preprocessed: true)
        end

        def call
          # Not needed for hook tests
        end
      end
    end

    it "calls before_step hook when defined" do
      workflow = workflow_class.new

      context = { input: "test" }
      result = workflow.send(:before_step, :process, context)

      expect(result[:preprocessed]).to be true
    end

    it "defaults to extract_step_input when no hook defined" do
      workflow = workflow_class.new

      context = { input: { query: "test" } }
      result = workflow.send(:before_step, :unknown_step, context)

      # extract_step_input returns the input when no previous results
      expect(result).to eq({ query: "test" })
    end
  end

  describe "#extract_step_input" do
    let(:workflow_class) do
      Class.new(described_class) do
        def self.name
          "ExtractInputWorkflow"
        end

        def call; end
      end
    end

    it "uses input when no previous results" do
      workflow = workflow_class.new
      context = { input: { query: "test" } }

      result = workflow.send(:extract_step_input, context)

      expect(result).to eq({ query: "test" })
    end

    it "returns input when context only has :input key" do
      workflow = workflow_class.new
      context = { input: { user_query: "hello" } }

      result = workflow.send(:extract_step_input, context)

      expect(result).to eq({ user_query: "hello" })
    end

    it "handles empty input" do
      workflow = workflow_class.new
      context = { input: {} }

      result = workflow.send(:extract_step_input, context)

      expect(result).to eq({})
    end

    it "returns empty hash when input is nil" do
      workflow = workflow_class.new
      context = { input: nil }

      result = workflow.send(:extract_step_input, context)

      # When input is nil, extract_step_input returns {} as fallback
      expect(result).to eq({})
    end
  end

  describe "inheritance" do
    let(:parent_workflow) do
      Class.new(described_class) do
        version "1.0"
        timeout 60
        max_cost 5.0
        description "Parent workflow"
      end
    end

    let(:child_workflow) do
      Class.new(parent_workflow) do
        version "2.0"
        # Override version only
      end
    end

    it "allows overriding parent settings" do
      expect(child_workflow.version).to eq("2.0")
    end

    it "does not inherit parent values for class variables" do
      # Ruby class instance variables are not inherited
      # Child should have its own defaults
      expect(child_workflow.timeout).to be_nil
      expect(child_workflow.max_cost).to be_nil
    end
  end
end
