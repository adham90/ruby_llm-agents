# frozen_string_literal: true

require "rails_helper"
require "ostruct"

RSpec.describe RubyLLM::Agents::ModerationExecution do
  # Helper to create a fresh agent class for each test
  def create_agent_class(&block)
    Class.new(RubyLLM::Agents::Base) do
      class_eval(&block) if block
    end
  end

  # Mock moderation result
  def mock_moderation_result(flagged:, categories: [], scores: {}, model: "omni-moderation-latest")
    OpenStruct.new(
      flagged?: flagged,
      flagged_categories: categories,
      category_scores: scores,
      model: model,
      id: "modr-#{SecureRandom.hex(4)}"
    )
  end

  let(:agent_class) do
    create_agent_class do
      moderation :input

      def system_prompt
        "You are a helpful assistant"
      end

      def user_prompt
        @options[:query] || "Test prompt"
      end
    end
  end

  before do
    allow_any_instance_of(RubyLLM::Agents::Base).to receive(:build_client).and_return(double)
  end

  describe "#moderate_input" do
    let(:agent) { agent_class.new(query: "test") }

    context "when input moderation is enabled" do
      before do
        allow(RubyLLM).to receive(:moderate).and_return(
          mock_moderation_result(flagged: false)
        )
        allow(agent).to receive(:record_moderation_execution)
      end

      it "calls RubyLLM.moderate with the text" do
        agent.moderate_input("test")
        expect(RubyLLM).to have_received(:moderate).with("test")
      end

      it "returns the moderation result" do
        result = agent.moderate_input("test")
        expect(result.flagged?).to be false
      end

      it "stores result in moderation_results" do
        agent.moderate_input("test")
        expect(agent.moderation_results[:input]).to be_present
      end
    end

    context "when input moderation is disabled" do
      let(:agent_class) do
        create_agent_class do
          moderation :output # Only output moderation

          def user_prompt
            "test"
          end
        end
      end

      it "returns nil" do
        agent = agent_class.new
        result = agent.moderate_input("test")
        expect(result).to be_nil
      end
    end

    context "when moderation is disabled at runtime" do
      it "returns nil when moderation: false is passed" do
        agent = agent_class.new(query: "test", moderation: false)
        result = agent.moderate_input("test")
        expect(result).to be_nil
      end
    end
  end

  describe "#moderate_output" do
    let(:output_agent_class) do
      create_agent_class do
        moderation :output

        def user_prompt
          "test"
        end
      end
    end

    let(:agent) { output_agent_class.new }

    before do
      allow(RubyLLM).to receive(:moderate).and_return(
        mock_moderation_result(flagged: false)
      )
      allow(agent).to receive(:record_moderation_execution)
    end

    it "moderates output when output phase is configured" do
      agent.moderate_output("output text")
      expect(RubyLLM).to have_received(:moderate).with("output text")
    end

    it "returns nil when output phase is not configured" do
      input_only_agent = agent_class.new(query: "test")
      result = input_only_agent.moderate_output("output text")
      expect(result).to be_nil
    end
  end

  describe "#moderation_blocked?" do
    let(:agent) { agent_class.new(query: "test") }

    it "returns false by default" do
      expect(agent.moderation_blocked?).to be false
    end

    it "returns true after content is blocked" do
      flagged_result = mock_moderation_result(
        flagged: true,
        categories: [:hate],
        scores: { hate: 0.95 }
      )
      allow(RubyLLM).to receive(:moderate).and_return(flagged_result)
      allow(agent).to receive(:record_moderation_execution)

      agent.moderate_input("bad content")

      expect(agent.moderation_blocked?).to be true
    end
  end

  describe "#moderation_blocked_phase" do
    let(:agent) { agent_class.new(query: "test") }

    it "returns nil by default" do
      expect(agent.moderation_blocked_phase).to be_nil
    end

    it "returns :input when input moderation blocked" do
      flagged_result = mock_moderation_result(
        flagged: true,
        categories: [:hate],
        scores: { hate: 0.95 }
      )
      allow(RubyLLM).to receive(:moderate).and_return(flagged_result)
      allow(agent).to receive(:record_moderation_execution)

      agent.moderate_input("bad content")

      expect(agent.moderation_blocked_phase).to eq(:input)
    end
  end

  describe "#moderation_results" do
    let(:agent) { agent_class.new(query: "test") }

    it "returns empty hash by default" do
      expect(agent.moderation_results).to eq({})
    end

    it "contains results keyed by phase after moderation" do
      allow(RubyLLM).to receive(:moderate).and_return(
        mock_moderation_result(flagged: false)
      )
      allow(agent).to receive(:record_moderation_execution)

      agent.moderate_input("test")

      expect(agent.moderation_results).to have_key(:input)
    end
  end

  describe "#should_moderate? (private)" do
    it "returns true for configured phase" do
      agent = agent_class.new(query: "test")
      expect(agent.send(:should_moderate?, :input)).to be true
    end

    it "returns false for unconfigured phase" do
      agent = agent_class.new(query: "test")
      expect(agent.send(:should_moderate?, :output)).to be false
    end

    it "returns false when moderation is disabled via options" do
      agent = agent_class.new(query: "test", moderation: false)
      expect(agent.send(:should_moderate?, :input)).to be false
    end

    it "returns false when no moderation configured" do
      no_moderation_class = create_agent_class do
        def user_prompt
          "test"
        end
      end
      agent = no_moderation_class.new
      expect(agent.send(:should_moderate?, :input)).to be false
    end
  end

  describe "#resolved_moderation_config (private)" do
    it "returns nil when moderation is false" do
      agent = agent_class.new(query: "test", moderation: false)
      expect(agent.send(:resolved_moderation_config)).to be_nil
    end

    it "returns class config when no runtime override" do
      agent = agent_class.new(query: "test")
      config = agent.send(:resolved_moderation_config)
      expect(config[:phases]).to eq([:input])
    end

    it "merges runtime options with class config" do
      agent = agent_class.new(query: "test", moderation: { threshold: 0.9, on_flagged: :raise })
      config = agent.send(:resolved_moderation_config)

      expect(config[:phases]).to eq([:input])
      expect(config[:threshold]).to eq(0.9)
      expect(config[:on_flagged]).to eq(:raise)
    end
  end

  describe "#content_flagged? (private)" do
    let(:agent) { agent_class.new(query: "test") }

    it "returns false when result is not flagged" do
      result = mock_moderation_result(flagged: false)
      config = { phases: [:input], on_flagged: :block }
      expect(agent.send(:content_flagged?, result, config, :input)).to be false
    end

    it "returns true when result is flagged and no threshold" do
      result = mock_moderation_result(flagged: true, categories: [:hate])
      config = { phases: [:input], on_flagged: :block }
      expect(agent.send(:content_flagged?, result, config, :input)).to be true
    end

    it "returns false when score is below global threshold" do
      result = mock_moderation_result(
        flagged: true,
        categories: [:hate],
        scores: { hate: 0.5 }
      )
      config = { phases: [:input], threshold: 0.8, on_flagged: :block }
      expect(agent.send(:content_flagged?, result, config, :input)).to be false
    end

    it "returns true when score meets global threshold" do
      result = mock_moderation_result(
        flagged: true,
        categories: [:hate],
        scores: { hate: 0.9 }
      )
      config = { phases: [:input], threshold: 0.8, on_flagged: :block }
      expect(agent.send(:content_flagged?, result, config, :input)).to be true
    end

    it "uses phase-specific threshold over global threshold" do
      result = mock_moderation_result(
        flagged: true,
        categories: [:hate],
        scores: { hate: 0.7 }
      )
      # Global threshold is 0.9 (would be false), but input threshold is 0.6 (should be true)
      config = { phases: [:input], threshold: 0.9, input_threshold: 0.6, on_flagged: :block }
      expect(agent.send(:content_flagged?, result, config, :input)).to be true
    end

    it "returns false when flagged category not in filter" do
      result = mock_moderation_result(flagged: true, categories: [:sexual])
      config = { phases: [:input], categories: [:hate, :violence], on_flagged: :block }
      expect(agent.send(:content_flagged?, result, config, :input)).to be false
    end

    it "returns true when flagged category is in filter" do
      result = mock_moderation_result(flagged: true, categories: [:hate, :sexual])
      config = { phases: [:input], categories: [:hate, :violence], on_flagged: :block }
      expect(agent.send(:content_flagged?, result, config, :input)).to be true
    end

    it "returns false when scores hash is empty and threshold is set" do
      result = mock_moderation_result(flagged: true, categories: [:hate], scores: {})
      config = { phases: [:input], threshold: 0.8, on_flagged: :block }
      expect(agent.send(:content_flagged?, result, config, :input)).to be false
    end
  end

  describe "#normalize_category (private)" do
    let(:agent) { agent_class.new(query: "test") }

    it "normalizes slashes to underscores" do
      expect(agent.send(:normalize_category, "hate/threatening")).to eq(:hate_threatening)
    end

    it "normalizes hyphens to underscores" do
      expect(agent.send(:normalize_category, "self-harm")).to eq(:self_harm)
    end

    it "converts to lowercase" do
      expect(agent.send(:normalize_category, "HATE")).to eq(:hate)
    end

    it "handles symbols" do
      expect(agent.send(:normalize_category, :violence)).to eq(:violence)
    end

    it "handles complex categories" do
      expect(agent.send(:normalize_category, "self-harm/intent")).to eq(:self_harm_intent)
    end
  end

  describe "#handle_flagged_content (private)" do
    let(:agent) { agent_class.new(query: "test") }
    let(:flagged_result) { mock_moderation_result(flagged: true, categories: [:hate]) }

    it "raises ModerationError when on_flagged is :raise" do
      config = { phases: [:input], on_flagged: :raise }
      expect {
        agent.send(:handle_flagged_content, flagged_result, config, :input)
      }.to raise_error(RubyLLM::Agents::ModerationError)
    end

    it "sets moderation_blocked when on_flagged is :block" do
      config = { phases: [:input], on_flagged: :block }
      agent.send(:handle_flagged_content, flagged_result, config, :input)
      expect(agent.moderation_blocked?).to be true
      expect(agent.moderation_blocked_phase).to eq(:input)
    end

    it "logs warning when on_flagged is :warn" do
      config = { phases: [:input], on_flagged: :warn }
      expect(Rails.logger).to receive(:warn).with(/Content flagged/)
      agent.send(:handle_flagged_content, flagged_result, config, :input)
    end

    it "logs info when on_flagged is :log" do
      config = { phases: [:input], on_flagged: :log }
      expect(Rails.logger).to receive(:info).with(/Content flagged/)
      agent.send(:handle_flagged_content, flagged_result, config, :input)
    end

    it "calls custom handler when configured" do
      handler_called = false
      handler_result = nil
      handler_phase = nil

      agent_with_handler = create_agent_class do
        moderation :input, custom_handler: :my_handler

        define_method(:my_handler) do |result, phase|
          handler_called = true
          handler_result = result
          handler_phase = phase
          :continue
        end

        def user_prompt
          "test"
        end
      end.new

      config = { phases: [:input], custom_handler: :my_handler, on_flagged: :block }
      agent_with_handler.send(:handle_flagged_content, flagged_result, config, :input)

      expect(handler_called).to be true
      expect(handler_result).to eq(flagged_result)
      expect(handler_phase).to eq(:input)
    end

    it "skips default action when custom handler returns :continue" do
      agent_with_handler = create_agent_class do
        moderation :input, custom_handler: :my_handler

        def my_handler(_result, _phase)
          :continue
        end

        def user_prompt
          "test"
        end
      end.new

      config = { phases: [:input], custom_handler: :my_handler, on_flagged: :block }
      agent_with_handler.send(:handle_flagged_content, flagged_result, config, :input)

      # Should not be blocked because custom handler returned :continue
      expect(agent_with_handler.moderation_blocked?).to be false
    end
  end

  describe "#build_moderation_input (private)" do
    it "returns string prompt as-is" do
      agent = create_agent_class do
        def user_prompt
          "Hello world"
        end
      end.new

      expect(agent.send(:build_moderation_input)).to eq("Hello world")
    end

    it "joins array prompts with newlines" do
      agent = create_agent_class do
        def user_prompt
          ["First line", "Second line", "Third line"]
        end
      end.new

      expect(agent.send(:build_moderation_input)).to eq("First line\nSecond line\nThird line")
    end

    it "extracts content from hash prompts" do
      agent = create_agent_class do
        def user_prompt
          [{ content: "Message one" }, { content: "Message two" }]
        end
      end.new

      expect(agent.send(:build_moderation_input)).to eq("Message one\nMessage two")
    end

    it "handles mixed array of strings and hashes" do
      agent = create_agent_class do
        def user_prompt
          ["Plain text", { content: "Hash content" }]
        end
      end.new

      expect(agent.send(:build_moderation_input)).to eq("Plain text\nHash content")
    end
  end

  describe "#build_moderation_blocked_result (private)" do
    let(:agent) { agent_class.new(query: "test") }

    before do
      flagged_result = mock_moderation_result(flagged: true, categories: [:hate])
      agent.instance_variable_set(:@moderation_results, { input: flagged_result })
      agent.instance_variable_set(:@execution_started_at, Time.current - 1.second)
    end

    it "returns a Result with blocked status for input phase" do
      result = agent.send(:build_moderation_blocked_result, :input)

      expect(result).to be_a(RubyLLM::Agents::Result)
      expect(result.status).to eq(:input_moderation_blocked)
      expect(result.moderation_flagged?).to be true
      expect(result.moderation_phase).to eq(:input)
    end

    it "returns a Result with blocked status for output phase" do
      agent.instance_variable_set(:@moderation_results, { output: mock_moderation_result(flagged: true, categories: [:violence]) })
      result = agent.send(:build_moderation_blocked_result, :output)

      expect(result.status).to eq(:output_moderation_blocked)
      expect(result.moderation_phase).to eq(:output)
    end

    it "includes timing information" do
      result = agent.send(:build_moderation_blocked_result, :input)

      expect(result.started_at).to be_present
      expect(result.completed_at).to be_present
      expect(result.completed_at).to be >= result.started_at
    end

    it "sets zero costs for blocked results" do
      result = agent.send(:build_moderation_blocked_result, :input)

      expect(result.input_tokens).to eq(0)
      expect(result.output_tokens).to eq(0)
      expect(result.total_cost).to eq(0)
    end
  end

  describe "#default_moderation_model (private)" do
    it "returns configured default model" do
      agent = agent_class.new(query: "test")
      expect(agent.send(:default_moderation_model)).to eq("omni-moderation-latest")
    end
  end
end
