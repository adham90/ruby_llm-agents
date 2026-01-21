# frozen_string_literal: true

require "rails_helper"

RSpec.describe RubyLLM::Agents::Instrumentation do
  # NOTE: The Instrumentation module (core/instrumentation.rb) is primarily used by
  # workflow orchestrators. Regular agents use the Pipeline::Middleware::Instrumentation
  # which has simpler tracking. These tests focus on the module behavior.

  describe "#mark_execution_failed!" do
    let(:execution) do
      RubyLLM::Agents::Execution.create!(
        agent_type: "TestAgent",
        agent_version: "1.0",
        model_id: "gpt-4",
        started_at: Time.current,
        status: "running"
      )
    end

    # Create a test class that exposes the private method
    let(:instrumentation_test_class) do
      Class.new do
        include RubyLLM::Agents::Instrumentation

        # Expose private method for testing
        def test_mark_execution_failed!(execution, error:)
          mark_execution_failed!(execution, error: error)
        end
      end
    end

    let(:test_instance) { instrumentation_test_class.new }

    it "marks execution as error" do
      error = StandardError.new("Test failure")
      test_instance.test_mark_execution_failed!(execution, error: error)

      execution.reload
      expect(execution.status).to eq("error")
    end

    it "records error class and message" do
      error = StandardError.new("Test failure")
      test_instance.test_mark_execution_failed!(execution, error: error)

      execution.reload
      expect(execution.error_class).to eq("StandardError")
      expect(execution.error_message).to include("Test failure")
    end

    it "sets completed_at" do
      error = StandardError.new("Test failure")
      test_instance.test_mark_execution_failed!(execution, error: error)

      execution.reload
      expect(execution.completed_at).to be_present
    end

    it "does nothing if execution is nil" do
      expect {
        test_instance.test_mark_execution_failed!(nil, error: StandardError.new("Test"))
      }.not_to raise_error
    end

    it "does nothing if execution status is not running" do
      execution.update!(status: "success")

      test_instance.test_mark_execution_failed!(execution, error: StandardError.new("Test"))

      execution.reload
      expect(execution.status).to eq("success")
    end
  end

  describe "AttemptTracker" do
    describe ".new" do
      it "initializes with empty attempts" do
        tracker = RubyLLM::Agents::AttemptTracker.new
        expect(tracker.attempts_count).to eq(0)
      end
    end

    describe "#start_attempt and #complete_attempt" do
      let(:tracker) { RubyLLM::Agents::AttemptTracker.new }

      it "records successful attempts" do
        attempt = tracker.start_attempt("gpt-4")
        mock_resp = double("Response", input_tokens: 100, output_tokens: 50, cached_tokens: 0, cache_creation_tokens: 0, model_id: "gpt-4")
        tracker.complete_attempt(attempt, success: true, response: mock_resp)

        expect(tracker.attempts_count).to eq(1)
        expect(tracker.chosen_model_id).to eq("gpt-4")
      end

      it "records failed attempts" do
        attempt = tracker.start_attempt("gpt-4")
        error = StandardError.new("Test error")
        tracker.complete_attempt(attempt, success: false, error: error)

        expect(tracker.attempts_count).to eq(1)
        expect(tracker.failed_attempts.size).to eq(1)
      end

      it "aggregates token usage" do
        # First attempt - failed
        attempt1 = tracker.start_attempt("gpt-4")
        mock_resp1 = double("Response", input_tokens: 50, output_tokens: 25, cached_tokens: 0, cache_creation_tokens: 0, model_id: "gpt-4")
        tracker.complete_attempt(attempt1, success: false, response: mock_resp1, error: StandardError.new("Fail"))

        # Second attempt - success
        attempt2 = tracker.start_attempt("gpt-3.5-turbo")
        mock_resp2 = double("Response", input_tokens: 100, output_tokens: 50, cached_tokens: 0, cache_creation_tokens: 0, model_id: "gpt-3.5-turbo")
        tracker.complete_attempt(attempt2, success: true, response: mock_resp2)

        expect(tracker.total_input_tokens).to eq(150)
        expect(tracker.total_output_tokens).to eq(75)
        expect(tracker.total_tokens).to eq(225)
      end
    end

    describe "#used_fallback?" do
      let(:tracker) { RubyLLM::Agents::AttemptTracker.new }

      it "returns false with single attempt" do
        attempt = tracker.start_attempt("gpt-4")
        mock_resp = double("Response", input_tokens: 100, output_tokens: 50, cached_tokens: 0, cache_creation_tokens: 0, model_id: "gpt-4")
        tracker.complete_attempt(attempt, success: true, response: mock_resp)

        expect(tracker.used_fallback?).to be false
      end

      it "returns true with multiple attempts using different models" do
        attempt1 = tracker.start_attempt("gpt-4")
        tracker.complete_attempt(attempt1, success: false, error: StandardError.new("Fail"))

        attempt2 = tracker.start_attempt("gpt-3.5-turbo")
        mock_resp = double("Response", input_tokens: 100, output_tokens: 50, cached_tokens: 0, cache_creation_tokens: 0, model_id: "gpt-3.5-turbo")
        tracker.complete_attempt(attempt2, success: true, response: mock_resp)

        expect(tracker.used_fallback?).to be true
      end
    end

    describe "#to_json_array" do
      let(:tracker) { RubyLLM::Agents::AttemptTracker.new }

      it "returns array of attempt hashes with string keys" do
        attempt = tracker.start_attempt("gpt-4")
        mock_resp = double("Response", input_tokens: 100, output_tokens: 50, cached_tokens: 0, cache_creation_tokens: 0, model_id: "gpt-4")
        tracker.complete_attempt(attempt, success: true, response: mock_resp)

        json = tracker.to_json_array
        expect(json).to be_an(Array)
        expect(json.first["model_id"]).to eq("gpt-4")
        expect(json.first).to have_key("started_at")
        expect(json.first).to have_key("completed_at")
      end
    end

    describe "#record_short_circuit" do
      let(:tracker) { RubyLLM::Agents::AttemptTracker.new }

      it "records short-circuited attempt" do
        tracker.record_short_circuit("gpt-4")

        expect(tracker.attempts_count).to eq(1)
        expect(tracker.short_circuited_count).to eq(1)
        expect(tracker.failed_attempts.first[:short_circuited]).to be true
      end
    end

    describe "#successful_attempt" do
      let(:tracker) { RubyLLM::Agents::AttemptTracker.new }

      it "returns nil when no successful attempt" do
        attempt = tracker.start_attempt("gpt-4")
        tracker.complete_attempt(attempt, success: false, error: StandardError.new("Fail"))

        expect(tracker.successful_attempt).to be_nil
      end

      it "returns the successful attempt" do
        attempt = tracker.start_attempt("gpt-4")
        mock_resp = double("Response", input_tokens: 100, output_tokens: 50, cached_tokens: 0, cache_creation_tokens: 0, model_id: "gpt-4")
        tracker.complete_attempt(attempt, success: true, response: mock_resp)

        expect(tracker.successful_attempt).to be_present
        expect(tracker.successful_attempt[:model_id]).to eq("gpt-4")
      end
    end

    describe "#last_failed_attempt" do
      let(:tracker) { RubyLLM::Agents::AttemptTracker.new }

      it "returns nil when no failed attempts" do
        attempt = tracker.start_attempt("gpt-4")
        mock_resp = double("Response", input_tokens: 100, output_tokens: 50, cached_tokens: 0, cache_creation_tokens: 0, model_id: "gpt-4")
        tracker.complete_attempt(attempt, success: true, response: mock_resp)

        expect(tracker.last_failed_attempt).to be_nil
      end

      it "returns the last failed attempt" do
        attempt1 = tracker.start_attempt("gpt-4")
        tracker.complete_attempt(attempt1, success: false, error: StandardError.new("First fail"))

        attempt2 = tracker.start_attempt("gpt-3.5-turbo")
        tracker.complete_attempt(attempt2, success: false, error: StandardError.new("Second fail"))

        expect(tracker.last_failed_attempt[:model_id]).to eq("gpt-3.5-turbo")
        expect(tracker.last_failed_attempt[:error_message]).to include("Second fail")
      end
    end

    describe "#total_cached_tokens" do
      let(:tracker) { RubyLLM::Agents::AttemptTracker.new }

      it "sums cached tokens from all attempts" do
        attempt1 = tracker.start_attempt("gpt-4")
        mock_resp1 = double("Response", input_tokens: 100, output_tokens: 50, cached_tokens: 20, cache_creation_tokens: 5, model_id: "gpt-4")
        tracker.complete_attempt(attempt1, success: true, response: mock_resp1)

        expect(tracker.total_cached_tokens).to eq(20)
      end
    end

    describe "#total_duration_ms" do
      let(:tracker) { RubyLLM::Agents::AttemptTracker.new }

      it "sums duration from all attempts" do
        attempt = tracker.start_attempt("gpt-4")
        # Allow some time to pass
        sleep(0.01)
        mock_resp = double("Response", input_tokens: 100, output_tokens: 50, cached_tokens: 0, cache_creation_tokens: 0, model_id: "gpt-4")
        tracker.complete_attempt(attempt, success: true, response: mock_resp)

        expect(tracker.total_duration_ms).to be >= 0
      end
    end

    describe "#failed_attempts_count" do
      let(:tracker) { RubyLLM::Agents::AttemptTracker.new }

      it "counts failed attempts" do
        attempt1 = tracker.start_attempt("gpt-4")
        tracker.complete_attempt(attempt1, success: false, error: StandardError.new("Fail 1"))

        attempt2 = tracker.start_attempt("gpt-3.5-turbo")
        mock_resp = double("Response", input_tokens: 100, output_tokens: 50, cached_tokens: 0, cache_creation_tokens: 0, model_id: "gpt-3.5-turbo")
        tracker.complete_attempt(attempt2, success: true, response: mock_resp)

        expect(tracker.failed_attempts_count).to eq(1)
        expect(tracker.attempts_count).to eq(2)
      end
    end
  end

  # Test helper methods on the Instrumentation module
  describe "helper methods" do
    # Create a test class that includes Instrumentation and exposes private methods
    let(:test_class) do
      Class.new do
        include RubyLLM::Agents::Instrumentation

        attr_accessor :options, :accumulated_tool_calls

        def self.name
          "TestInstrumentationAgent"
        end

        def self.version
          "1.0.0"
        end

        def self.streaming
          false
        end

        def initialize
          @options = {}
          @accumulated_tool_calls = []
        end

        def model
          "gpt-4"
        end

        def temperature
          0.7
        end

        def system_prompt
          "You are a test assistant."
        end

        def user_prompt
          "Hello world"
        end

        def resolved_messages
          [{ role: :user, content: "Hello" }]
        end

        # Expose private methods for testing
        def test_safe_response_value(response, method, default = nil)
          safe_response_value(response, method, default)
        end

        def test_safe_extract_response_data(response)
          safe_extract_response_data(response)
        end

        def test_safe_extract_finish_reason(response)
          safe_extract_finish_reason(response)
        end

        def test_safe_extract_thinking_data(response)
          safe_extract_thinking_data(response)
        end

        def test_determine_fallback_reason(attempt_tracker)
          determine_fallback_reason(attempt_tracker)
        end

        def test_retryable_error?(error)
          retryable_error?(error)
        end

        def test_rate_limit_error?(error)
          rate_limit_error?(error)
        end

        def test_messages_summary
          messages_summary
        end

        def test_redacted_parameters
          redacted_parameters
        end

        def test_execution_metadata
          execution_metadata
        end

        def test_safe_system_prompt
          safe_system_prompt
        end

        def test_safe_user_prompt
          safe_user_prompt
        end

        def test_capture_response(response)
          capture_response(response)
        end
      end
    end

    let(:test_instance) { test_class.new }

    describe "#capture_response" do
      it "stores the response" do
        mock_response = double("Response", content: "Hello")
        result = test_instance.test_capture_response(mock_response)

        expect(result).to eq(mock_response)
      end
    end

    describe "#safe_response_value" do
      it "returns value when method exists" do
        mock_response = double("Response", input_tokens: 100)
        result = test_instance.test_safe_response_value(mock_response, :input_tokens)

        expect(result).to eq(100)
      end

      it "returns default when method does not exist" do
        mock_response = double("Response")
        result = test_instance.test_safe_response_value(mock_response, :nonexistent, 42)

        expect(result).to eq(42)
      end

      it "returns default when method raises" do
        mock_response = double("Response")
        allow(mock_response).to receive(:input_tokens).and_raise(StandardError.new("Error"))
        result = test_instance.test_safe_response_value(mock_response, :input_tokens, 0)

        expect(result).to eq(0)
      end
    end

    describe "#safe_extract_response_data" do
      it "returns empty hash when response does not respond to input_tokens" do
        mock_response = double("Response")
        result = test_instance.test_safe_extract_response_data(mock_response)

        expect(result).to eq({})
      end

      it "extracts token data from response" do
        mock_response = double("Response",
          input_tokens: 100,
          output_tokens: 50,
          cached_tokens: 10,
          cache_creation_tokens: 5,
          model_id: "gpt-4",
          finish_reason: "stop",
          content: "Hello",
          thinking: nil,
          tool_calls: nil)
        allow(mock_response).to receive(:respond_to?).and_return(true)

        result = test_instance.test_safe_extract_response_data(mock_response)

        expect(result[:input_tokens]).to eq(100)
        expect(result[:output_tokens]).to eq(50)
        expect(result[:cached_tokens]).to eq(10)
        expect(result[:model_id]).to eq("gpt-4")
      end
    end

    describe "#safe_extract_finish_reason" do
      it "returns nil when no finish reason" do
        mock_response = double("Response")
        allow(mock_response).to receive(:respond_to?).and_return(false)

        result = test_instance.test_safe_extract_finish_reason(mock_response)

        expect(result).to be_nil
      end

      it "normalizes 'stop' reasons" do
        %w[stop end_turn stop_sequence].each do |reason|
          mock_response = double("Response", finish_reason: reason)
          allow(mock_response).to receive(:respond_to?).and_return(true)

          result = test_instance.test_safe_extract_finish_reason(mock_response)

          expect(result).to eq("stop")
        end
      end

      it "normalizes 'length' reasons" do
        %w[length max_tokens].each do |reason|
          mock_response = double("Response", finish_reason: reason)
          allow(mock_response).to receive(:respond_to?).and_return(true)

          result = test_instance.test_safe_extract_finish_reason(mock_response)

          expect(result).to eq("length")
        end
      end

      it "normalizes 'content_filter' reasons" do
        %w[content_filter safety].each do |reason|
          mock_response = double("Response", finish_reason: reason)
          allow(mock_response).to receive(:respond_to?).and_return(true)

          result = test_instance.test_safe_extract_finish_reason(mock_response)

          expect(result).to eq("content_filter")
        end
      end

      it "normalizes 'tool_calls' reasons" do
        %w[tool_calls tool_use function_call].each do |reason|
          mock_response = double("Response", finish_reason: reason)
          allow(mock_response).to receive(:respond_to?).and_return(true)

          result = test_instance.test_safe_extract_finish_reason(mock_response)

          expect(result).to eq("tool_calls")
        end
      end

      it "returns 'other' for unknown reasons" do
        mock_response = double("Response", finish_reason: "unknown_reason")
        allow(mock_response).to receive(:respond_to?).and_return(true)

        result = test_instance.test_safe_extract_finish_reason(mock_response)

        expect(result).to eq("other")
      end

      it "uses stop_reason as fallback" do
        mock_response = double("Response")
        allow(mock_response).to receive(:respond_to?).with(:finish_reason).and_return(false)
        allow(mock_response).to receive(:respond_to?).with(:stop_reason).and_return(true)
        allow(mock_response).to receive(:stop_reason).and_return("stop")

        result = test_instance.test_safe_extract_finish_reason(mock_response)

        expect(result).to eq("stop")
      end
    end

    describe "#safe_extract_thinking_data" do
      it "returns empty hash when no thinking" do
        mock_response = double("Response")
        allow(mock_response).to receive(:respond_to?).and_return(false)

        result = test_instance.test_safe_extract_thinking_data(mock_response)

        expect(result).to eq({})
      end

      it "extracts thinking data from object" do
        thinking = double("Thinking", text: "Thinking...", signature: "sig123", tokens: 50)
        mock_response = double("Response", thinking: thinking)
        allow(mock_response).to receive(:respond_to?).with(:thinking).and_return(true)

        result = test_instance.test_safe_extract_thinking_data(mock_response)

        expect(result[:thinking_text]).to eq("Thinking...")
        expect(result[:thinking_signature]).to eq("sig123")
        expect(result[:thinking_tokens]).to eq(50)
      end

      it "extracts thinking data from hash" do
        thinking = { text: "Thinking...", signature: "sig456", tokens: 75 }
        mock_response = double("Response", thinking: thinking)
        allow(mock_response).to receive(:respond_to?).with(:thinking).and_return(true)

        result = test_instance.test_safe_extract_thinking_data(mock_response)

        expect(result[:thinking_text]).to eq("Thinking...")
        expect(result[:thinking_signature]).to eq("sig456")
        expect(result[:thinking_tokens]).to eq(75)
      end
    end

    describe "#determine_fallback_reason" do
      let(:tracker) { RubyLLM::Agents::AttemptTracker.new }

      it "returns 'other' when no failed attempts" do
        result = test_instance.test_determine_fallback_reason(tracker)

        expect(result).to eq("other")
      end

      it "returns 'rate_limit' for rate limit errors" do
        attempt = tracker.start_attempt("gpt-4")
        error = Class.new(StandardError) { def self.name; "RateLimitError"; end }.new("Rate limited")
        tracker.complete_attempt(attempt, success: false, error: error)

        result = test_instance.test_determine_fallback_reason(tracker)

        expect(result).to eq("rate_limit")
      end

      it "returns 'timeout' for timeout errors" do
        attempt = tracker.start_attempt("gpt-4")
        error = Timeout::Error.new("Connection timed out")
        tracker.complete_attempt(attempt, success: false, error: error)

        result = test_instance.test_determine_fallback_reason(tracker)

        expect(result).to eq("timeout")
      end

      it "returns 'safety' for content filter errors" do
        attempt = tracker.start_attempt("gpt-4")
        error = Class.new(StandardError) { def self.name; "ContentFilterError"; end }.new("Blocked")
        tracker.complete_attempt(attempt, success: false, error: error)

        result = test_instance.test_determine_fallback_reason(tracker)

        expect(result).to eq("safety")
      end

      it "returns 'price_limit' for budget exceeded errors" do
        attempt = tracker.start_attempt("gpt-4")
        error = Class.new(StandardError) { def self.name; "BudgetExceededError"; end }.new("Over budget")
        tracker.complete_attempt(attempt, success: false, error: error)

        result = test_instance.test_determine_fallback_reason(tracker)

        expect(result).to eq("price_limit")
      end

      it "returns 'error' for generic errors" do
        attempt = tracker.start_attempt("gpt-4")
        error = StandardError.new("Some error")
        tracker.complete_attempt(attempt, success: false, error: error)

        result = test_instance.test_determine_fallback_reason(tracker)

        expect(result).to eq("error")
      end
    end

    describe "#retryable_error?" do
      it "returns false for nil" do
        result = test_instance.test_retryable_error?(nil)

        expect(result).to be false
      end

      it "returns true for timeout errors" do
        error = Timeout::Error.new("Timed out")
        result = test_instance.test_retryable_error?(error)

        expect(result).to be true
      end

      it "returns true for connection errors" do
        error = Class.new(StandardError) { def self.name; "ConnectionError"; end }.new("Connection failed")
        result = test_instance.test_retryable_error?(error)

        expect(result).to be true
      end

      it "returns true for rate limit errors" do
        error = Class.new(StandardError) { def self.name; "RateLimitError"; end }.new("Rate limited")
        result = test_instance.test_retryable_error?(error)

        expect(result).to be true
      end

      it "returns true for service unavailable errors" do
        error = Class.new(StandardError) { def self.name; "ServiceUnavailableError"; end }.new("Unavailable")
        result = test_instance.test_retryable_error?(error)

        expect(result).to be true
      end

      it "returns false for generic errors" do
        error = StandardError.new("Generic error")
        result = test_instance.test_retryable_error?(error)

        expect(result).to be false
      end
    end

    describe "#rate_limit_error?" do
      it "returns false for nil" do
        result = test_instance.test_rate_limit_error?(nil)

        expect(result).to be false
      end

      it "returns true for RateLimitError class" do
        error = Class.new(StandardError) { def self.name; "RateLimitError"; end }.new("Rate limited")
        result = test_instance.test_rate_limit_error?(error)

        expect(result).to be true
      end

      it "returns true for TooManyRequests class" do
        error = Class.new(StandardError) { def self.name; "TooManyRequestsError"; end }.new("Too many requests")
        result = test_instance.test_rate_limit_error?(error)

        expect(result).to be true
      end

      it "returns true when message contains 'rate limit'" do
        error = StandardError.new("You have exceeded the rate limit")
        result = test_instance.test_rate_limit_error?(error)

        expect(result).to be true
      end

      it "returns true when message contains 'too many requests'" do
        error = StandardError.new("Error: too many requests. Please retry later.")
        result = test_instance.test_rate_limit_error?(error)

        expect(result).to be true
      end

      it "returns false for generic errors" do
        error = StandardError.new("Something went wrong")
        result = test_instance.test_rate_limit_error?(error)

        expect(result).to be false
      end
    end

    describe "#messages_summary" do
      it "returns empty hash when no messages" do
        instance = test_class.new
        allow(instance).to receive(:resolved_messages).and_return([])

        result = instance.test_messages_summary

        expect(result).to eq({})
      end

      it "returns first message when only one" do
        instance = test_class.new
        allow(instance).to receive(:resolved_messages).and_return([
          { role: :user, content: "Hello" }
        ])

        result = instance.test_messages_summary

        expect(result[:first][:role]).to eq("user")
        expect(result[:first][:content]).to include("Hello")
        expect(result[:last]).to be_nil
      end

      it "returns first and last when multiple messages" do
        instance = test_class.new
        allow(instance).to receive(:resolved_messages).and_return([
          { role: :user, content: "Hello" },
          { role: :assistant, content: "Hi there" },
          { role: :user, content: "How are you?" }
        ])

        result = instance.test_messages_summary

        expect(result[:first][:role]).to eq("user")
        expect(result[:first][:content]).to include("Hello")
        expect(result[:last][:role]).to eq("user")
        expect(result[:last][:content]).to include("How are you?")
      end

      it "truncates long content" do
        instance = test_class.new
        long_content = "x" * 1000
        allow(instance).to receive(:resolved_messages).and_return([
          { role: :user, content: long_content }
        ])

        result = instance.test_messages_summary

        expect(result[:first][:content].length).to be <= 503 # 500 + "..."
      end
    end

    describe "#redacted_parameters" do
      it "excludes skip_cache and dry_run" do
        test_instance.options = { query: "test", skip_cache: true, dry_run: true }
        result = test_instance.test_redacted_parameters

        expect(result).not_to have_key(:skip_cache)
        expect(result).not_to have_key(:dry_run)
        expect(result).to have_key(:query)
      end
    end

    describe "#execution_metadata" do
      it "returns empty hash by default" do
        result = test_instance.test_execution_metadata

        expect(result).to eq({})
      end
    end

    describe "#safe_system_prompt" do
      it "returns the system prompt" do
        result = test_instance.test_safe_system_prompt

        expect(result).to eq("You are a test assistant.")
      end

      it "returns nil when system_prompt is not defined" do
        instance = test_class.new
        allow(instance).to receive(:respond_to?).with(:system_prompt).and_return(false)

        result = instance.test_safe_system_prompt

        expect(result).to be_nil
      end
    end

    describe "#safe_user_prompt" do
      it "returns the user prompt" do
        result = test_instance.test_safe_user_prompt

        expect(result).to eq("Hello world")
      end
    end
  end
end
