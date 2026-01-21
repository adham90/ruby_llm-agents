# frozen_string_literal: true

require "rails_helper"

RSpec.describe RubyLLM::Agents::ImagePipeline::Execution do
  # Create test pipeline class that uses the Execution module
  let(:test_pipeline_class) do
    Class.new(RubyLLM::Agents::ImagePipeline) do
      def self.name
        "TestImagePipeline"
      end

      version "1.0.0"
      cache_for 1.hour

      step :generate, generator: RubyLLM::Agents::ImageGenerator
    end
  end

  let(:test_pipeline_with_multiple_steps) do
    Class.new(RubyLLM::Agents::ImagePipeline) do
      def self.name
        "MultiStepPipeline"
      end

      version "1.0.0"

      step :generate, generator: RubyLLM::Agents::ImageGenerator
      step :upscale, upscaler: RubyLLM::Agents::ImageUpscaler
    end
  end

  let(:conditional_pipeline_class) do
    Class.new(RubyLLM::Agents::ImagePipeline) do
      def self.name
        "ConditionalPipeline"
      end

      version "1.0.0"

      step :generate, generator: RubyLLM::Agents::ImageGenerator, if: :should_generate?

      def should_generate?
        true
      end
    end
  end

  before do
    RubyLLM::Agents.reset_configuration!
    RubyLLM::Agents.configure do |config|
      config.track_image_generation = true
      config.async_logging = false
    end
  end

  describe "#execute" do
    let(:mock_generator_result) do
      double("GeneratorResult",
        success?: true,
        error?: false,
        url: "https://example.com/image.png",
        data: nil,
        total_cost: 0.04,
        duration_ms: 1000,
        model_id: "dall-e-3")
    end

    before do
      allow_any_instance_of(RubyLLM::Agents::ImageGenerator).to receive(:call).and_return(mock_generator_result)
      # Stub execution tracking
      allow(RubyLLM::Agents::Execution).to receive(:create!)
    end

    it "executes pipeline steps in order" do
      result = test_pipeline_class.call(prompt: "A test image")

      expect(result).to be_a(RubyLLM::Agents::ImagePipelineResult)
    end

    it "returns result with step data" do
      result = test_pipeline_class.call(prompt: "A test image")

      expect(result.step_count).to be >= 1
    end

    it "handles step errors" do
      error_result = double("ErrorResult",
        success?: false,
        error?: true,
        url: nil,
        data: nil,
        total_cost: 0,
        duration_ms: 100,
        model_id: "dall-e-3")

      allow_any_instance_of(RubyLLM::Agents::ImageGenerator).to receive(:call).and_return(error_result)

      result = test_pipeline_class.call(prompt: "A test image")

      # Pipeline should still return a result, possibly with errors
      expect(result).to be_a(RubyLLM::Agents::ImagePipelineResult)
    end
  end

  describe "#should_run_step?" do
    # Create a test class to expose private method
    let(:execution_test_class) do
      Class.new(RubyLLM::Agents::ImagePipeline) do
        include RubyLLM::Agents::ImagePipeline::Execution

        def self.name
          "ExecutionTestPipeline"
        end

        attr_accessor :test_context

        def initialize(options = {})
          @options = options
          @context = {}
          @test_context = {}
        end

        def test_should_run_step?(step_def)
          should_run_step?(step_def)
        end

        def test_evaluate_condition(condition)
          @context = @test_context
          evaluate_condition(condition)
        end

        def respond_to_missing?(name, include_private = false)
          @test_context.key?(name) || super
        end

        def method_missing(name, *args)
          if @test_context.key?(name)
            @test_context[name]
          else
            super
          end
        end
      end
    end

    let(:execution_instance) { execution_test_class.new }

    it "returns true when no conditions specified" do
      step_def = { name: :test, type: :generator, config: {} }

      expect(execution_instance.test_should_run_step?(step_def)).to be true
    end

    it "returns false when :if condition evaluates to false" do
      # Use a proc that returns false, since literal false would skip the check
      step_def = { name: :test, type: :generator, config: { if: ->(_ctx) { false } } }

      expect(execution_instance.test_should_run_step?(step_def)).to be false
    end

    it "returns true when :if condition evaluates to true" do
      step_def = { name: :test, type: :generator, config: { if: ->(_ctx) { true } } }

      expect(execution_instance.test_should_run_step?(step_def)).to be true
    end

    it "returns false when :unless condition evaluates to true" do
      step_def = { name: :test, type: :generator, config: { unless: ->(_ctx) { true } } }

      expect(execution_instance.test_should_run_step?(step_def)).to be false
    end

    it "returns true when :unless condition evaluates to false" do
      step_def = { name: :test, type: :generator, config: { unless: ->(_ctx) { false } } }

      expect(execution_instance.test_should_run_step?(step_def)).to be true
    end

    it "skips check when :if is literal false (truthy check)" do
      # Literal false value means the if block doesn't execute at all
      step_def = { name: :test, type: :generator, config: { if: false } }

      expect(execution_instance.test_should_run_step?(step_def)).to be true
    end
  end

  describe "#evaluate_condition" do
    let(:execution_test_class) do
      Class.new(RubyLLM::Agents::ImagePipeline) do
        include RubyLLM::Agents::ImagePipeline::Execution

        def self.name
          "ConditionTestPipeline"
        end

        attr_accessor :test_context

        def initialize(options = {})
          @options = options
          @context = {}
          @test_context = {}
        end

        def test_evaluate_condition(condition)
          @context = @test_context
          evaluate_condition(condition)
        end

        def test_method
          "method_result"
        end
      end
    end

    let(:execution_instance) { execution_test_class.new }

    it "evaluates Proc conditions" do
      condition = ->(ctx) { ctx[:key] == "value" }
      execution_instance.test_context = { key: "value" }

      expect(execution_instance.test_evaluate_condition(condition)).to be true
    end

    it "evaluates Symbol conditions by calling method if exists" do
      expect(execution_instance.test_evaluate_condition(:test_method)).to eq("method_result")
    end

    it "evaluates Symbol conditions from context if method not defined" do
      execution_instance.test_context = { other_key: "context_value" }

      expect(execution_instance.test_evaluate_condition(:other_key)).to eq("context_value")
    end

    it "returns non-proc/symbol conditions as-is" do
      expect(execution_instance.test_evaluate_condition(true)).to be true
      expect(execution_instance.test_evaluate_condition(false)).to be false
      expect(execution_instance.test_evaluate_condition("string")).to eq("string")
    end
  end

  describe "#execute_step" do
    # Create test class that exposes execute_step
    let(:step_test_class) do
      Class.new(RubyLLM::Agents::ImagePipeline) do
        include RubyLLM::Agents::ImagePipeline::Execution

        def self.name
          "StepTestPipeline"
        end

        attr_accessor :options

        def initialize(opts = {})
          @options = opts
          @context = {}
        end

        def test_execute_step(step_def, current_image)
          execute_step(step_def, current_image)
        end
      end
    end

    let(:step_instance) { step_test_class.new }

    let(:mock_result) do
      double("Result", success?: true, error?: false)
    end

    it "executes generator step" do
      step_def = {
        name: :generate,
        type: :generator,
        config: { generator: RubyLLM::Agents::ImageGenerator, prompt: "test" }
      }

      allow(RubyLLM::Agents::ImageGenerator).to receive(:call).and_return(mock_result)

      result = step_instance.test_execute_step(step_def, nil)

      expect(RubyLLM::Agents::ImageGenerator).to have_received(:call)
      expect(result).to eq(mock_result)
    end

    it "raises error for generator without prompt" do
      step_def = {
        name: :generate,
        type: :generator,
        config: { generator: RubyLLM::Agents::ImageGenerator }
      }

      expect {
        step_instance.test_execute_step(step_def, nil)
      }.to raise_error(ArgumentError, /requires a prompt/)
    end

    it "executes upscaler step" do
      step_def = {
        name: :upscale,
        type: :upscaler,
        config: { upscaler: RubyLLM::Agents::ImageUpscaler }
      }

      allow(RubyLLM::Agents::ImageUpscaler).to receive(:call).and_return(mock_result)

      result = step_instance.test_execute_step(step_def, "http://example.com/image.png")

      expect(RubyLLM::Agents::ImageUpscaler).to have_received(:call)
    end

    it "raises error for upscaler without image" do
      step_def = {
        name: :upscale,
        type: :upscaler,
        config: { upscaler: RubyLLM::Agents::ImageUpscaler }
      }

      expect {
        step_instance.test_execute_step(step_def, nil)
      }.to raise_error(ArgumentError, /requires an input image/)
    end

    it "executes analyzer step" do
      step_def = {
        name: :analyze,
        type: :analyzer,
        config: { analyzer: RubyLLM::Agents::ImageAnalyzer }
      }

      allow(RubyLLM::Agents::ImageAnalyzer).to receive(:call).and_return(mock_result)

      result = step_instance.test_execute_step(step_def, "http://example.com/image.png")

      expect(RubyLLM::Agents::ImageAnalyzer).to have_received(:call)
    end

    it "raises error for unknown step type" do
      step_def = {
        name: :unknown,
        type: :unknown_type,
        config: {}
      }

      expect {
        step_instance.test_execute_step(step_def, nil)
      }.to raise_error(ArgumentError, /Unknown step type/)
    end
  end

  describe "#extract_image_from_result" do
    let(:extraction_test_class) do
      Class.new(RubyLLM::Agents::ImagePipeline) do
        include RubyLLM::Agents::ImagePipeline::Execution

        def self.name
          "ExtractionTestPipeline"
        end

        def test_extract_image(result)
          extract_image_from_result(result)
        end
      end
    end

    let(:extraction_instance) { extraction_test_class.new }

    it "extracts URL from result" do
      result = double("Result", url: "https://example.com/image.png", data: nil)
      allow(result).to receive(:respond_to?).with(:url).and_return(true)

      expect(extraction_instance.test_extract_image(result)).to eq("https://example.com/image.png")
    end

    it "extracts data from result when no URL" do
      result = double("Result")
      allow(result).to receive(:respond_to?).with(:url).and_return(true)
      allow(result).to receive(:url).and_return(nil)
      allow(result).to receive(:respond_to?).with(:data).and_return(true)
      allow(result).to receive(:data).and_return("base64data")

      expect(extraction_instance.test_extract_image(result)).to eq("base64data")
    end

    it "returns result as-is when no standard methods" do
      result = "raw_image"
      expect(extraction_instance.test_extract_image(result)).to eq("raw_image")
    end
  end

  describe "#build_result and #build_error_result" do
    let(:result_test_class) do
      Class.new(RubyLLM::Agents::ImagePipeline) do
        include RubyLLM::Agents::ImagePipeline::Execution

        def self.name
          "ResultTestPipeline"
        end

        attr_accessor :step_results, :started_at, :tenant_id, :context

        def initialize
          @step_results = []
          @started_at = Time.current
          @tenant_id = nil
          @context = {}
        end

        def test_build_result
          build_result
        end

        def test_build_error_result(error)
          build_error_result(error)
        end
      end
    end

    let(:result_instance) { result_test_class.new }

    it "builds successful result" do
      result_instance.step_results = [
        { name: :generate, type: :generator, result: double(success?: true) }
      ]

      result = result_instance.test_build_result

      expect(result).to be_a(RubyLLM::Agents::ImagePipelineResult)
    end

    it "builds error result" do
      error = StandardError.new("Pipeline failed")

      result = result_instance.test_build_error_result(error)

      expect(result).to be_a(RubyLLM::Agents::ImagePipelineResult)
      expect(result.error?).to be true
    end
  end

  describe "cache key generation" do
    let(:cache_test_class) do
      Class.new(RubyLLM::Agents::ImagePipeline) do
        include RubyLLM::Agents::ImagePipeline::Execution

        def self.name
          "CacheTestPipeline"
        end

        def self.version
          "1.0.0"
        end

        def self.steps
          [{ name: :generate, type: :generator }]
        end

        def self.cache_enabled?
          true
        end

        def self.cache_ttl
          1.hour
        end

        attr_accessor :options

        def initialize(opts = {})
          @options = opts
        end

        def test_cache_key
          cache_key
        end
      end
    end

    it "generates consistent cache key" do
      instance = cache_test_class.new(prompt: "test prompt")

      key1 = instance.test_cache_key
      key2 = instance.test_cache_key

      expect(key1).to eq(key2)
    end

    it "generates different keys for different prompts" do
      instance1 = cache_test_class.new(prompt: "prompt 1")
      instance2 = cache_test_class.new(prompt: "prompt 2")

      expect(instance1.test_cache_key).not_to eq(instance2.test_cache_key)
    end
  end

  describe "#calculate_partial_cost" do
    let(:cost_test_class) do
      Class.new(RubyLLM::Agents::ImagePipeline) do
        include RubyLLM::Agents::ImagePipeline::Execution

        def self.name
          "CostTestPipeline"
        end

        attr_accessor :step_results

        def initialize
          @step_results = nil
        end

        def test_calculate_partial_cost
          calculate_partial_cost
        end
      end
    end

    it "returns 0 when no step_results" do
      instance = cost_test_class.new
      instance.step_results = nil

      expect(instance.test_calculate_partial_cost).to eq(0)
    end

    it "sums costs from all steps" do
      instance = cost_test_class.new
      instance.step_results = [
        { result: double(total_cost: 0.02) },
        { result: double(total_cost: 0.03) }
      ]

      expect(instance.test_calculate_partial_cost).to eq(0.05)
    end

    it "handles nil results" do
      instance = cost_test_class.new
      instance.step_results = [
        { result: double(total_cost: 0.02) },
        { result: nil }
      ]

      expect(instance.test_calculate_partial_cost).to eq(0.02)
    end
  end

  describe "#run_callbacks" do
    let(:callback_test_class) do
      Class.new(RubyLLM::Agents::ImagePipeline) do
        include RubyLLM::Agents::ImagePipeline::Execution

        def self.name
          "CallbackTestPipeline"
        end

        def self.callbacks
          @callbacks ||= { before: [], after: [] }
        end

        attr_accessor :callback_calls

        def initialize
          @callback_calls = []
        end

        def test_run_callbacks(type, *args)
          run_callbacks(type, *args)
        end

        def my_callback(*args)
          @callback_calls << [:method, args]
        end
      end
    end

    it "runs symbol callbacks by calling method" do
      callback_test_class.callbacks[:before] << :my_callback

      instance = callback_test_class.new
      instance.test_run_callbacks(:before)

      expect(instance.callback_calls).to include([:method, []])
    end

    it "runs proc callbacks" do
      calls = []
      callback_test_class.callbacks[:after] = [
        ->(result) { calls << result }
      ]

      instance = callback_test_class.new
      instance.test_run_callbacks(:after, "result")

      expect(calls).to eq(["result"])
    end
  end
end
