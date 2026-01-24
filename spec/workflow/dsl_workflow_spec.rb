# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Workflow DSL" do
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

  let(:fetch_agent) do
    result_builder = mock_result
    Class.new(RubyLLM::Agents::Base) do
      model "gpt-4o"

      define_method(:call) do |&_block|
        result_builder.call({ order_id: @options[:order_id], data: "fetched" })
      end

      def user_prompt
        "fetch"
      end
    end
  end

  let(:validate_agent) do
    result_builder = mock_result
    Class.new(RubyLLM::Agents::Base) do
      model "gpt-4o"

      define_method(:call) do |&_block|
        result_builder.call({ valid: true, tier: @options[:tier] || "standard" })
      end

      def user_prompt
        "validate"
      end
    end
  end

  let(:process_agent) do
    result_builder = mock_result
    Class.new(RubyLLM::Agents::Base) do
      model "gpt-4o"

      define_method(:call) do |&_block|
        result_builder.call({ processed: true })
      end

      def user_prompt
        "process"
      end
    end
  end

  let(:premium_agent) do
    result_builder = mock_result
    Class.new(RubyLLM::Agents::Base) do
      model "gpt-4o"

      define_method(:call) do |&_block|
        result_builder.call({ type: "premium", vip: @options[:vip] })
      end

      def user_prompt
        "premium"
      end
    end
  end

  let(:standard_agent) do
    result_builder = mock_result
    Class.new(RubyLLM::Agents::Base) do
      model "gpt-4o"

      define_method(:call) do |&_block|
        result_builder.call({ type: "standard" })
      end

      def user_prompt
        "standard"
      end
    end
  end

  let(:analyze_agent) do
    result_builder = mock_result
    Class.new(RubyLLM::Agents::Base) do
      model "gpt-4o"

      define_method(:call) do |&_block|
        result_builder.call({ analysis: "complete" })
      end

      def user_prompt
        "analyze"
      end
    end
  end

  let(:summarize_agent) do
    result_builder = mock_result
    Class.new(RubyLLM::Agents::Base) do
      model "gpt-4o"

      define_method(:call) do |&_block|
        result_builder.call({ summary: "brief" })
      end

      def user_prompt
        "summarize"
      end
    end
  end

  describe "minimal workflow" do
    it "executes steps in definition order" do
      fetch = fetch_agent
      validate = validate_agent
      process = process_agent

      workflow = Class.new(RubyLLM::Agents::Workflow) do
        step :fetch, fetch
        step :validate, validate
        step :process, process
      end

      result = workflow.call(order_id: "ORD-123")

      expect(result).to be_a(RubyLLM::Agents::Workflow::Result)
      expect(result.success?).to be true
      expect(result.steps.keys).to eq([:fetch, :validate, :process])
    end

    it "returns aggregate metrics" do
      fetch = fetch_agent
      validate = validate_agent

      workflow = Class.new(RubyLLM::Agents::Workflow) do
        step :fetch, fetch
        step :validate, validate
      end

      result = workflow.call(order_id: "ORD-123")

      expect(result.total_cost).to eq(0.002) # 2 steps * 0.001
      expect(result.total_tokens).to eq(300) # 2 steps * 150
    end
  end

  describe "input schema" do
    it "validates required fields" do
      fetch = fetch_agent

      workflow = Class.new(RubyLLM::Agents::Workflow) do
        input do
          required :order_id, String
        end

        step :fetch, fetch
      end

      expect { workflow.call({}) }.to raise_error(
        RubyLLM::Agents::Workflow::DSL::InputSchema::ValidationError,
        /order_id is required/
      )
    end

    it "applies defaults" do
      fetch = fetch_agent
      received_priority = nil

      workflow = Class.new(RubyLLM::Agents::Workflow) do
        input do
          required :order_id, String
          optional :priority, String, default: "normal"
        end

        step :fetch, fetch

        # Use block form which can ignore extra args passed by run_hooks
        after_step(:fetch) do
          received_priority = input.priority
        end
      end

      workflow.call(order_id: "ORD-123")

      expect(received_priority).to eq("normal")
    end

    it "provides input accessor" do
      fetch = fetch_agent
      captured_input = nil

      workflow_class = Class.new(RubyLLM::Agents::Workflow) do
        input do
          required :order_id, String
        end

        step :fetch, fetch, input: -> { captured_input = input; { order_id: input.order_id } }
      end

      workflow_class.call(order_id: "ORD-123")

      expect(captured_input.order_id).to eq("ORD-123")
    end
  end

  describe "step options" do
    describe "timeout" do
      let(:slow_agent) do
        Class.new(RubyLLM::Agents::Base) do
          model "gpt-4o"

          def call(&_block)
            sleep 2
            RubyLLM::Agents::Result.new(content: "done", model_id: "gpt-4o")
          end

          def user_prompt
            "slow"
          end
        end
      end

      it "times out slow steps", skip: "Timeout behavior tested in integration" do
        slow = slow_agent

        workflow = Class.new(RubyLLM::Agents::Workflow) do
          step :slow, slow, timeout: 1
        end

        result = workflow.call

        expect(result.error?).to be true
      end
    end

    describe "optional" do
      let(:failing_agent) do
        Class.new(RubyLLM::Agents::Base) do
          model "gpt-4o"

          def call(&_block)
            raise StandardError, "Failed"
          end

          def user_prompt
            "fail"
          end
        end
      end

      it "continues on optional step failure" do
        failing = failing_agent
        process = process_agent

        workflow = Class.new(RubyLLM::Agents::Workflow) do
          step :fail, failing, optional: true
          step :process, process
        end

        result = workflow.call

        expect(result.partial?).to be true
        expect(result.steps[:process].content[:processed]).to be true
      end

      it "uses default value on optional failure" do
        failing = failing_agent
        process = process_agent

        workflow = Class.new(RubyLLM::Agents::Workflow) do
          step :fail, failing, optional: true, default: { fallback: true }
          step :process, process
        end

        result = workflow.call

        expect(result.steps[:fail].content[:fallback]).to be true
      end
    end
  end

  describe "conditional execution" do
    it "skips steps when if condition is false" do
      fetch = fetch_agent
      premium = premium_agent

      workflow = Class.new(RubyLLM::Agents::Workflow) do
        step :fetch, fetch
        step :premium, premium, if: -> { false }
      end

      result = workflow.call(order_id: "ORD-123")

      expect(result.steps[:premium]).to be_a(RubyLLM::Agents::Workflow::SkippedResult)
    end

    it "executes steps when if condition is true" do
      fetch = fetch_agent
      premium = premium_agent

      workflow = Class.new(RubyLLM::Agents::Workflow) do
        step :fetch, fetch
        step :premium, premium, if: -> { true }
      end

      result = workflow.call(order_id: "ORD-123")

      expect(result.steps[:premium].content[:type]).to eq("premium")
    end

    it "supports symbol conditions" do
      fetch = fetch_agent
      premium = premium_agent

      workflow = Class.new(RubyLLM::Agents::Workflow) do
        step :fetch, fetch
        step :premium, premium, if: :should_process_premium?

        private

        def should_process_premium?
          true
        end
      end

      result = workflow.call(order_id: "ORD-123")

      expect(result.steps[:premium].content[:type]).to eq("premium")
    end

    it "supports unless conditions" do
      fetch = fetch_agent
      premium = premium_agent

      workflow = Class.new(RubyLLM::Agents::Workflow) do
        step :fetch, fetch
        step :premium, premium, unless: -> { true }
      end

      result = workflow.call(order_id: "ORD-123")

      expect(result.steps[:premium]).to be_a(RubyLLM::Agents::Workflow::SkippedResult)
    end
  end

  describe "routing" do
    it "routes to different agents based on value" do
      validate_klass = validate_agent
      premium_klass = premium_agent
      standard_klass = standard_agent

      workflow = Class.new(RubyLLM::Agents::Workflow) do
        step :validate, validate_klass

        step :process, on: -> { self.validate.tier } do |r|
          r.premium premium_klass
          r.standard standard_klass
          r.default standard_klass
        end
      end

      # Default tier is "standard"
      result = workflow.call

      expect(result.steps[:process].content[:type]).to eq("standard")
    end

    it "routes to premium when tier is premium" do
      result_builder = mock_result
      premium_klass = premium_agent
      standard_klass = standard_agent

      premium_validate_klass = Class.new(RubyLLM::Agents::Base) do
        model "gpt-4o"

        define_method(:call) do |&_block|
          result_builder.call({ valid: true, tier: "premium" })
        end

        def user_prompt
          "validate"
        end
      end

      workflow = Class.new(RubyLLM::Agents::Workflow) do
        step :validate, premium_validate_klass

        step :process, on: -> { self.validate.tier } do |r|
          r.premium premium_klass
          r.standard standard_klass
        end
      end

      result = workflow.call

      expect(result.steps[:process].content[:type]).to eq("premium")
    end

    it "supports per-route input mapping" do
      premium_klass = premium_agent
      standard_klass = standard_agent

      result_builder = mock_result
      premium_validate_klass = Class.new(RubyLLM::Agents::Base) do
        model "gpt-4o"

        define_method(:call) do |&_block|
          result_builder.call({ valid: true, tier: "premium" })
        end

        def user_prompt
          "validate"
        end
      end

      workflow = Class.new(RubyLLM::Agents::Workflow) do
        step :validate, premium_validate_klass

        step :process, on: -> { self.validate.tier } do |r|
          r.premium premium_klass, input: -> { { vip: true } }
          r.standard standard_klass
        end
      end

      result = workflow.call

      expect(result.steps[:process].content[:vip]).to be true
    end
  end

  describe "parallel execution" do
    it "executes steps in parallel" do
      analyze = analyze_agent
      summarize = summarize_agent

      workflow = Class.new(RubyLLM::Agents::Workflow) do
        parallel do
          step :analyze, analyze
          step :summarize, summarize
        end
      end

      result = workflow.call

      expect(result.success?).to be true
      expect(result.steps[:analyze].content[:analysis]).to eq("complete")
      expect(result.steps[:summarize].content[:summary]).to eq("brief")
    end

    it "aggregates parallel step results" do
      analyze = analyze_agent
      summarize = summarize_agent

      workflow = Class.new(RubyLLM::Agents::Workflow) do
        parallel do
          step :analyze, analyze
          step :summarize, summarize
        end
      end

      result = workflow.call

      # Total cost should include both parallel steps
      expect(result.total_cost).to eq(0.002)
    end

    it "supports named parallel groups" do
      analyze = analyze_agent
      summarize = summarize_agent

      workflow = Class.new(RubyLLM::Agents::Workflow) do
        parallel :analysis do
          step :analyze, analyze
          step :summarize, summarize
        end
      end

      expect(workflow.parallel_groups.first.name).to eq(:analysis)
    end
  end

  describe "input mapping" do
    it "passes output to next step" do
      fetch = fetch_agent
      validate = validate_agent

      workflow = Class.new(RubyLLM::Agents::Workflow) do
        step :fetch, fetch
        step :validate, validate
      end

      result = workflow.call(order_id: "ORD-123")

      # validate should receive fetch's output
      expect(result.success?).to be true
    end

    it "supports custom input mapping" do
      fetch_klass = fetch_agent
      received_input = nil

      custom_agent = Class.new(RubyLLM::Agents::Base) do
        model "gpt-4o"

        define_method(:call) do |&_block|
          received_input = @options
          RubyLLM::Agents::Result.new(content: "done", model_id: "gpt-4o")
        end

        def user_prompt
          "custom"
        end
      end

      workflow = Class.new(RubyLLM::Agents::Workflow) do
        step :fetch, fetch_klass
        step :custom, custom_agent, input: -> { { custom_key: self.fetch.order_id } }
      end

      workflow.call(order_id: "ORD-123")

      expect(received_input[:custom_key]).to eq("ORD-123")
    end

    it "supports pick fields" do
      fetch = fetch_agent
      received_input = nil

      custom_agent = Class.new(RubyLLM::Agents::Base) do
        model "gpt-4o"

        define_method(:call) do |&_block|
          received_input = @options.dup
          RubyLLM::Agents::Result.new(content: "done", model_id: "gpt-4o")
        end

        def user_prompt
          "custom"
        end
      end

      workflow = Class.new(RubyLLM::Agents::Workflow) do
        step :fetch, fetch
        step :custom, custom_agent, pick: [:order_id]
      end

      workflow.call(order_id: "ORD-123")

      expect(received_input.keys).to include(:order_id)
      expect(received_input.keys).not_to include(:data)
    end
  end

  describe "accessing step results" do
    it "provides access to previous step results" do
      fetch_klass = fetch_agent
      captured_order_id = nil

      check_agent = Class.new(RubyLLM::Agents::Base) do
        model "gpt-4o"

        define_method(:call) do |&_block|
          RubyLLM::Agents::Result.new(content: "checked", model_id: "gpt-4o")
        end

        def user_prompt
          "check"
        end
      end

      workflow = Class.new(RubyLLM::Agents::Workflow) do
        step :fetch, fetch_klass
        step :check, check_agent, input: -> { captured_order_id = self.fetch.order_id; {} }
      end

      workflow.call(order_id: "ORD-123")

      expect(captured_order_id).to eq("ORD-123")
    end
  end

  describe "lifecycle hooks" do
    it "calls before_workflow hook" do
      fetch = fetch_agent
      hook_called = false

      workflow = Class.new(RubyLLM::Agents::Workflow) do
        before_workflow do
          hook_called = true
        end

        step :fetch, fetch
      end

      workflow.call(order_id: "ORD-123")

      expect(hook_called).to be true
    end

    it "calls after_workflow hook" do
      fetch = fetch_agent
      hook_called = false

      workflow = Class.new(RubyLLM::Agents::Workflow) do
        after_workflow do
          hook_called = true
        end

        step :fetch, fetch
      end

      workflow.call(order_id: "ORD-123")

      expect(hook_called).to be true
    end
  end

  describe "class methods" do
    describe ".step_metadata" do
      it "returns step information for UI" do
        fetch = fetch_agent
        validate = validate_agent

        workflow = Class.new(RubyLLM::Agents::Workflow) do
          step :fetch, fetch, "Fetch order data", timeout: 30
          step :validate, validate, optional: true
        end

        metadata = workflow.step_metadata

        expect(metadata.size).to eq(2)
        expect(metadata[0][:name]).to eq(:fetch)
        expect(metadata[0][:timeout]).to eq(30)
        expect(metadata[1][:optional]).to be true
      end
    end

    describe ".dry_run" do
      it "validates without executing" do
        fetch = fetch_agent

        workflow = Class.new(RubyLLM::Agents::Workflow) do
          input do
            required :order_id, String
          end

          step :fetch, fetch
        end

        result = workflow.dry_run(order_id: "ORD-123")

        expect(result[:valid]).to be true
        expect(result[:steps]).to eq([:fetch])
      end

      it "returns input errors" do
        fetch = fetch_agent

        workflow = Class.new(RubyLLM::Agents::Workflow) do
          input do
            required :order_id, String
          end

          step :fetch, fetch
        end

        result = workflow.dry_run({})

        expect(result[:valid]).to be false
        expect(result[:input_errors]).to include("order_id is required")
      end
    end

    describe ".total_steps" do
      it "returns the step count" do
        fetch = fetch_agent
        validate = validate_agent

        workflow = Class.new(RubyLLM::Agents::Workflow) do
          step :fetch, fetch
          step :validate, validate
        end

        expect(workflow.total_steps).to eq(2)
      end
    end
  end

  describe "inheritance" do
    it "inherits steps from parent" do
      fetch = fetch_agent
      validate = validate_agent

      parent = Class.new(RubyLLM::Agents::Workflow) do
        step :fetch, fetch
      end

      child = Class.new(parent) do
        step :validate, validate
      end

      expect(child.step_configs.keys).to eq([:fetch, :validate])
      expect(parent.step_configs.keys).to eq([:fetch])
    end
  end
end
