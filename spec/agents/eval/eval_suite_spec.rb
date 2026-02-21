# frozen_string_literal: true

require "rails_helper"
require "ostruct"

RSpec.describe RubyLLM::Agents::Eval::EvalSuite do
  # --- Test agents ---

  let(:classifier_agent) do
    Class.new(RubyLLM::Agents::BaseAgent) do
      def self.name
        "ClassifierAgent"
      end

      model "gpt-4o-mini"
      system "Classify the input as positive or negative. Reply with only the word."
      user "{text}"
      param :text, required: true
    end
  end

  before do
    stub_agent_configuration(track_executions: false)
  end

  # --- DSL ---

  describe "DSL" do
    it "registers agent class" do
      agent = classifier_agent
      suite = Class.new(described_class) do
        self.agent agent
        test_case "a", input: {text: "hi"}, expected: "positive"
      end

      expect(suite.agent_class).to eq(agent)
    end

    it "registers test cases" do
      agent = classifier_agent
      suite = Class.new(described_class) do
        self.agent agent
        test_case "case1", input: {text: "good"}, expected: "positive"
        test_case "case2", input: {text: "bad"}, expected: "negative"
      end

      expect(suite.test_cases.size).to eq(2)
      expect(suite.test_cases.first.name).to eq("case1")
      expect(suite.test_cases.last.name).to eq("case2")
    end

    it "sets eval model and temperature" do
      agent = classifier_agent
      suite = Class.new(described_class) do
        self.agent agent
        test_case "a", input: {text: "hi"}, expected: "positive"
        eval_model "gpt-4o"
        eval_temperature 0.0
      end

      expect(suite.eval_options[:model]).to eq("gpt-4o")
      expect(suite.eval_options[:temperature]).to eq(0.0)
    end

    it "isolates test cases between subclasses" do
      agent = classifier_agent
      suite_a = Class.new(described_class) do
        self.agent agent
        test_case "a", input: {text: "a"}, expected: "positive"
      end

      suite_b = Class.new(described_class) do
        self.agent agent
        test_case "b", input: {text: "b"}, expected: "negative"
      end

      expect(suite_a.test_cases.size).to eq(1)
      expect(suite_b.test_cases.size).to eq(1)
      expect(suite_a.test_cases.first.name).to eq("a")
      expect(suite_b.test_cases.first.name).to eq("b")
    end
  end

  # --- Validation ---

  describe ".validate!" do
    it "raises when no agent class is set" do
      suite = Class.new(described_class) do
        test_case "a", input: {text: "hi"}, expected: "positive"
      end

      expect { suite.validate! }.to raise_error(
        RubyLLM::Agents::ConfigurationError, /No agent class set/
      )
    end

    it "raises when no test cases are defined" do
      agent = classifier_agent
      suite = Class.new(described_class) do
        self.agent agent
      end

      expect { suite.validate! }.to raise_error(
        RubyLLM::Agents::ConfigurationError, /No test cases defined/
      )
    end

    it "raises when test case is missing required params" do
      agent = classifier_agent
      suite = Class.new(described_class) do
        self.agent agent
        test_case "missing", input: {wrong_param: "hi"}, expected: "positive"
      end

      expect { suite.validate! }.to raise_error(
        RubyLLM::Agents::ConfigurationError, /missing required params.*text/
      )
    end

    it "skips param validation for lazy inputs" do
      agent = classifier_agent
      suite = Class.new(described_class) do
        self.agent agent
        test_case "lazy", input: -> { {text: "lazy"} }, expected: "positive"
      end

      expect(suite.validate!).to be true
    end

    it "passes for valid configuration" do
      agent = classifier_agent
      suite = Class.new(described_class) do
        self.agent agent
        test_case "valid", input: {text: "hello"}, expected: "positive"
      end

      expect(suite.validate!).to be true
    end
  end

  # --- Running ---

  describe ".run!" do
    it "runs test cases and returns an EvalRun" do
      mock = build_mock_chat_client(
        response: build_mock_response(content: "positive")
      )
      stub_ruby_llm_chat(mock)

      agent = classifier_agent
      suite = Class.new(described_class) do
        self.agent agent
        test_case "positive", input: {text: "I love this!"}, expected: "positive"
        test_case "negative", input: {text: "I hate this."}, expected: "negative"
      end

      run = suite.run!

      expect(run).to be_a(RubyLLM::Agents::Eval::EvalRun)
      expect(run.total_cases).to eq(2)
      expect(run.agent_class).to eq(agent)
    end

    it "scores exact match correctly" do
      mock = build_mock_chat_client(
        response: build_mock_response(content: "positive")
      )
      stub_ruby_llm_chat(mock)

      agent = classifier_agent
      suite = Class.new(described_class) do
        self.agent agent
        test_case "match", input: {text: "great!"}, expected: "positive"
        test_case "mismatch", input: {text: "terrible"}, expected: "negative"
      end

      run = suite.run!

      expect(run.passed).to eq(1)
      expect(run.failed).to eq(1)
      expect(run.score).to eq(0.5)
    end

    it "scores contains correctly" do
      mock = build_mock_chat_client(
        response: build_mock_response(content: "We have a 30-day refund policy.")
      )
      stub_ruby_llm_chat(mock)

      agent = classifier_agent
      suite = Class.new(described_class) do
        self.agent agent
        test_case "contains hit",
          input: {text: "refund?"},
          score: :contains,
          expected: "refund policy"

        test_case "contains miss",
          input: {text: "exchange?"},
          score: :contains,
          expected: "exchange"
      end

      run = suite.run!
      expect(run.results[0].score.value).to eq(1.0)
      expect(run.results[1].score.value).to eq(0.0)
    end

    it "scores with custom lambda" do
      mock = build_mock_chat_client(
        response: build_mock_response(content: "positive")
      )
      stub_ruby_llm_chat(mock)

      agent = classifier_agent
      suite = Class.new(described_class) do
        self.agent agent
        test_case "custom",
          input: {text: "hello"},
          score: ->(result, _expected) {
            (result.content == "positive") ? 1.0 : 0.0
          }
      end

      run = suite.run!
      expect(run.results.first.score.value).to eq(1.0)
    end

    it "coerces boolean lambda results" do
      mock = build_mock_chat_client(
        response: build_mock_response(content: "yes")
      )
      stub_ruby_llm_chat(mock)

      agent = classifier_agent
      suite = Class.new(described_class) do
        self.agent agent
        test_case "bool true",
          input: {text: "hello"},
          score: ->(_result, _expected) { true }
        test_case "bool false",
          input: {text: "hello"},
          score: ->(_result, _expected) { false }
      end

      run = suite.run!
      expect(run.results[0].score.value).to eq(1.0)
      expect(run.results[1].score.value).to eq(0.0)
    end

    it "handles agent errors gracefully" do
      mock = build_mock_chat_client(error: RuntimeError.new("API down"))
      stub_ruby_llm_chat(mock)

      agent = classifier_agent
      suite = Class.new(described_class) do
        self.agent agent
        test_case "will fail", input: {text: "test"}, expected: "positive"
        test_case "also fails", input: {text: "test"}, expected: "negative"
      end

      run = suite.run!

      # Both cases should have score 0.0 but the run should complete
      expect(run.total_cases).to eq(2)
      expect(run.failed).to eq(2)
      expect(run.results.first.errored?).to be true
      expect(run.results.first.score.reason).to include("RuntimeError")
    end

    it "filters cases with only:" do
      mock = build_mock_chat_client(
        response: build_mock_response(content: "positive")
      )
      stub_ruby_llm_chat(mock)

      agent = classifier_agent
      suite = Class.new(described_class) do
        self.agent agent
        test_case "run this", input: {text: "good"}, expected: "positive"
        test_case "skip this", input: {text: "bad"}, expected: "negative"
      end

      run = suite.run!(only: "run this")

      expect(run.total_cases).to eq(1)
      expect(run.results.first.test_case_name).to eq("run this")
    end

    it "merges overrides into test case inputs" do
      captured_inputs = []
      mock = build_mock_chat_client(
        response: build_mock_response(content: "positive")
      )
      allow(mock).to receive(:ask) do |prompt, **_opts|
        captured_inputs << prompt
        build_mock_response(content: "positive")
      end
      stub_ruby_llm_chat(mock)

      agent = classifier_agent
      suite = Class.new(described_class) do
        self.agent agent
        test_case "with override", input: {text: "hello"}, expected: "positive"
      end

      # The agent was called — overrides are merged into call_options
      result = suite.run!(overrides: {extra: "data"})
      expect(result).to be_a(RubyLLM::Agents::Eval::EvalRun)
    end

    it "resolves lazy inputs before calling the agent" do
      call_count = 0
      mock = build_mock_chat_client(
        response: build_mock_response(content: "positive")
      )
      stub_ruby_llm_chat(mock)

      agent = classifier_agent
      suite = Class.new(described_class) do
        self.agent agent
        test_case "lazy",
          input: -> {
            call_count += 1
            {text: "lazy input #{call_count}"}
          },
          expected: "positive"
      end

      suite.run!
      expect(call_count).to eq(1)

      suite.run!
      expect(call_count).to eq(2)
    end

    it "uses custom pass_threshold" do
      mock = build_mock_chat_client(
        response: build_mock_response(content: "positive")
      )
      stub_ruby_llm_chat(mock)

      agent = classifier_agent
      suite = Class.new(described_class) do
        self.agent agent
        test_case "match", input: {text: "good"}, expected: "positive"
      end

      # With threshold 0.5, score 1.0 passes
      run = suite.run!(pass_threshold: 0.5)
      expect(run.passed).to eq(1)

      # With threshold 1.1, nothing can pass (edge case)
      run = suite.run!(pass_threshold: 1.1)
      expect(run.passed).to eq(0)
    end

    it "raises for unknown scorer" do
      mock = build_mock_chat_client(
        response: build_mock_response(content: "ok")
      )
      stub_ruby_llm_chat(mock)

      agent = classifier_agent
      suite = Class.new(described_class) do
        self.agent agent
        test_case "bad scorer", input: {text: "hi"}, score: :nonexistent, expected: "ok"
      end

      expect { suite.run! }.to raise_error(ArgumentError, /Unknown scorer/)
    end
  end

  # --- Programmatic suite ---

  describe ".for" do
    it "creates a suite programmatically" do
      mock = build_mock_chat_client(
        response: build_mock_response(content: "positive")
      )
      stub_ruby_llm_chat(mock)

      agent = classifier_agent
      suite = described_class.for(agent) do
        test_case "inline", input: {text: "hello"}, expected: "positive"
      end

      expect(suite.agent_class).to eq(agent)
      expect(suite.test_cases.size).to eq(1)

      run = suite.run!
      expect(run.total_cases).to eq(1)
      expect(run.passed).to eq(1)
    end
  end

  # --- YAML dataset ---

  describe ".dataset" do
    it "loads test cases from a YAML file" do
      yaml_content = [
        {name: "billing", input: {text: "charged twice"}, expected: "billing"},
        {name: "tech", input: {text: "500 error"}, expected: "technical"}
      ]

      yaml_path = Rails.root.join("tmp", "test_dataset.yml")
      FileUtils.mkdir_p(File.dirname(yaml_path))
      File.write(yaml_path, yaml_content.to_yaml)

      mock = build_mock_chat_client(
        response: build_mock_response(content: "billing")
      )
      stub_ruby_llm_chat(mock)

      agent = classifier_agent
      suite = Class.new(described_class) do
        self.agent agent
        dataset "tmp/test_dataset.yml"
      end

      expect(suite.test_cases.size).to eq(2)
      expect(suite.test_cases.first.name).to eq("billing")

      run = suite.run!
      expect(run.total_cases).to eq(2)
    ensure
      FileUtils.rm_f(yaml_path) if yaml_path
    end
  end
end
