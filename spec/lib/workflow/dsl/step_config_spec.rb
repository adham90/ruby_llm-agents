# frozen_string_literal: true

require "rails_helper"

RSpec.describe RubyLLM::Agents::Workflow::DSL::StepConfig do
  let(:mock_agent) do
    Class.new do
      def self.name
        "MockAgent"
      end
    end
  end

  describe "#initialize" do
    it "creates a step config with name and agent" do
      config = described_class.new(name: :process, agent: mock_agent)
      expect(config.name).to eq(:process)
      expect(config.agent).to eq(mock_agent)
    end

    it "accepts description" do
      config = described_class.new(name: :process, agent: mock_agent, description: "Process data")
      expect(config.description).to eq("Process data")
    end

    it "accepts :desc as alias for description" do
      config = described_class.new(name: :process, agent: mock_agent, options: { desc: "Short desc" })
      expect(config.description).to eq("Short desc")
    end

    it "stores block for routing or custom logic" do
      block = proc { |r| r.when(:type_a, use: TypeAAgent) }
      config = described_class.new(name: :route, block: block)
      expect(config.block).to eq(block)
    end
  end

  describe "#routing?" do
    it "returns true when :on option and block present" do
      config = described_class.new(
        name: :route,
        options: { on: -> { :type_a } },
        block: proc { |r| r.when(:type_a, use: mock_agent) }
      )
      expect(config.routing?).to be true
    end

    it "returns false when only block present" do
      config = described_class.new(name: :custom, block: proc { "result" })
      expect(config.routing?).to be false
    end

    it "returns false when only :on present" do
      config = described_class.new(name: :step, options: { on: -> { :type_a } })
      expect(config.routing?).to be false
    end
  end

  describe "#custom_block?" do
    it "returns true when block present but not routing" do
      config = described_class.new(name: :custom, block: proc { "result" })
      expect(config.custom_block?).to be true
    end

    it "returns false when routing" do
      config = described_class.new(
        name: :route,
        options: { on: -> { :type_a } },
        block: proc { |r| r.when(:type_a, use: mock_agent) }
      )
      expect(config.custom_block?).to be false
    end

    it "returns false when no block" do
      config = described_class.new(name: :step, agent: mock_agent)
      expect(config.custom_block?).to be false
    end
  end

  describe "#optional?" do
    it "returns true when optional: true" do
      config = described_class.new(name: :step, options: { optional: true })
      expect(config.optional?).to be true
    end

    it "returns false by default" do
      config = described_class.new(name: :step)
      expect(config.optional?).to be false
    end
  end

  describe "#critical?" do
    it "returns true by default" do
      config = described_class.new(name: :step)
      expect(config.critical?).to be true
    end

    it "returns false when critical: false" do
      config = described_class.new(name: :step, options: { critical: false })
      expect(config.critical?).to be false
    end

    it "returns false when optional" do
      config = described_class.new(name: :step, options: { optional: true })
      expect(config.critical?).to be false
    end
  end

  describe "#workflow?" do
    let(:workflow_class) do
      Class.new(RubyLLM::Agents::Workflow) do
        def self.name
          "TestWorkflow"
        end
      end
    end

    it "returns true when agent is a Workflow subclass" do
      config = described_class.new(name: :step, agent: workflow_class)
      expect(config.workflow?).to be true
    end

    it "returns false for regular agents" do
      config = described_class.new(name: :step, agent: mock_agent)
      expect(config.workflow?).to be false
    end

    it "returns false when no agent" do
      config = described_class.new(name: :step)
      expect(config.workflow?).to be false
    end
  end

  describe "#iteration?" do
    it "returns true when :each option present" do
      config = described_class.new(name: :step, options: { each: -> { [1, 2, 3] } })
      expect(config.iteration?).to be true
    end

    it "returns false when no :each option" do
      config = described_class.new(name: :step)
      expect(config.iteration?).to be false
    end
  end

  describe "#each_source" do
    it "returns the iteration source proc" do
      source = -> { [1, 2, 3] }
      config = described_class.new(name: :step, options: { each: source })
      expect(config.each_source).to eq(source)
    end
  end

  describe "#iteration_concurrency" do
    it "returns configured concurrency" do
      config = described_class.new(name: :step, options: { concurrency: 5 })
      expect(config.iteration_concurrency).to eq(5)
    end
  end

  describe "#iteration_fail_fast?" do
    it "returns true when fail_fast: true" do
      config = described_class.new(name: :step, options: { fail_fast: true })
      expect(config.iteration_fail_fast?).to be true
    end

    it "returns false by default" do
      config = described_class.new(name: :step)
      expect(config.iteration_fail_fast?).to be false
    end
  end

  describe "#continue_on_error?" do
    it "returns true when continue_on_error: true" do
      config = described_class.new(name: :step, options: { continue_on_error: true })
      expect(config.continue_on_error?).to be true
    end

    it "returns false by default" do
      config = described_class.new(name: :step)
      expect(config.continue_on_error?).to be false
    end
  end

  describe "#timeout" do
    it "returns configured timeout" do
      config = described_class.new(name: :step, options: { timeout: 30 })
      expect(config.timeout).to eq(30)
    end

    it "converts duration to integer" do
      config = described_class.new(name: :step, options: { timeout: 30.5 })
      expect(config.timeout).to eq(30)
    end

    it "returns nil when not configured" do
      config = described_class.new(name: :step)
      expect(config.timeout).to be_nil
    end
  end

  describe "#retry_config" do
    it "accepts integer for retry count" do
      config = described_class.new(name: :step, options: { retry: 3 })
      expect(config.retry_config[:max]).to eq(3)
      expect(config.retry_config[:on]).to eq([StandardError])
    end

    it "accepts hash for full retry config" do
      config = described_class.new(
        name: :step,
        options: {
          retry: {
            max: 5,
            on: [Timeout::Error],
            backoff: :exponential,
            delay: 2
          }
        }
      )
      expect(config.retry_config[:max]).to eq(5)
      expect(config.retry_config[:on]).to eq([Timeout::Error])
      expect(config.retry_config[:backoff]).to eq(:exponential)
      expect(config.retry_config[:delay]).to eq(2)
    end

    it "defaults to no retries" do
      config = described_class.new(name: :step)
      expect(config.retry_config[:max]).to eq(0)
      expect(config.retry_config[:on]).to eq([])
    end
  end

  describe "#fallbacks" do
    let(:fallback_agent) do
      Class.new { def self.name; "FallbackAgent"; end }
    end

    it "returns array of fallback agents" do
      config = described_class.new(name: :step, options: { fallback: [fallback_agent] })
      expect(config.fallbacks).to eq([fallback_agent])
    end

    it "wraps single fallback in array" do
      config = described_class.new(name: :step, options: { fallback: fallback_agent })
      expect(config.fallbacks).to eq([fallback_agent])
    end

    it "returns empty array when no fallbacks" do
      config = described_class.new(name: :step)
      expect(config.fallbacks).to eq([])
    end
  end

  describe "#if_condition and #unless_condition" do
    it "returns configured if condition" do
      config = described_class.new(name: :step, options: { if: :should_run? })
      expect(config.if_condition).to eq(:should_run?)
    end

    it "returns configured unless condition" do
      config = described_class.new(name: :step, options: { unless: :skip? })
      expect(config.unless_condition).to eq(:skip?)
    end
  end

  describe "#input_mapper" do
    it "returns configured input lambda" do
      mapper = -> { { query: "test" } }
      config = described_class.new(name: :step, options: { input: mapper })
      expect(config.input_mapper).to eq(mapper)
    end
  end

  describe "#pick_fields and #pick_from" do
    it "returns pick configuration" do
      config = described_class.new(name: :step, options: { pick: [:name, :email], from: :user_step })
      expect(config.pick_fields).to eq([:name, :email])
      expect(config.pick_from).to eq(:user_step)
    end
  end

  describe "#default_value" do
    it "returns configured default" do
      config = described_class.new(name: :step, options: { default: "fallback value" })
      expect(config.default_value).to eq("fallback value")
    end
  end

  describe "#error_handler" do
    it "returns symbol error handler" do
      config = described_class.new(name: :step, options: { on_error: :handle_error })
      expect(config.error_handler).to eq(:handle_error)
    end

    it "returns proc error handler" do
      handler = ->(e) { puts e.message }
      config = described_class.new(name: :step, options: { on_error: handler })
      expect(config.error_handler).to eq(handler)
    end
  end

  describe "#throttle and #rate_limit" do
    it "returns configured throttle" do
      config = described_class.new(name: :step, options: { throttle: 5.0 })
      expect(config.throttle).to eq(5.0)
      expect(config.throttled?).to be true
    end

    it "returns configured rate_limit" do
      config = described_class.new(name: :step, options: { rate_limit: { calls: 10, per: 60 } })
      expect(config.rate_limit).to eq({ calls: 10, per: 60 })
      expect(config.throttled?).to be true
    end

    it "#throttled? returns false when not configured" do
      config = described_class.new(name: :step)
      expect(config.throttled?).to be false
    end
  end

  describe "#ui_label and #tags" do
    it "returns configured ui_label" do
      config = described_class.new(name: :step, options: { ui_label: "Processing..." })
      expect(config.ui_label).to eq("Processing...")
    end

    it "returns configured tags" do
      config = described_class.new(name: :step, options: { tags: [:critical, :payment] })
      expect(config.tags).to eq([:critical, :payment])
    end

    it "wraps single tag in array" do
      config = described_class.new(name: :step, options: { tags: :important })
      expect(config.tags).to eq([:important])
    end
  end

  describe "#should_execute?" do
    let(:workflow) do
      double("workflow").tap do |w|
        allow(w).to receive(:should_run?).and_return(true)
        allow(w).to receive(:skip?).and_return(false)
      end
    end

    it "returns true when no conditions" do
      config = described_class.new(name: :step)
      expect(config.should_execute?(workflow)).to be true
    end

    it "evaluates if condition" do
      config = described_class.new(name: :step, options: { if: :should_run? })
      expect(config.should_execute?(workflow)).to be true

      allow(workflow).to receive(:should_run?).and_return(false)
      expect(config.should_execute?(workflow)).to be false
    end

    it "evaluates unless condition" do
      config = described_class.new(name: :step, options: { unless: :skip? })
      expect(config.should_execute?(workflow)).to be true

      allow(workflow).to receive(:skip?).and_return(true)
      expect(config.should_execute?(workflow)).to be false
    end

    it "evaluates proc conditions" do
      config = described_class.new(name: :step, options: { if: -> { true } })
      allow(workflow).to receive(:instance_exec).and_return(true)
      expect(config.should_execute?(workflow)).to be true
    end
  end

  describe "#resolve_input" do
    let(:workflow) do
      double("workflow").tap do |w|
        allow(w).to receive(:input).and_return(OpenStruct.new(user_id: 1))
        allow(w).to receive(:instance_exec).and_return({ query: "custom" })
        allow(w).to receive(:step_result).and_return(double(content: { name: "John", email: "john@example.com" }))
      end
    end

    let(:previous_result) { double("result", content: { data: "value" }) }

    it "uses input_mapper when provided" do
      mapper = -> { { query: "custom" } }
      config = described_class.new(name: :step, options: { input: mapper })

      result = config.resolve_input(workflow, previous_result)
      expect(result).to eq({ query: "custom" })
    end

    it "uses pick_fields when provided" do
      config = described_class.new(name: :step, options: { pick: [:name, :email], from: :user_step })
      allow(workflow).to receive(:step_result).with(:user_step).and_return(
        double(content: { name: "John", email: "john@example.com", age: 30 })
      )

      result = config.resolve_input(workflow, previous_result)
      expect(result).to eq({ name: "John", email: "john@example.com" })
    end

    it "merges original input with previous result by default" do
      config = described_class.new(name: :step)
      allow(workflow).to receive(:input).and_return(double(to_h: { user_id: 1 }))

      result = config.resolve_input(workflow, previous_result)
      expect(result).to include(user_id: 1, data: "value")
    end
  end

  describe "#to_h" do
    it "returns hash representation" do
      config = described_class.new(
        name: :process,
        agent: mock_agent,
        description: "Process data",
        options: {
          timeout: 30,
          optional: true,
          tags: [:important]
        }
      )

      hash = config.to_h

      expect(hash[:name]).to eq(:process)
      expect(hash[:agent]).to eq("MockAgent")
      expect(hash[:description]).to eq("Process data")
      expect(hash[:timeout]).to eq(30)
      expect(hash[:optional]).to be true
      expect(hash[:critical]).to be false
      expect(hash[:tags]).to eq([:important])
    end
  end
end
