# frozen_string_literal: true

require "rails_helper"

RSpec.describe RubyLLM::Agents::Base::ResponseBuilding do
  # Test class that includes the module
  let(:test_class) do
    Class.new do
      include RubyLLM::Agents::Base::ResponseBuilding
      include RubyLLM::Agents::Base::CostCalculation

      attr_accessor :execution_started_at, :time_to_first_token_ms, :accumulated_tool_calls

      def initialize
        @execution_started_at = nil
        @time_to_first_token_ms = nil
        @accumulated_tool_calls = []
      end

      def model
        "gpt-4o"
      end

      def temperature
        0.7
      end

      def self.streaming
        false
      end
    end
  end

  let(:instance) { test_class.new }

  describe "#result_response_value" do
    it "returns value when response responds to method" do
      response = double("response", input_tokens: 100)
      expect(instance.result_response_value(response, :input_tokens)).to eq(100)
    end

    it "returns default when response does not respond to method" do
      response = double("response")
      expect(instance.result_response_value(response, :unknown_method, 42)).to eq(42)
    end

    it "returns nil when response does not respond to method and no default" do
      response = double("response")
      expect(instance.result_response_value(response, :unknown_method)).to be_nil
    end

    it "returns default when method returns nil" do
      response = double("response", input_tokens: nil)
      expect(instance.result_response_value(response, :input_tokens, 0)).to eq(0)
    end

    it "returns value even if it's zero" do
      response = double("response", input_tokens: 0)
      expect(instance.result_response_value(response, :input_tokens, 42)).to eq(0)
    end
  end

  describe "#result_duration_ms" do
    it "returns nil when execution_started_at is nil" do
      instance.execution_started_at = nil
      expect(instance.result_duration_ms(Time.current)).to be_nil
    end

    it "calculates duration in milliseconds" do
      start_time = Time.current
      instance.execution_started_at = start_time
      completed_at = start_time + 1.5.seconds

      expect(instance.result_duration_ms(completed_at)).to eq(1500)
    end

    it "handles very short durations" do
      start_time = Time.current
      instance.execution_started_at = start_time
      completed_at = start_time + 0.001.seconds

      expect(instance.result_duration_ms(completed_at)).to eq(1)
    end

    it "handles longer durations" do
      start_time = Time.current
      instance.execution_started_at = start_time
      completed_at = start_time + 5.minutes

      expect(instance.result_duration_ms(completed_at)).to eq(300_000)
    end
  end

  describe "#result_finish_reason" do
    context "when response has finish_reason" do
      it "normalizes 'stop' to 'stop'" do
        response = double("response", finish_reason: "stop")
        expect(instance.result_finish_reason(response)).to eq("stop")
      end

      it "normalizes 'end_turn' to 'stop'" do
        response = double("response", finish_reason: "end_turn")
        expect(instance.result_finish_reason(response)).to eq("stop")
      end

      it "normalizes 'length' to 'length'" do
        response = double("response", finish_reason: "length")
        expect(instance.result_finish_reason(response)).to eq("length")
      end

      it "normalizes 'max_tokens' to 'length'" do
        response = double("response", finish_reason: "max_tokens")
        expect(instance.result_finish_reason(response)).to eq("length")
      end

      it "normalizes 'content_filter' to 'content_filter'" do
        response = double("response", finish_reason: "content_filter")
        expect(instance.result_finish_reason(response)).to eq("content_filter")
      end

      it "normalizes 'safety' to 'content_filter'" do
        response = double("response", finish_reason: "safety")
        expect(instance.result_finish_reason(response)).to eq("content_filter")
      end

      it "normalizes 'tool_calls' to 'tool_calls'" do
        response = double("response", finish_reason: "tool_calls")
        expect(instance.result_finish_reason(response)).to eq("tool_calls")
      end

      it "normalizes 'tool_use' to 'tool_calls'" do
        response = double("response", finish_reason: "tool_use")
        expect(instance.result_finish_reason(response)).to eq("tool_calls")
      end

      it "returns 'other' for unknown reasons" do
        response = double("response", finish_reason: "unknown_reason")
        expect(instance.result_finish_reason(response)).to eq("other")
      end

      it "handles symbol reasons" do
        response = double("response", finish_reason: :stop)
        expect(instance.result_finish_reason(response)).to eq("stop")
      end

      it "handles uppercase reasons" do
        response = double("response", finish_reason: "STOP")
        expect(instance.result_finish_reason(response)).to eq("stop")
      end
    end

    context "when response has stop_reason instead" do
      it "uses stop_reason as fallback" do
        response = double("response")
        allow(response).to receive(:respond_to?).with(:finish_reason).and_return(false)
        allow(response).to receive(:respond_to?).with(:stop_reason).and_return(true)
        allow(response).to receive(:stop_reason).and_return("end_turn")

        expect(instance.result_finish_reason(response)).to eq("stop")
      end
    end

    context "when response has no reason" do
      it "returns nil when finish_reason is nil" do
        response = double("response", finish_reason: nil)
        allow(response).to receive(:respond_to?).with(:finish_reason).and_return(true)
        allow(response).to receive(:respond_to?).with(:stop_reason).and_return(false)

        expect(instance.result_finish_reason(response)).to be_nil
      end

      it "returns nil when no methods respond" do
        response = double("response")
        allow(response).to receive(:respond_to?).with(:finish_reason).and_return(false)
        allow(response).to receive(:respond_to?).with(:stop_reason).and_return(false)

        expect(instance.result_finish_reason(response)).to be_nil
      end
    end
  end

  describe "#build_result" do
    let(:response) do
      double("response",
        input_tokens: 100,
        output_tokens: 50,
        cached_tokens: 10,
        cache_creation_tokens: 5,
        model_id: "gpt-4o",
        finish_reason: "stop"
      )
    end

    before do
      instance.execution_started_at = Time.current - 1.second
      instance.time_to_first_token_ms = 200
      instance.accumulated_tool_calls = [{ "name" => "search" }]

      # Stub cost calculation methods
      allow(instance).to receive(:result_input_cost).and_return(0.001)
      allow(instance).to receive(:result_output_cost).and_return(0.002)
      allow(instance).to receive(:result_total_cost).and_return(0.003)
    end

    it "builds a Result object" do
      result = instance.build_result("content", response)
      expect(result).to be_a(RubyLLM::Agents::Result)
    end

    it "sets content from parameter" do
      result = instance.build_result("test content", response)
      expect(result.content).to eq("test content")
    end

    it "extracts input_tokens from response" do
      result = instance.build_result("content", response)
      expect(result.input_tokens).to eq(100)
    end

    it "extracts output_tokens from response" do
      result = instance.build_result("content", response)
      expect(result.output_tokens).to eq(50)
    end

    it "extracts cached_tokens with default 0" do
      result = instance.build_result("content", response)
      expect(result.cached_tokens).to eq(10)
    end

    it "extracts cache_creation_tokens with default 0" do
      result = instance.build_result("content", response)
      expect(result.cache_creation_tokens).to eq(5)
    end

    it "uses instance model for model_id" do
      result = instance.build_result("content", response)
      expect(result.model_id).to eq("gpt-4o")
    end

    it "uses response model_id for chosen_model_id" do
      result = instance.build_result("content", response)
      expect(result.chosen_model_id).to eq("gpt-4o")
    end

    it "falls back to instance model for chosen_model_id when response model_id is nil" do
      response_no_model = double("response",
        input_tokens: 100,
        output_tokens: 50,
        cached_tokens: 10,
        cache_creation_tokens: 5,
        model_id: nil,
        finish_reason: "stop"
      )

      result = instance.build_result("content", response_no_model)
      expect(result.chosen_model_id).to eq("gpt-4o")
    end

    it "sets temperature from instance" do
      result = instance.build_result("content", response)
      expect(result.temperature).to eq(0.7)
    end

    it "sets started_at from instance" do
      result = instance.build_result("content", response)
      expect(result.started_at).to eq(instance.execution_started_at)
    end

    it "sets completed_at to current time" do
      before = Time.current
      result = instance.build_result("content", response)
      after = Time.current
      expect(result.completed_at).to be_between(before, after)
    end

    it "calculates duration_ms" do
      result = instance.build_result("content", response)
      expect(result.duration_ms).to be_a(Integer)
      expect(result.duration_ms).to be >= 1000
    end

    it "sets time_to_first_token_ms from instance" do
      result = instance.build_result("content", response)
      expect(result.time_to_first_token_ms).to eq(200)
    end

    it "normalizes finish_reason" do
      result = instance.build_result("content", response)
      expect(result.finish_reason).to eq("stop")
    end

    it "sets streaming from class" do
      result = instance.build_result("content", response)
      expect(result.streaming).to be false
    end

    it "sets costs from calculation methods" do
      result = instance.build_result("content", response)
      expect(result.input_cost).to eq(0.001)
      expect(result.output_cost).to eq(0.002)
      expect(result.total_cost).to eq(0.003)
    end

    it "includes tool_calls from accumulated" do
      result = instance.build_result("content", response)
      expect(result.tool_calls).to eq([{ "name" => "search" }])
    end

    it "counts tool_calls" do
      result = instance.build_result("content", response)
      expect(result.tool_calls_count).to eq(1)
    end

    context "with hash content" do
      it "passes hash content through" do
        hash_content = { key: "value", nested: { data: true } }
        result = instance.build_result(hash_content, response)
        expect(result.content).to eq(hash_content)
      end
    end

    context "with missing response values" do
      let(:minimal_response) do
        double("response").tap do |r|
          allow(r).to receive(:respond_to?).and_return(false)
        end
      end

      before do
        allow(instance).to receive(:result_input_cost).and_return(nil)
        allow(instance).to receive(:result_output_cost).and_return(nil)
        allow(instance).to receive(:result_total_cost).and_return(nil)
      end

      it "handles missing values gracefully" do
        result = instance.build_result("content", minimal_response)
        expect(result.input_tokens).to be_nil
        expect(result.output_tokens).to be_nil
      end
    end
  end
end
