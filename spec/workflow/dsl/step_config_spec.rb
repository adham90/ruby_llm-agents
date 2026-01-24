# frozen_string_literal: true

require "rails_helper"

RSpec.describe RubyLLM::Agents::Workflow::DSL::StepConfig do
  let(:mock_agent) { Class.new(RubyLLM::Agents::Base) }

  describe "#initialize" do
    it "stores the step name" do
      config = described_class.new(name: :process, agent: mock_agent)
      expect(config.name).to eq(:process)
    end

    it "stores the agent class" do
      config = described_class.new(name: :process, agent: mock_agent)
      expect(config.agent).to eq(mock_agent)
    end

    it "stores the description" do
      config = described_class.new(name: :process, agent: mock_agent, description: "Process data")
      expect(config.description).to eq("Process data")
    end

    it "stores options" do
      config = described_class.new(name: :process, agent: mock_agent, options: { timeout: 30 })
      expect(config.timeout).to eq(30)
    end

    it "stores the block" do
      block = proc { :test }
      config = described_class.new(name: :process, block: block)
      expect(config.block).to eq(block)
    end

    it "normalizes desc option to description" do
      config = described_class.new(name: :process, agent: mock_agent, options: { desc: "Short desc" })
      expect(config.description).to eq("Short desc")
    end
  end

  describe "#routing?" do
    it "returns true when on: and block are both present" do
      config = described_class.new(
        name: :route,
        options: { on: -> { :value } },
        block: proc { |r| r.default mock_agent }
      )
      expect(config.routing?).to be true
    end

    it "returns false when only block is present" do
      config = described_class.new(name: :custom, block: proc { :result })
      expect(config.routing?).to be false
    end

    it "returns false when only on: is present" do
      config = described_class.new(name: :step, options: { on: -> { :value } })
      expect(config.routing?).to be false
    end
  end

  describe "#custom_block?" do
    it "returns true when block is present without routing" do
      config = described_class.new(name: :custom, block: proc { :result })
      expect(config.custom_block?).to be true
    end

    it "returns false when block is for routing" do
      config = described_class.new(
        name: :route,
        options: { on: -> { :value } },
        block: proc { |r| r.default mock_agent }
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
      config = described_class.new(name: :step, agent: mock_agent, options: { optional: true })
      expect(config.optional?).to be true
    end

    it "returns false when optional: false" do
      config = described_class.new(name: :step, agent: mock_agent, options: { optional: false })
      expect(config.optional?).to be false
    end

    it "returns false by default" do
      config = described_class.new(name: :step, agent: mock_agent)
      expect(config.optional?).to be false
    end
  end

  describe "#critical?" do
    it "returns true by default" do
      config = described_class.new(name: :step, agent: mock_agent)
      expect(config.critical?).to be true
    end

    it "returns false when critical: false" do
      config = described_class.new(name: :step, agent: mock_agent, options: { critical: false })
      expect(config.critical?).to be false
    end

    it "returns false when optional: true" do
      config = described_class.new(name: :step, agent: mock_agent, options: { optional: true })
      expect(config.critical?).to be false
    end
  end

  describe "#timeout" do
    it "returns the timeout value" do
      config = described_class.new(name: :step, agent: mock_agent, options: { timeout: 30 })
      expect(config.timeout).to eq(30)
    end

    it "returns nil when not set" do
      config = described_class.new(name: :step, agent: mock_agent)
      expect(config.timeout).to be_nil
    end

    it "converts Duration to integer" do
      config = described_class.new(name: :step, agent: mock_agent, options: { timeout: 1.minute })
      expect(config.timeout).to eq(60)
    end
  end

  describe "#retry_config" do
    it "returns default config when retry not set" do
      config = described_class.new(name: :step, agent: mock_agent)
      expect(config.retry_config).to eq({ max: 0, on: [], backoff: :none, delay: 1 })
    end

    it "handles integer retry count" do
      config = described_class.new(name: :step, agent: mock_agent, options: { retry: 3 })
      expect(config.retry_config[:max]).to eq(3)
      expect(config.retry_config[:on]).to eq([StandardError])
    end

    it "handles retry with on: error class" do
      config = described_class.new(name: :step, agent: mock_agent, options: { retry: 3, on: Timeout::Error })
      expect(config.retry_config[:on]).to eq([Timeout::Error])
    end

    it "handles retry with array of error classes" do
      config = described_class.new(name: :step, agent: mock_agent, options: { retry: 3, on: [Timeout::Error, ArgumentError] })
      expect(config.retry_config[:on]).to eq([Timeout::Error, ArgumentError])
    end

    it "handles hash retry config" do
      config = described_class.new(
        name: :step,
        agent: mock_agent,
        options: { retry: { max: 5, backoff: :exponential, delay: 2 } }
      )
      expect(config.retry_config[:max]).to eq(5)
      expect(config.retry_config[:backoff]).to eq(:exponential)
      expect(config.retry_config[:delay]).to eq(2)
    end
  end

  describe "#fallbacks" do
    it "returns empty array when not set" do
      config = described_class.new(name: :step, agent: mock_agent)
      expect(config.fallbacks).to eq([])
    end

    it "wraps single fallback in array" do
      fallback = Class.new(RubyLLM::Agents::Base)
      config = described_class.new(name: :step, agent: mock_agent, options: { fallback: fallback })
      expect(config.fallbacks).to eq([fallback])
    end

    it "keeps array of fallbacks" do
      fallback1 = Class.new(RubyLLM::Agents::Base)
      fallback2 = Class.new(RubyLLM::Agents::Base)
      config = described_class.new(name: :step, agent: mock_agent, options: { fallback: [fallback1, fallback2] })
      expect(config.fallbacks).to eq([fallback1, fallback2])
    end
  end

  describe "#if_condition and #unless_condition" do
    it "returns the if condition" do
      condition = -> { true }
      config = described_class.new(name: :step, agent: mock_agent, options: { if: condition })
      expect(config.if_condition).to eq(condition)
    end

    it "returns the unless condition" do
      condition = :skip?
      config = described_class.new(name: :step, agent: mock_agent, options: { unless: condition })
      expect(config.unless_condition).to eq(:skip?)
    end
  end

  describe "#input_mapper and #pick_fields" do
    it "returns the input mapper" do
      mapper = -> { { foo: :bar } }
      config = described_class.new(name: :step, agent: mock_agent, options: { input: mapper })
      expect(config.input_mapper).to eq(mapper)
    end

    it "returns pick fields" do
      config = described_class.new(name: :step, agent: mock_agent, options: { pick: [:id, :name] })
      expect(config.pick_fields).to eq([:id, :name])
    end

    it "returns pick source" do
      config = described_class.new(name: :step, agent: mock_agent, options: { from: :validate, pick: [:id] })
      expect(config.pick_from).to eq(:validate)
    end
  end

  describe "#should_execute?" do
    let(:workflow) do
      workflow_class = Class.new(RubyLLM::Agents::Workflow)
      workflow_class.new
    end

    before do
      allow(workflow).to receive(:premium?).and_return(true)
      allow(workflow).to receive(:skip?).and_return(false)
    end

    it "returns true when no conditions" do
      config = described_class.new(name: :step, agent: mock_agent)
      expect(config.should_execute?(workflow)).to be true
    end

    it "evaluates symbol if condition" do
      config = described_class.new(name: :step, agent: mock_agent, options: { if: :premium? })
      expect(config.should_execute?(workflow)).to be true
    end

    it "evaluates lambda if condition" do
      config = described_class.new(name: :step, agent: mock_agent, options: { if: -> { true } })
      expect(config.should_execute?(workflow)).to be true
    end

    it "evaluates unless condition" do
      config = described_class.new(name: :step, agent: mock_agent, options: { unless: :skip? })
      expect(config.should_execute?(workflow)).to be true
    end

    it "returns false when if condition fails" do
      config = described_class.new(name: :step, agent: mock_agent, options: { if: -> { false } })
      expect(config.should_execute?(workflow)).to be false
    end

    it "returns false when unless condition is true" do
      allow(workflow).to receive(:skip?).and_return(true)
      config = described_class.new(name: :step, agent: mock_agent, options: { unless: :skip? })
      expect(config.should_execute?(workflow)).to be false
    end
  end

  describe "#to_h" do
    it "serializes the config" do
      config = described_class.new(
        name: :process,
        agent: mock_agent,
        description: "Process data",
        options: { timeout: 30, optional: true, tags: [:important] }
      )

      hash = config.to_h

      expect(hash[:name]).to eq(:process)
      expect(hash[:description]).to eq("Process data")
      expect(hash[:timeout]).to eq(30)
      expect(hash[:optional]).to be true
      expect(hash[:tags]).to eq([:important])
    end
  end
end
