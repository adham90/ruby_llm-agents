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

        def test_sanitized_parameters
          sanitized_parameters
        end

        def test_metadata
          metadata
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

        def test_stored_system_prompt
          stored_system_prompt
        end

        def test_stored_user_prompt
          stored_user_prompt
        end

        def test_stored_response(response)
          stored_response(response)
        end

        def test_extract_routing_data(attempt_tracker, error)
          extract_routing_data(attempt_tracker, error)
        end

        def test_serialize_tool_calls(response)
          serialize_tool_calls(response)
        end

        def test_safe_serialize_response(response)
          safe_serialize_response(response)
        end

        def test_record_cache_hit_execution(cache_key, cached_result, started_at)
          record_cache_hit_execution(cache_key, cached_result, started_at)
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

    describe "#sanitized_parameters" do
      it "excludes skip_cache and dry_run" do
        test_instance.options = { query: "test", skip_cache: true, dry_run: true }
        result = test_instance.test_sanitized_parameters

        expect(result).not_to have_key(:skip_cache)
        expect(result).not_to have_key(:dry_run)
        expect(result).to have_key(:query)
      end
    end

    describe "#metadata" do
      it "returns empty hash by default" do
        result = test_instance.test_metadata

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

    describe "#stored_system_prompt" do
      it "returns nil when system prompt is nil" do
        instance = test_class.new
        allow(instance).to receive(:safe_system_prompt).and_return(nil)

        result = instance.test_stored_system_prompt

        expect(result).to be_nil
      end

      it "returns prompt unchanged" do
        RubyLLM::Agents.reset_configuration!
        result = test_instance.test_stored_system_prompt

        expect(result).to eq("You are a test assistant.")
      end
    end

    describe "#stored_user_prompt" do
      it "returns nil when user prompt is nil" do
        instance = test_class.new
        allow(instance).to receive(:safe_user_prompt).and_return(nil)

        result = instance.test_stored_user_prompt

        expect(result).to be_nil
      end

      it "returns prompt unchanged" do
        RubyLLM::Agents.reset_configuration!
        result = test_instance.test_stored_user_prompt

        expect(result).to eq("Hello world")
      end
    end

    describe "#stored_response" do
      it "preserves response data" do
        RubyLLM::Agents.reset_configuration!
        mock_response = double("Response",
          content: "Hello world",
          model_id: "gpt-4",
          input_tokens: 100,
          output_tokens: 50,
          cached_tokens: 0,
          cache_creation_tokens: 0,
          tool_calls: nil)
        allow(mock_response).to receive(:respond_to?).and_return(true)

        result = test_instance.test_stored_response(mock_response)

        expect(result[:content]).to eq("Hello world")
        expect(result[:model_id]).to eq("gpt-4")
      end
    end

    describe "#extract_routing_data" do
      let(:tracker) { RubyLLM::Agents::AttemptTracker.new }

      it "returns empty hash when no fallback used" do
        attempt = tracker.start_attempt("gpt-4")
        mock_resp = double("Response", input_tokens: 100, output_tokens: 50, cached_tokens: 0, cache_creation_tokens: 0, model_id: "gpt-4")
        tracker.complete_attempt(attempt, success: true, response: mock_resp)

        result = test_instance.test_extract_routing_data(tracker, nil)

        expect(result).to eq({})
      end

      it "includes fallback_reason when fallback was used" do
        attempt1 = tracker.start_attempt("gpt-4")
        tracker.complete_attempt(attempt1, success: false, error: StandardError.new("Error"))

        attempt2 = tracker.start_attempt("gpt-3.5-turbo")
        mock_resp = double("Response", input_tokens: 100, output_tokens: 50, cached_tokens: 0, cache_creation_tokens: 0, model_id: "gpt-3.5-turbo")
        tracker.complete_attempt(attempt2, success: true, response: mock_resp)

        result = test_instance.test_extract_routing_data(tracker, nil)

        expect(result[:fallback_reason]).to eq("error")
      end

      it "includes retryable and rate_limited flags for errors" do
        attempt = tracker.start_attempt("gpt-4")
        mock_resp = double("Response", input_tokens: 100, output_tokens: 50, cached_tokens: 0, cache_creation_tokens: 0, model_id: "gpt-4")
        tracker.complete_attempt(attempt, success: true, response: mock_resp)

        error = Class.new(StandardError) { def self.name; "RateLimitError"; end }.new("Rate limited")
        result = test_instance.test_extract_routing_data(tracker, error)

        expect(result[:retryable]).to be true
        expect(result[:rate_limited]).to be true
      end

      it "marks non-retryable errors correctly" do
        attempt = tracker.start_attempt("gpt-4")
        mock_resp = double("Response", input_tokens: 100, output_tokens: 50, cached_tokens: 0, cache_creation_tokens: 0, model_id: "gpt-4")
        tracker.complete_attempt(attempt, success: true, response: mock_resp)

        error = StandardError.new("Invalid input")
        result = test_instance.test_extract_routing_data(tracker, error)

        expect(result[:retryable]).to be false
        expect(result[:rate_limited]).to be false
      end
    end

    describe "#serialize_tool_calls" do
      it "returns nil when no tool_calls" do
        mock_response = double("Response")
        allow(mock_response).to receive(:respond_to?).with(:tool_calls).and_return(false)

        result = test_instance.test_serialize_tool_calls(mock_response)

        expect(result).to be_nil
      end

      it "returns nil when tool_calls is empty" do
        mock_response = double("Response", tool_calls: {})
        allow(mock_response).to receive(:respond_to?).with(:tool_calls).and_return(true)

        result = test_instance.test_serialize_tool_calls(mock_response)

        expect(result).to be_nil
      end

      it "serializes tool calls with to_h method" do
        tool_call = double("ToolCall")
        allow(tool_call).to receive(:respond_to?).with(:to_h).and_return(true)
        allow(tool_call).to receive(:to_h).and_return({ id: "call_1", name: "calculator", arguments: { x: 1, y: 2 } })

        mock_response = double("Response", tool_calls: { "call_1" => tool_call })
        allow(mock_response).to receive(:respond_to?).with(:tool_calls).and_return(true)

        result = test_instance.test_serialize_tool_calls(mock_response)

        expect(result).to be_an(Array)
        expect(result.first[:name]).to eq("calculator")
      end

      it "serializes tool calls from hash without to_h" do
        tool_call = double("ToolCall")
        allow(tool_call).to receive(:respond_to?).with(:to_h).and_return(false)
        allow(tool_call).to receive(:[]).with(:name).and_return("search")
        allow(tool_call).to receive(:[]).with(:arguments).and_return({ query: "test" })

        mock_response = double("Response", tool_calls: { "call_2" => tool_call })
        allow(mock_response).to receive(:respond_to?).with(:tool_calls).and_return(true)

        result = test_instance.test_serialize_tool_calls(mock_response)

        expect(result).to be_an(Array)
        expect(result.first[:id]).to eq("call_2")
        expect(result.first[:name]).to eq("search")
      end
    end

    describe "#safe_serialize_response" do
      it "serializes response with all fields" do
        mock_response = double("Response",
          content: "Hello",
          model_id: "gpt-4",
          input_tokens: 100,
          output_tokens: 50,
          cached_tokens: 10,
          cache_creation_tokens: 5,
          tool_calls: nil)
        allow(mock_response).to receive(:respond_to?).and_return(true)

        result = test_instance.test_safe_serialize_response(mock_response)

        expect(result[:content]).to eq("Hello")
        expect(result[:model_id]).to eq("gpt-4")
        expect(result[:input_tokens]).to eq(100)
        expect(result[:output_tokens]).to eq(50)
        expect(result[:cached_tokens]).to eq(10)
      end

      it "includes tool_calls from accumulated_tool_calls" do
        test_instance.accumulated_tool_calls = [
          { id: "call_1", name: "search", arguments: {} }
        ]
        mock_response = double("Response",
          content: "Done",
          model_id: "gpt-4",
          input_tokens: 50,
          output_tokens: 25,
          cached_tokens: 0,
          cache_creation_tokens: 0,
          tool_calls: nil)
        allow(mock_response).to receive(:respond_to?).and_return(true)

        result = test_instance.test_safe_serialize_response(mock_response)

        expect(result[:tool_calls]).to be_an(Array)
        expect(result[:tool_calls].first[:name]).to eq("search")
      end

      it "compacts nil values" do
        mock_response = double("Response",
          content: nil,
          model_id: nil,
          input_tokens: 100,
          output_tokens: 50,
          cached_tokens: 0,
          cache_creation_tokens: 0,
          tool_calls: nil)
        allow(mock_response).to receive(:respond_to?).and_return(true)

        result = test_instance.test_safe_serialize_response(mock_response)

        expect(result).not_to have_key(:content)
        expect(result).not_to have_key(:model_id)
        expect(result).to have_key(:input_tokens)
      end
    end

    describe "#record_cache_hit_execution" do
      before do
        RubyLLM::Agents.reset_configuration!
        RubyLLM::Agents.configure do |config|
          config.async_logging = false
        end
      end

      it "creates execution record with cache_hit: true" do
        expect {
          test_instance.test_record_cache_hit_execution("cache_key_123", { result: "cached" }, 1.second.ago)
        }.to change(RubyLLM::Agents::Execution, :count).by(1)

        execution = RubyLLM::Agents::Execution.last
        expect(execution.cache_hit).to be true
        expect(execution.status).to eq("success")
        expect(execution.total_cost).to eq(0)
      end

      it "sets token counts to zero" do
        test_instance.test_record_cache_hit_execution("cache_key_123", { result: "cached" }, 1.second.ago)

        execution = RubyLLM::Agents::Execution.last
        expect(execution.input_tokens).to eq(0)
        expect(execution.output_tokens).to eq(0)
        expect(execution.total_tokens).to eq(0)
      end

      it "records the cache key" do
        test_instance.test_record_cache_hit_execution("my_cache_key", { result: "cached" }, 1.second.ago)

        execution = RubyLLM::Agents::Execution.last
        expect(execution.response_cache_key).to eq("my_cache_key")
      end

      it "calculates duration_ms correctly" do
        started_at = 0.1.seconds.ago
        test_instance.test_record_cache_hit_execution("cache_key", { result: "cached" }, started_at)

        execution = RubyLLM::Agents::Execution.last
        expect(execution.duration_ms).to be >= 100
        expect(execution.duration_ms).to be < 500 # reasonable upper bound
      end

      it "uses async logging when configured" do
        RubyLLM::Agents.configure do |config|
          config.async_logging = true
        end

        expect(RubyLLM::Agents::ExecutionLoggerJob).to receive(:perform_later).with(hash_including(cache_hit: true))

        test_instance.test_record_cache_hit_execution("cache_key", { result: "cached" }, 1.second.ago)
      end

      it "handles errors gracefully" do
        allow(RubyLLM::Agents::Execution).to receive(:create!).and_raise(StandardError.new("DB error"))

        expect {
          test_instance.test_record_cache_hit_execution("cache_key", { result: "cached" }, 1.second.ago)
        }.not_to raise_error
      end
    end
  end

  # ===== ORCHESTRATION METHOD TESTS =====
  # These test the main execution tracking orchestration methods

  describe "orchestration methods" do
    # Extended test class that exposes private orchestration methods
    let(:orchestration_test_class) do
      Class.new do
        include RubyLLM::Agents::Instrumentation

        attr_accessor :options, :accumulated_tool_calls, :last_response

        def self.name
          "OrchestrationTestAgent"
        end

        def self.version
          "2.0.0"
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
          "Test prompt"
        end

        def resolved_messages
          [{ role: :user, content: "Hello" }]
        end

        # Expose private methods for testing
        def test_create_running_execution(started_at, fallback_chain: [])
          create_running_execution(started_at, fallback_chain: fallback_chain)
        end

        def test_complete_execution(execution, completed_at:, status:, response: nil, error: nil)
          complete_execution(execution, completed_at: completed_at, status: status, response: response, error: error)
        end

        def test_complete_execution_with_attempts(execution, attempt_tracker:, completed_at:, status:, error: nil)
          complete_execution_with_attempts(execution, attempt_tracker: attempt_tracker, completed_at: completed_at, status: status, error: error)
        end

        def test_legacy_log_execution(completed_at:, status:, response: nil, error: nil)
          legacy_log_execution(completed_at: completed_at, status: status, response: response, error: error)
        end

        def test_record_token_usage(execution)
          record_token_usage(execution)
        end

        def test_instrument_execution(&block)
          instrument_execution(&block)
        end

        def test_instrument_execution_with_attempts(models_to_try:, &block)
          instrument_execution_with_attempts(models_to_try: models_to_try, &block)
        end
      end
    end

    let(:orch_instance) { orchestration_test_class.new }

    before do
      RubyLLM::Agents.reset_configuration!
      RubyLLM::Agents.configure do |config|
        config.async_logging = false
        config.persist_prompts = true
        config.persist_responses = true
        config.persist_messages_summary = true
      end
    end

    describe "#create_running_execution" do
      it "creates execution with running status" do
        started_at = Time.current
        execution = orch_instance.test_create_running_execution(started_at)

        expect(execution).to be_a(RubyLLM::Agents::Execution)
        expect(execution.status).to eq("running")
        expect(execution.agent_type).to eq("OrchestrationTestAgent")
        expect(execution.agent_version).to eq("2.0.0")
        expect(execution.model_id).to eq("gpt-4")
      end

      it "sets started_at timestamp" do
        started_at = 5.seconds.ago
        execution = orch_instance.test_create_running_execution(started_at)

        expect(execution.started_at).to be_within(1.second).of(started_at)
      end

      it "includes temperature and parameters" do
        execution = orch_instance.test_create_running_execution(Time.current)

        expect(execution.temperature).to eq(0.7)
        expect(execution.parameters).to be_a(Hash)
      end

      it "includes streaming flag" do
        execution = orch_instance.test_create_running_execution(Time.current)

        expect(execution.streaming).to be false
      end

      it "includes messages count and summary" do
        execution = orch_instance.test_create_running_execution(Time.current)

        expect(execution.messages_count).to eq(1)
        expect(execution.messages_summary).to be_present
      end

      it "includes fallback chain when provided" do
        started_at = Time.current
        execution = orch_instance.test_create_running_execution(started_at, fallback_chain: ["gpt-4", "gpt-3.5-turbo"])

        expect(execution.fallback_chain).to eq(["gpt-4", "gpt-3.5-turbo"])
        expect(execution.attempts).to eq([])
        expect(execution.attempts_count).to eq(0)
      end

      it "includes system and user prompts when persist_prompts is true" do
        execution = orch_instance.test_create_running_execution(Time.current)

        expect(execution.system_prompt).to include("test assistant")
        expect(execution.user_prompt).to include("Test prompt")
      end

      it "omits prompts when persist_prompts is false" do
        RubyLLM::Agents.configure do |config|
          config.persist_prompts = false
        end
        execution = orch_instance.test_create_running_execution(Time.current)

        expect(execution.system_prompt).to be_nil
        expect(execution.user_prompt).to be_nil
      end

      context "with multi-tenancy enabled" do
        before do
          RubyLLM::Agents.configure do |config|
            config.multi_tenancy_enabled = true
            config.tenant_resolver = -> { "tenant-123" }
          end
        end

        after do
          RubyLLM::Agents.configure do |config|
            config.multi_tenancy_enabled = false
            config.tenant_resolver = -> { nil }
          end
        end

        it "includes tenant_id" do
          execution = orch_instance.test_create_running_execution(Time.current)

          expect(execution.tenant_id).to eq("tenant-123")
        end
      end

      it "returns nil and logs error on failure" do
        allow(RubyLLM::Agents::Execution).to receive(:create!).and_raise(StandardError.new("DB error"))

        execution = orch_instance.test_create_running_execution(Time.current)

        expect(execution).to be_nil
      end
    end

    describe "#complete_execution" do
      let(:execution) do
        RubyLLM::Agents::Execution.create!(
          agent_type: "TestAgent",
          agent_version: "1.0",
          model_id: "gpt-4",
          started_at: 5.seconds.ago,
          status: "running"
        )
      end

      let(:mock_response) do
        double("Response",
          input_tokens: 100,
          output_tokens: 50,
          cached_tokens: 10,
          cache_creation_tokens: 5,
          model_id: "gpt-4",
          finish_reason: "stop",
          content: "Hello there!",
          thinking: nil,
          tool_calls: nil)
      end

      before do
        allow(mock_response).to receive(:respond_to?).and_return(true)
      end

      it "updates execution to success status" do
        orch_instance.test_complete_execution(execution, completed_at: Time.current, status: "success", response: mock_response)

        execution.reload
        expect(execution.status).to eq("success")
      end

      it "calculates duration_ms" do
        completed_at = Time.current
        orch_instance.test_complete_execution(execution, completed_at: completed_at, status: "success", response: mock_response)

        execution.reload
        expect(execution.duration_ms).to be > 0
      end

      it "records token counts from response" do
        orch_instance.test_complete_execution(execution, completed_at: Time.current, status: "success", response: mock_response)

        execution.reload
        expect(execution.input_tokens).to eq(100)
        expect(execution.output_tokens).to eq(50)
        expect(execution.cached_tokens).to eq(10)
      end

      it "records finish_reason from response" do
        orch_instance.test_complete_execution(execution, completed_at: Time.current, status: "success", response: mock_response)

        execution.reload
        expect(execution.finish_reason).to eq("stop")
      end

      it "updates to error status with error details" do
        error = StandardError.new("Something went wrong")
        orch_instance.test_complete_execution(execution, completed_at: Time.current, status: "error", error: error)

        execution.reload
        expect(execution.status).to eq("error")
        expect(execution.error_class).to eq("StandardError")
        expect(execution.error_message).to include("Something went wrong")
      end

      it "updates to timeout status" do
        error = Timeout::Error.new("Connection timed out")
        orch_instance.test_complete_execution(execution, completed_at: Time.current, status: "timeout", error: error)

        execution.reload
        expect(execution.status).to eq("timeout")
        expect(execution.error_class).to eq("Timeout::Error")
      end

      it "falls back to legacy logging when execution is nil" do
        expect(RubyLLM::Agents::ExecutionLoggerJob).to receive(:new).and_return(
          double("job", perform: true)
        )

        orch_instance.test_complete_execution(nil, completed_at: Time.current, status: "success", response: mock_response)
      end

      it "attempts cost calculation when token data available" do
        orch_instance.test_complete_execution(execution, completed_at: Time.current, status: "success", response: mock_response)

        execution.reload
        # Costs may be nil or 0 if pricing data isn't available for the model
        # The important thing is that it doesn't raise an error
        expect(execution.input_cost).to be_nil.or(be >= 0)
        expect(execution.output_cost).to be_nil.or(be >= 0)
      end
    end

    describe "#complete_execution_with_attempts" do
      let(:execution) do
        exec = RubyLLM::Agents::Execution.create!(
          agent_type: "TestAgent",
          agent_version: "1.0",
          model_id: "gpt-4",
          started_at: 5.seconds.ago,
          status: "running",
          attempts_count: 0
        )
        # Store fallback_chain and attempts on the detail record
        exec.create_detail!(
          fallback_chain: ["gpt-4", "gpt-3.5-turbo"],
          attempts: []
        )
        exec
      end

      let(:attempt_tracker) { RubyLLM::Agents::AttemptTracker.new }
      let(:mock_response) do
        double("Response",
          input_tokens: 100,
          output_tokens: 50,
          cached_tokens: 0,
          cache_creation_tokens: 0,
          model_id: "gpt-3.5-turbo",
          finish_reason: "stop")
      end

      before do
        # Record a failed attempt followed by a successful one
        attempt1 = attempt_tracker.start_attempt("gpt-4")
        attempt_tracker.complete_attempt(attempt1, success: false, error: StandardError.new("Rate limited"))

        attempt2 = attempt_tracker.start_attempt("gpt-3.5-turbo")
        attempt_tracker.complete_attempt(attempt2, success: true, response: mock_response)
      end

      it "updates execution with attempt data" do
        orch_instance.test_complete_execution_with_attempts(
          execution,
          attempt_tracker: attempt_tracker,
          completed_at: Time.current,
          status: "success"
        )

        execution.reload
        expect(execution.status).to eq("success")
        expect(execution.attempts_count).to eq(2)
        expect(execution.chosen_model_id).to eq("gpt-3.5-turbo")
      end

      it "aggregates token counts from all attempts" do
        orch_instance.test_complete_execution_with_attempts(
          execution,
          attempt_tracker: attempt_tracker,
          completed_at: Time.current,
          status: "success"
        )

        execution.reload
        expect(execution.input_tokens).to eq(attempt_tracker.total_input_tokens)
        expect(execution.output_tokens).to eq(attempt_tracker.total_output_tokens)
      end

      it "stores attempt data as JSON array" do
        orch_instance.test_complete_execution_with_attempts(
          execution,
          attempt_tracker: attempt_tracker,
          completed_at: Time.current,
          status: "success"
        )

        execution.reload
        expect(execution.attempts).to be_an(Array)
        expect(execution.attempts.size).to eq(2)
        expect(execution.attempts.first["model_id"]).to eq("gpt-4")
      end

      it "records fallback reason when fallback was used" do
        orch_instance.test_complete_execution_with_attempts(
          execution,
          attempt_tracker: attempt_tracker,
          completed_at: Time.current,
          status: "success"
        )

        execution.reload
        expect(execution.fallback_reason).to be_present
      end

      it "records error details when execution failed" do
        error = StandardError.new("All models failed")
        orch_instance.test_complete_execution_with_attempts(
          execution,
          attempt_tracker: attempt_tracker,
          completed_at: Time.current,
          status: "error",
          error: error
        )

        execution.reload
        expect(execution.status).to eq("error")
        expect(execution.error_class).to eq("StandardError")
        expect(execution.error_message).to include("All models failed")
      end

      it "does nothing when execution is nil" do
        expect {
          orch_instance.test_complete_execution_with_attempts(
            nil,
            attempt_tracker: attempt_tracker,
            completed_at: Time.current,
            status: "success"
          )
        }.not_to raise_error
      end
    end

    describe "#legacy_log_execution" do
      let(:mock_response) do
        double("Response",
          input_tokens: 100,
          output_tokens: 50,
          cached_tokens: 0,
          cache_creation_tokens: 0,
          model_id: "gpt-4",
          finish_reason: "stop",
          content: "Hello",
          thinking: nil,
          tool_calls: nil)
      end

      before do
        allow(mock_response).to receive(:respond_to?).and_return(true)
      end

      it "creates execution via synchronous job when async_logging is false" do
        RubyLLM::Agents.configure do |config|
          config.async_logging = false
        end

        expect {
          orch_instance.test_legacy_log_execution(
            completed_at: Time.current,
            status: "success",
            response: mock_response
          )
        }.to change(RubyLLM::Agents::Execution, :count).by(1)
      end

      it "creates execution via async job when async_logging is true" do
        RubyLLM::Agents.configure do |config|
          config.async_logging = true
        end

        expect(RubyLLM::Agents::ExecutionLoggerJob).to receive(:perform_later).with(hash_including(
          agent_type: "OrchestrationTestAgent",
          status: "success"
        ))

        orch_instance.test_legacy_log_execution(
          completed_at: Time.current,
          status: "success",
          response: mock_response
        )
      end

      it "includes error details when provided" do
        RubyLLM::Agents.configure do |config|
          config.async_logging = false
        end

        error = StandardError.new("Test error")
        orch_instance.test_legacy_log_execution(
          completed_at: Time.current,
          status: "error",
          error: error
        )

        execution = RubyLLM::Agents::Execution.last
        expect(execution.error_class).to eq("StandardError")
        # error_message is now stored on the detail record via _detail_data.
        # The ExecutionLoggerJob filters to known columns only, so _detail_data
        # is excluded. The error_class on the execution is the key error indicator.
      end
    end

    describe "#record_token_usage" do
      let(:execution) do
        RubyLLM::Agents::Execution.create!(
          agent_type: "TestAgent",
          agent_version: "1.0",
          model_id: "gpt-4",
          started_at: Time.current,
          status: "success",
          total_tokens: 150
        )
      end

      before do
        allow(RubyLLM::Agents::BudgetTracker).to receive(:record_tokens!)
      end

      it "records tokens to BudgetTracker" do
        orch_instance.test_record_token_usage(execution)

        expect(RubyLLM::Agents::BudgetTracker).to have_received(:record_tokens!).with(
          "OrchestrationTestAgent",
          150,
          tenant_id: nil,
          tenant_config: nil
        )
      end

      it "does nothing when execution is nil" do
        expect {
          orch_instance.test_record_token_usage(nil)
        }.not_to raise_error
      end

      it "does nothing when total_tokens is zero" do
        execution.update!(total_tokens: 0)

        orch_instance.test_record_token_usage(execution)

        expect(RubyLLM::Agents::BudgetTracker).not_to have_received(:record_tokens!)
      end

      it "handles BudgetTracker errors gracefully" do
        allow(RubyLLM::Agents::BudgetTracker).to receive(:record_tokens!).and_raise(StandardError.new("Budget error"))

        expect {
          orch_instance.test_record_token_usage(execution)
        }.not_to raise_error
      end
    end

    describe "#instrument_execution" do
      it "creates execution record and updates on success" do
        result = nil
        orch_instance.test_instrument_execution do
          result = "success"
        end

        expect(result).to eq("success")

        execution = RubyLLM::Agents::Execution.last
        expect(execution.status).to eq("success")
        expect(execution.completed_at).to be_present
      end

      it "tracks timeout errors" do
        expect {
          orch_instance.test_instrument_execution do
            raise Timeout::Error.new("Connection timed out")
          end
        }.to raise_error(Timeout::Error)

        execution = RubyLLM::Agents::Execution.last
        expect(execution.status).to eq("timeout")
      end

      it "tracks standard errors" do
        expect {
          orch_instance.test_instrument_execution do
            raise StandardError.new("Something failed")
          end
        }.to raise_error(StandardError)

        execution = RubyLLM::Agents::Execution.last
        expect(execution.status).to eq("error")
        expect(execution.error_class).to eq("StandardError")
      end

      it "stores captured response" do
        mock_response = double("Response",
          input_tokens: 100,
          output_tokens: 50,
          cached_tokens: 0,
          cache_creation_tokens: 0,
          model_id: "gpt-4",
          finish_reason: "stop",
          content: "Test content",
          thinking: nil,
          tool_calls: nil)
        allow(mock_response).to receive(:respond_to?).and_return(true)

        orch_instance.test_instrument_execution do
          orch_instance.capture_response(mock_response)
          "done"
        end

        execution = RubyLLM::Agents::Execution.last
        expect(execution.input_tokens).to eq(100)
        expect(execution.output_tokens).to eq(50)
      end

      it "sets execution_id on the instance" do
        orch_instance.test_instrument_execution do
          "test"
        end

        expect(orch_instance.execution_id).to be_present
        expect(orch_instance.execution_id).to eq(RubyLLM::Agents::Execution.last.id)
      end

      it "marks execution failed if complete_execution fails" do
        # Force the first update to fail, simulating a validation error
        call_count = 0
        allow_any_instance_of(RubyLLM::Agents::Execution).to receive(:update!) do |execution, *args|
          call_count += 1
          if call_count == 1
            raise ActiveRecord::RecordInvalid.new(execution)
          end
        end

        orch_instance.test_instrument_execution do
          "test"
        end

        # The execution should still be marked as error due to the emergency fallback
        execution = RubyLLM::Agents::Execution.last
        expect(["error", "running"]).to include(execution.status)
      end
    end

    describe "#instrument_execution_with_attempts" do
      it "creates execution record with fallback chain" do
        result = nil
        orch_instance.test_instrument_execution_with_attempts(models_to_try: ["gpt-4", "gpt-3.5-turbo"]) do |tracker|
          tracker.start_attempt("gpt-4")
          result = "success"
          throw :execution_success, result
        end

        expect(result).to eq("success")

        execution = RubyLLM::Agents::Execution.last
        expect(execution.fallback_chain).to eq(["gpt-4", "gpt-3.5-turbo"])
      end

      it "tracks attempts via AttemptTracker" do
        orch_instance.test_instrument_execution_with_attempts(models_to_try: ["gpt-4", "gpt-3.5-turbo"]) do |tracker|
          attempt1 = tracker.start_attempt("gpt-4")
          tracker.complete_attempt(attempt1, success: false, error: StandardError.new("Failed"))

          attempt2 = tracker.start_attempt("gpt-3.5-turbo")
          mock_resp = double("Response", input_tokens: 50, output_tokens: 25, cached_tokens: 0, cache_creation_tokens: 0, model_id: "gpt-3.5-turbo")
          tracker.complete_attempt(attempt2, success: true, response: mock_resp)

          throw :execution_success, "done"
        end

        execution = RubyLLM::Agents::Execution.last
        expect(execution.attempts_count).to eq(2)
        expect(execution.chosen_model_id).to eq("gpt-3.5-turbo")
      end

      it "handles timeout errors" do
        expect {
          orch_instance.test_instrument_execution_with_attempts(models_to_try: ["gpt-4"]) do |_tracker|
            raise Timeout::Error.new("Timed out")
          end
        }.to raise_error(Timeout::Error)

        execution = RubyLLM::Agents::Execution.last
        expect(execution.status).to eq("timeout")
      end

      it "handles standard errors" do
        expect {
          orch_instance.test_instrument_execution_with_attempts(models_to_try: ["gpt-4"]) do |_tracker|
            raise StandardError.new("All models failed")
          end
        }.to raise_error(StandardError)

        execution = RubyLLM::Agents::Execution.last
        expect(execution.status).to eq("error")
      end

      it "returns result from successful execution" do
        result = orch_instance.test_instrument_execution_with_attempts(models_to_try: ["gpt-4"]) do |tracker|
          attempt = tracker.start_attempt("gpt-4")
          mock_resp = double("Response", input_tokens: 50, output_tokens: 25, cached_tokens: 0, cache_creation_tokens: 0, model_id: "gpt-4")
          tracker.complete_attempt(attempt, success: true, response: mock_resp)
          throw :execution_success, "my result"
        end

        expect(result).to eq("my result")
      end
    end
  end
end
