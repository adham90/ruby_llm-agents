# frozen_string_literal: true

require "rails_helper"

RSpec.describe RubyLLM::Agents::AttemptTracker do
  describe "#initialize" do
    it "starts with empty attempts" do
      tracker = described_class.new
      expect(tracker.attempts).to eq([])
    end
  end

  describe "#start_attempt" do
    it "records attempt start with model" do
      tracker = described_class.new
      tracker.start_attempt("gpt-4o")

      expect(tracker.instance_variable_get(:@current_attempt)).to include(
        model_id: "gpt-4o"
      )
      expect(tracker.instance_variable_get(:@current_attempt)[:started_at]).to be_present
    end

    it "instruments via ActiveSupport::Notifications" do
      tracker = described_class.new
      events = []

      subscription = ActiveSupport::Notifications.subscribe("ruby_llm_agents.attempt.start") do |*args|
        events << ActiveSupport::Notifications::Event.new(*args)
      end

      tracker.start_attempt("gpt-4o")

      ActiveSupport::Notifications.unsubscribe(subscription)

      expect(events.length).to eq(1)
      expect(events.first.payload[:model_id]).to eq("gpt-4o")
    end
  end

  describe "#complete_attempt" do
    let(:tracker) { described_class.new }
    let(:mock_response) do
      double(
        input_tokens: 100,
        output_tokens: 50,
        cached_tokens: 10,
        cache_creation_tokens: 5,
        model_id: "gpt-4o"
      )
    end

    context "on success" do
      it "records success metrics" do
        attempt = tracker.start_attempt("gpt-4o")
        tracker.complete_attempt(attempt, success: true, response: mock_response)

        completed = tracker.attempts.first
        expect(completed[:input_tokens]).to eq(100)
        expect(completed[:output_tokens]).to eq(50)
        expect(completed[:duration_ms]).to be_a(Numeric)
        expect(completed[:error_class]).to be_nil
      end

      it "calculates duration" do
        attempt = tracker.start_attempt("gpt-4o")
        sleep 0.01 # Small delay
        tracker.complete_attempt(attempt, success: true, response: mock_response)

        completed = tracker.attempts.first
        expect(completed[:duration_ms]).to be >= 10
      end
    end

    context "on error" do
      let(:error) { StandardError.new("API failed") }

      it "records error details" do
        attempt = tracker.start_attempt("gpt-4o")
        tracker.complete_attempt(attempt, success: false, error: error)

        completed = tracker.attempts.first
        expect(completed[:error_class]).to eq("StandardError")
        expect(completed[:error_message]).to eq("API failed")
      end
    end

    it "instruments via ActiveSupport::Notifications" do
      events = []

      subscription = ActiveSupport::Notifications.subscribe("ruby_llm_agents.attempt.finish") do |*args|
        events << ActiveSupport::Notifications::Event.new(*args)
      end

      attempt = tracker.start_attempt("gpt-4o")
      tracker.complete_attempt(attempt, success: true, response: mock_response)

      ActiveSupport::Notifications.unsubscribe(subscription)

      expect(events.length).to eq(1)
      expect(events.first.payload[:success]).to be true
    end
  end

  describe "#record_short_circuit" do
    it "records short-circuited attempt" do
      tracker = described_class.new
      tracker.record_short_circuit("gpt-4o")

      attempt = tracker.attempts.first
      expect(attempt[:model_id]).to eq("gpt-4o")
      expect(attempt[:short_circuited]).to be true
      expect(attempt[:error_class]).to include("CircuitBreakerOpenError")
    end

    it "has zero duration (no API call made)" do
      tracker = described_class.new
      tracker.record_short_circuit("gpt-4o")

      expect(tracker.attempts.first[:duration_ms]).to eq(0)
    end
  end

  describe "#attempts" do
    let(:mock_response) { double(input_tokens: 50, output_tokens: 25, cached_tokens: 0, cache_creation_tokens: 0, model_id: nil) }

    it "returns all recorded attempts" do
      tracker = described_class.new

      attempt1 = tracker.start_attempt("gpt-4o")
      tracker.complete_attempt(attempt1, success: false, error: StandardError.new("Error 1"))

      attempt2 = tracker.start_attempt("claude-3")
      tracker.complete_attempt(attempt2, success: true, response: mock_response)

      expect(tracker.attempts.length).to eq(2)
      expect(tracker.attempts[0][:model_id]).to eq("gpt-4o")
      expect(tracker.attempts[1][:model_id]).to eq("claude-3")
    end
  end

  describe "#total_input_tokens" do
    let(:mock_response1) { double(input_tokens: 100, output_tokens: 50, cached_tokens: 0, cache_creation_tokens: 0, model_id: nil) }
    let(:mock_response2) { double(input_tokens: 150, output_tokens: 75, cached_tokens: 0, cache_creation_tokens: 0, model_id: nil) }

    it "sums input tokens from all attempts" do
      tracker = described_class.new

      attempt1 = tracker.start_attempt("gpt-4o")
      tracker.complete_attempt(attempt1, success: true, response: mock_response1)

      attempt2 = tracker.start_attempt("gpt-4o")
      tracker.complete_attempt(attempt2, success: true, response: mock_response2)

      expect(tracker.total_input_tokens).to eq(250)
    end
  end

  describe "#total_output_tokens" do
    let(:mock_response1) { double(input_tokens: 100, output_tokens: 50, cached_tokens: 0, cache_creation_tokens: 0, model_id: nil) }
    let(:mock_response2) { double(input_tokens: 150, output_tokens: 75, cached_tokens: 0, cache_creation_tokens: 0, model_id: nil) }

    it "sums output tokens from all attempts" do
      tracker = described_class.new

      attempt1 = tracker.start_attempt("gpt-4o")
      tracker.complete_attempt(attempt1, success: true, response: mock_response1)

      attempt2 = tracker.start_attempt("gpt-4o")
      tracker.complete_attempt(attempt2, success: true, response: mock_response2)

      expect(tracker.total_output_tokens).to eq(125)
    end
  end

  describe "#total_duration_ms" do
    let(:mock_response) { double(input_tokens: 100, output_tokens: 50, cached_tokens: 0, cache_creation_tokens: 0, model_id: nil) }

    it "sums duration from all attempts" do
      tracker = described_class.new

      attempt1 = tracker.start_attempt("gpt-4o")
      sleep 0.01
      tracker.complete_attempt(attempt1, success: true, response: mock_response)

      attempt2 = tracker.start_attempt("gpt-4o")
      sleep 0.01
      tracker.complete_attempt(attempt2, success: true, response: mock_response)

      expect(tracker.total_duration_ms).to be >= 20
    end
  end

  describe "#successful_attempt" do
    let(:mock_response) { double(input_tokens: 50, output_tokens: 25, cached_tokens: 0, cache_creation_tokens: 0, model_id: nil) }

    it "returns the successful attempt" do
      tracker = described_class.new

      attempt1 = tracker.start_attempt("gpt-4o")
      tracker.complete_attempt(attempt1, success: false, error: StandardError.new)

      attempt2 = tracker.start_attempt("claude-3")
      tracker.complete_attempt(attempt2, success: true, response: mock_response)

      successful = tracker.successful_attempt
      expect(successful[:model_id]).to eq("claude-3")
      expect(successful[:error_class]).to be_nil
    end

    it "returns nil if no successful attempt" do
      tracker = described_class.new

      attempt = tracker.start_attempt("gpt-4o")
      tracker.complete_attempt(attempt, success: false, error: StandardError.new)

      expect(tracker.successful_attempt).to be_nil
    end
  end

  describe "#to_json_array" do
    let(:mock_response) { double(input_tokens: 50, output_tokens: 25, cached_tokens: 0, cache_creation_tokens: 0, model_id: nil) }

    it "returns data suitable for JSON persistence" do
      tracker = described_class.new

      attempt1 = tracker.start_attempt("gpt-4o")
      tracker.complete_attempt(attempt1, success: false, error: StandardError.new)

      attempt2 = tracker.start_attempt("claude-3")
      tracker.complete_attempt(attempt2, success: true, response: mock_response)

      data = tracker.to_json_array

      expect(data).to be_an(Array)
      expect(data.length).to eq(2)
      # Keys should be strings for JSON
      expect(data[0]).to have_key("model_id")
      expect(data[0]["model_id"]).to eq("gpt-4o")
    end
  end

  describe "#chosen_model_id" do
    let(:mock_response) { double(input_tokens: 50, output_tokens: 25, cached_tokens: 0, cache_creation_tokens: 0, model_id: "claude-3-sonnet") }

    it "returns the model ID from successful attempt" do
      tracker = described_class.new

      attempt1 = tracker.start_attempt("gpt-4o")
      tracker.complete_attempt(attempt1, success: false, error: StandardError.new)

      attempt2 = tracker.start_attempt("claude-3")
      tracker.complete_attempt(attempt2, success: true, response: mock_response)

      expect(tracker.chosen_model_id).to eq("claude-3-sonnet")
    end
  end
end
