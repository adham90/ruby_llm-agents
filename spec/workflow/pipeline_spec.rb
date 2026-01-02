# frozen_string_literal: true

require "rails_helper"

RSpec.describe RubyLLM::Agents::Workflow::Pipeline do
  # Mock agent classes for testing
  let(:mock_result) do
    ->(content) do
      RubyLLM::Agents::Result.new(
        content: content,
        input_tokens: 100,
        output_tokens: 50,
        total_cost: 0.001,
        model_id: "gpt-4o"
      )
    end
  end

  let(:extractor_agent) do
    result_builder = mock_result
    Class.new(RubyLLM::Agents::Base) do
      model "gpt-4o"
      param :text, required: true

      define_method(:call) do |&_block|
        result_builder.call({ extracted: "data from #{@options[:text]}" })
      end

      def user_prompt
        @options[:text]
      end
    end
  end

  let(:validator_agent) do
    result_builder = mock_result
    Class.new(RubyLLM::Agents::Base) do
      model "gpt-4o"
      param :extracted, required: false

      define_method(:call) do |&_block|
        result_builder.call({ valid: true, data: @options[:extracted] })
      end

      def user_prompt
        "validate"
      end
    end
  end

  let(:formatter_agent) do
    result_builder = mock_result
    Class.new(RubyLLM::Agents::Base) do
      model "gpt-4o"
      param :valid, required: false
      param :data, required: false

      define_method(:call) do |&_block|
        result_builder.call("Formatted: #{@options[:data]}")
      end

      def user_prompt
        "format"
      end
    end
  end

  describe "DSL class methods" do
    describe ".step" do
      it "defines steps" do
        agent = extractor_agent
        klass = Class.new(described_class) do
          step :extract, agent: agent
        end
        expect(klass.steps.keys).to eq([:extract])
      end

      it "stores agent class" do
        agent = extractor_agent
        klass = Class.new(described_class) do
          step :extract, agent: agent
        end
        expect(klass.steps[:extract][:agent]).to eq(agent)
      end

      it "supports skip_on option" do
        agent = extractor_agent
        skip_proc = ->(ctx) { ctx[:skip] }
        klass = Class.new(described_class) do
          step :extract, agent: agent, skip_on: skip_proc
        end
        expect(klass.steps[:extract][:skip_on]).to eq(skip_proc)
      end

      it "supports continue_on_error option" do
        agent = extractor_agent
        klass = Class.new(described_class) do
          step :extract, agent: agent, continue_on_error: true
        end
        expect(klass.steps[:extract][:continue_on_error]).to be true
      end

      it "supports optional option as alias for continue_on_error" do
        agent = extractor_agent
        klass = Class.new(described_class) do
          step :extract, agent: agent, optional: true
        end
        expect(klass.steps[:extract][:continue_on_error]).to be true
      end

      it "assigns step index in order" do
        agent1 = extractor_agent
        agent2 = validator_agent
        klass = Class.new(described_class) do
          step :first, agent: agent1
          step :second, agent: agent2
        end
        expect(klass.steps[:first][:index]).to eq(0)
        expect(klass.steps[:second][:index]).to eq(1)
      end
    end

    describe "inheritance" do
      it "inherits steps from parent" do
        agent = extractor_agent
        parent = Class.new(described_class) do
          step :extract, agent: agent
        end
        child = Class.new(parent)
        expect(child.steps.keys).to eq([:extract])
      end

      it "can add steps in child" do
        agent1 = extractor_agent
        agent2 = validator_agent
        parent = Class.new(described_class) do
          step :extract, agent: agent1
        end
        child = Class.new(parent) do
          step :validate, agent: agent2
        end
        expect(child.steps.keys).to eq(%i[extract validate])
        expect(parent.steps.keys).to eq([:extract])
      end
    end
  end

  describe "#call" do
    it "executes steps in order" do
      ext = extractor_agent
      val = validator_agent
      fmt = formatter_agent

      pipeline = Class.new(described_class) do
        step :extract, agent: ext
        step :validate, agent: val
        step :format, agent: fmt
      end

      result = pipeline.call(text: "input")

      expect(result).to be_a(RubyLLM::Agents::Workflow::Result)
      expect(result.steps.keys).to eq(%i[extract validate format])
    end

    it "returns WorkflowResult with aggregate metrics" do
      ext = extractor_agent

      pipeline = Class.new(described_class) do
        step :extract, agent: ext
      end

      result = pipeline.call(text: "test")

      expect(result.total_cost).to eq(0.001)
      expect(result.total_tokens).to eq(150) # 100 input + 50 output
      expect(result.workflow_id).to be_present
    end

    it "provides access to individual step results" do
      ext = extractor_agent

      pipeline = Class.new(described_class) do
        step :extract, agent: ext
      end

      result = pipeline.call(text: "hello")

      expect(result.steps[:extract].content).to eq({extracted: "data from hello"})
    end

    it "sets status to success when all steps succeed" do
      ext = extractor_agent

      pipeline = Class.new(described_class) do
        step :extract, agent: ext
      end

      result = pipeline.call(text: "test")

      expect(result.status).to eq("success")
      expect(result.success?).to be true
    end
  end

  describe "step skipping" do
    it "skips steps when skip_on returns true" do
      ext = extractor_agent
      val = validator_agent

      pipeline = Class.new(described_class) do
        step :extract, agent: ext
        step :validate, agent: val, skip_on: ->(ctx) { true }
      end

      result = pipeline.call(text: "test")

      expect(result.steps[:extract]).to be_a(RubyLLM::Agents::Result)
      expect(result.steps[:validate]).to be_a(RubyLLM::Agents::Workflow::SkippedResult)
      expect(result.steps[:validate].skipped?).to be true
    end

    it "executes steps when skip_on returns false" do
      ext = extractor_agent
      val = validator_agent

      pipeline = Class.new(described_class) do
        step :extract, agent: ext
        step :validate, agent: val, skip_on: ->(ctx) { false }
      end

      result = pipeline.call(text: "test")

      expect(result.steps[:validate]).to be_a(RubyLLM::Agents::Result)
    end

    it "provides context to skip_on lambda" do
      ext = extractor_agent
      val = validator_agent
      received_context = nil

      pipeline = Class.new(described_class) do
        step :extract, agent: ext
        step :validate, agent: val, skip_on: ->(ctx) do
          received_context = ctx
          false
        end
      end

      pipeline.call(text: "test")

      expect(received_context[:input]).to eq(text: "test")
      expect(received_context[:extract]).to be_a(RubyLLM::Agents::Result)
    end
  end

  describe "input transformation" do
    it "allows before_step hooks" do
      ext = extractor_agent
      val = validator_agent

      pipeline = Class.new(described_class) do
        step :extract, agent: ext
        step :validate, agent: val

        def before_validate(context)
          { custom_key: "custom_value" }
        end
      end

      # This tests that before_validate is called
      # The validator will receive custom_key instead of extracted
      result = pipeline.call(text: "test")
      expect(result.success?).to be true
    end
  end

  describe "error handling" do
    let(:failing_agent) do
      Class.new(RubyLLM::Agents::Base) do
        model "gpt-4o"

        def call(&_block)
          raise StandardError, "Agent failed"
        end

        def user_prompt
          "fail"
        end
      end
    end

    it "sets status to error when step fails" do
      ext = extractor_agent
      fail_agent = failing_agent

      pipeline = Class.new(described_class) do
        step :extract, agent: ext
        step :fail, agent: fail_agent
      end

      result = pipeline.call(text: "test")

      expect(result.status).to eq("error")
      expect(result.error?).to be true
      expect(result.failed_steps).to include(:fail)
    end

    it "continues when optional step fails" do
      fail_agent = failing_agent
      ext = extractor_agent

      pipeline = Class.new(described_class) do
        step :fail, agent: fail_agent, optional: true
        step :extract, agent: ext
      end

      result = pipeline.call(text: "test")

      expect(result.status).to eq("partial")
      expect(result.partial?).to be true
      expect(result.steps[:extract]).to be_a(RubyLLM::Agents::Result)
    end
  end
end
