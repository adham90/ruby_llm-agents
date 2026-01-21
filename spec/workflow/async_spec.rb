# frozen_string_literal: true

require "rails_helper"

RSpec.describe RubyLLM::Agents::Async do
  before do
    RubyLLM::Agents.reset_configuration!
  end

  describe ".available?" do
    it "delegates to configuration" do
      allow(RubyLLM::Agents.configuration).to receive(:async_available?).and_return(true)

      expect(described_class.available?).to be true
    end

    it "returns false when async gem not loaded" do
      allow(RubyLLM::Agents.configuration).to receive(:async_available?).and_return(false)

      expect(described_class.available?).to be false
    end
  end

  describe ".async_context?" do
    it "delegates to configuration" do
      allow(RubyLLM::Agents.configuration).to receive(:async_context?).and_return(true)

      expect(described_class.async_context?).to be true
    end

    it "returns false when not in async context" do
      allow(RubyLLM::Agents.configuration).to receive(:async_context?).and_return(false)

      expect(described_class.async_context?).to be false
    end
  end

  describe ".sleep" do
    it "uses async sleep when in async context" do
      allow(described_class).to receive(:async_context?).and_return(true)

      mock_task = double("Async::Task")
      expect(mock_task).to receive(:sleep).with(1)
      allow(Async::Task).to receive(:current).and_return(mock_task)

      # This should use async sleep
      described_class.sleep(1)
    end if defined?(Async)

    it "uses Kernel.sleep when not in async context" do
      allow(described_class).to receive(:async_context?).and_return(false)

      expect(Kernel).to receive(:sleep).with(1)

      described_class.sleep(1)
    end
  end

  describe ".batch" do
    context "when async gem is not available" do
      before do
        allow(described_class).to receive(:available?).and_return(false)
      end

      it "raises error explaining async gem is required" do
        expect {
          described_class.batch([])
        }.to raise_error(/Async gem is required/)
      end
    end

    context "when async gem is available", if: defined?(Async) do
      let(:mock_agent_class) do
        Class.new do
          def self.call(**params)
            "result: #{params[:input]}"
          end
        end
      end

      before do
        allow(described_class).to receive(:available?).and_return(true)
        RubyLLM::Agents.configure do |config|
          config.async_max_concurrency = 5
        end
      end

      it "executes agents concurrently" do
        agents_with_params = [
          [mock_agent_class, { input: "a" }],
          [mock_agent_class, { input: "b" }]
        ]

        results = Async do
          described_class.batch(agents_with_params)
        end.wait

        expect(results).to eq(["result: a", "result: b"])
      end

      it "yields results with index when block provided" do
        agents_with_params = [
          [mock_agent_class, { input: "a" }],
          [mock_agent_class, { input: "b" }]
        ]

        collected = []
        Async do
          described_class.batch(agents_with_params) do |result, index|
            collected << [result, index]
          end
        end.wait

        expect(collected).to contain_exactly(
          ["result: a", 0],
          ["result: b", 1]
        )
      end

      it "respects max_concurrent limit" do
        RubyLLM::Agents.configure do |config|
          config.async_max_concurrency = 2
        end

        agents_with_params = Array.new(5) { [mock_agent_class, { input: "x" }] }

        # This should still complete with concurrency limited
        results = Async do
          described_class.batch(agents_with_params, max_concurrent: 2)
        end.wait

        expect(results.size).to eq(5)
      end
    end
  end

  describe ".each" do
    context "when async gem is not available" do
      before do
        allow(described_class).to receive(:available?).and_return(false)
      end

      it "raises error" do
        expect {
          described_class.each([1, 2, 3]) { |item| item }
        }.to raise_error(/Async gem is required/)
      end
    end

    it "raises error when no block given" do
      allow(described_class).to receive(:available?).and_return(true)

      expect {
        described_class.each([1, 2, 3])
      }.to raise_error(ArgumentError, "Block required")
    end

    context "when async gem is available", if: defined?(Async) do
      before do
        allow(described_class).to receive(:available?).and_return(true)
        RubyLLM::Agents.configure do |config|
          config.async_max_concurrency = 5
        end
      end

      it "processes items concurrently" do
        items = [1, 2, 3]

        results = Async do
          described_class.each(items) { |item| item * 2 }
        end.wait

        expect(results).to contain_exactly(2, 4, 6)
      end
    end
  end

  describe ".stream" do
    context "when async gem is not available" do
      before do
        allow(described_class).to receive(:available?).and_return(false)
      end

      it "raises error" do
        expect {
          described_class.stream([])
        }.to raise_error(/Async gem is required/)
      end
    end

    context "when async gem is available", if: defined?(Async) do
      let(:mock_agent_class) do
        Class.new do
          def self.call(**params)
            "result: #{params[:input]}"
          end
        end
      end

      before do
        allow(described_class).to receive(:available?).and_return(true)
        RubyLLM::Agents.configure do |config|
          config.async_max_concurrency = 5
        end
      end

      it "yields results as they complete" do
        agents_with_params = [
          [mock_agent_class, { input: "a" }],
          [mock_agent_class, { input: "b" }]
        ]

        collected = []
        results = Async do
          described_class.stream(agents_with_params) do |result, agent_class, index|
            collected << { result: result, agent: agent_class, index: index }
          end
        end.wait

        expect(collected.size).to eq(2)
        expect(results).to be_a(Hash)
        expect(results.values).to contain_exactly("result: a", "result: b")
      end

      it "returns results keyed by original index" do
        agents_with_params = [
          [mock_agent_class, { input: "a" }],
          [mock_agent_class, { input: "b" }]
        ]

        results = Async do
          described_class.stream(agents_with_params)
        end.wait

        expect(results[0]).to eq("result: a")
        expect(results[1]).to eq("result: b")
      end
    end
  end

  describe ".call_async" do
    context "when async gem is not available" do
      before do
        allow(described_class).to receive(:available?).and_return(false)
      end

      it "raises error" do
        mock_agent = Class.new
        expect {
          described_class.call_async(mock_agent, input: "test")
        }.to raise_error(/Async gem is required/)
      end
    end

    context "when async gem is available", if: defined?(Async) do
      let(:mock_agent_class) do
        Class.new do
          def self.call(**params)
            "result: #{params[:input]}"
          end
        end
      end

      before do
        allow(described_class).to receive(:available?).and_return(true)
      end

      it "returns an async task" do
        task = Async do
          described_class.call_async(mock_agent_class, input: "test")
        end.wait

        expect(task).to respond_to(:wait)
        result = Async { task.wait }.wait
        expect(result).to eq("result: test")
      end
    end
  end

  describe "ensure_async_available!" do
    # This is a private method but critical for behavior

    it "raises descriptive error when async not available" do
      allow(described_class).to receive(:available?).and_return(false)

      expect {
        described_class.batch([])
      }.to raise_error do |error|
        expect(error.message).to include("Async gem is required")
        expect(error.message).to include("gem 'async'")
        expect(error.message).to include("bundle install")
      end
    end
  end

  describe "configuration integration" do
    it "uses async_max_concurrency from configuration" do
      RubyLLM::Agents.configure do |config|
        config.async_max_concurrency = 10
      end

      expect(RubyLLM::Agents.configuration.async_max_concurrency).to eq(10)
    end
  end
end
