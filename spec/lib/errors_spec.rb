# frozen_string_literal: true

require "rails_helper"

RSpec.describe "RubyLLM::Agents Error Classes" do
  describe RubyLLM::Agents::Error do
    it "inherits from StandardError" do
      expect(RubyLLM::Agents::Error.superclass).to eq(StandardError)
    end

    it "can be raised with a message" do
      expect {
        raise RubyLLM::Agents::Error, "test error"
      }.to raise_error(RubyLLM::Agents::Error, "test error")
    end
  end

  describe RubyLLM::Agents::PipelineError do
    it "inherits from Error" do
      expect(RubyLLM::Agents::PipelineError.superclass).to eq(RubyLLM::Agents::Error)
    end
  end

  describe RubyLLM::Agents::ReliabilityError do
    it "inherits from Error" do
      expect(RubyLLM::Agents::ReliabilityError.superclass).to eq(RubyLLM::Agents::Error)
    end
  end

  describe RubyLLM::Agents::RetryableError do
    it "inherits from ReliabilityError" do
      expect(RubyLLM::Agents::RetryableError.superclass).to eq(RubyLLM::Agents::ReliabilityError)
    end
  end

  describe RubyLLM::Agents::CircuitOpenError do
    it "inherits from ReliabilityError" do
      expect(RubyLLM::Agents::CircuitOpenError.superclass).to eq(RubyLLM::Agents::ReliabilityError)
    end

    it "generates default message" do
      error = RubyLLM::Agents::CircuitOpenError.new
      expect(error.message).to eq("Circuit breaker is open")
    end

    it "generates default message with model" do
      error = RubyLLM::Agents::CircuitOpenError.new(model: "gpt-4")
      expect(error.message).to eq("Circuit breaker is open for gpt-4")
    end

    it "accepts custom message" do
      error = RubyLLM::Agents::CircuitOpenError.new("Custom message")
      expect(error.message).to eq("Custom message")
    end

    it "stores model attribute" do
      error = RubyLLM::Agents::CircuitOpenError.new(model: "claude-3")
      expect(error.model).to eq("claude-3")
    end
  end

  describe RubyLLM::Agents::TotalTimeoutError do
    it "inherits from ReliabilityError" do
      expect(RubyLLM::Agents::TotalTimeoutError.superclass).to eq(RubyLLM::Agents::ReliabilityError)
    end

    it "generates default message with timeout and elapsed" do
      error = RubyLLM::Agents::TotalTimeoutError.new(timeout: 30, elapsed: 35.567)
      expect(error.message).to eq("Total timeout of 30s exceeded (elapsed: 35.57s)")
    end

    it "accepts custom message" do
      error = RubyLLM::Agents::TotalTimeoutError.new("Custom timeout message")
      expect(error.message).to eq("Custom timeout message")
    end

    it "stores timeout attribute" do
      error = RubyLLM::Agents::TotalTimeoutError.new(timeout: 60, elapsed: 65)
      expect(error.timeout).to eq(60)
    end

    it "stores elapsed attribute" do
      error = RubyLLM::Agents::TotalTimeoutError.new(timeout: 60, elapsed: 65.5)
      expect(error.elapsed).to eq(65.5)
    end

    it "handles nil elapsed" do
      error = RubyLLM::Agents::TotalTimeoutError.new(timeout: 30, elapsed: nil)
      expect(error.message).to include("elapsed:")
    end
  end

  describe RubyLLM::Agents::AllModelsFailedError do
    it "inherits from ReliabilityError" do
      expect(RubyLLM::Agents::AllModelsFailedError.superclass).to eq(RubyLLM::Agents::ReliabilityError)
    end

    it "generates default message listing models" do
      attempts = [
        { model: "gpt-4", error: "timeout" },
        { model: "claude-3", error: "rate limit" }
      ]
      error = RubyLLM::Agents::AllModelsFailedError.new(attempts: attempts)
      expect(error.message).to eq("All models failed: gpt-4, claude-3")
    end

    it "accepts custom message" do
      error = RubyLLM::Agents::AllModelsFailedError.new("Custom failure message")
      expect(error.message).to eq("Custom failure message")
    end

    it "stores attempts array" do
      attempts = [{ model: "gpt-4" }, { model: "claude-3" }]
      error = RubyLLM::Agents::AllModelsFailedError.new(attempts: attempts)
      expect(error.attempts).to eq(attempts)
    end

    it "defaults attempts to empty array" do
      error = RubyLLM::Agents::AllModelsFailedError.new
      expect(error.attempts).to eq([])
    end
  end

  describe RubyLLM::Agents::BudgetError do
    it "inherits from Error" do
      expect(RubyLLM::Agents::BudgetError.superclass).to eq(RubyLLM::Agents::Error)
    end
  end

  describe RubyLLM::Agents::BudgetExceededError do
    it "inherits from BudgetError" do
      expect(RubyLLM::Agents::BudgetExceededError.superclass).to eq(RubyLLM::Agents::BudgetError)
    end

    it "generates default message" do
      error = RubyLLM::Agents::BudgetExceededError.new
      expect(error.message).to eq("Budget exceeded")
    end

    it "generates message with tenant_id" do
      error = RubyLLM::Agents::BudgetExceededError.new(tenant_id: "org-123")
      expect(error.message).to eq("Budget exceeded for tenant org-123")
    end

    it "accepts custom message" do
      error = RubyLLM::Agents::BudgetExceededError.new("Custom budget message")
      expect(error.message).to eq("Custom budget message")
    end

    it "stores tenant_id attribute" do
      error = RubyLLM::Agents::BudgetExceededError.new(tenant_id: "org-456")
      expect(error.tenant_id).to eq("org-456")
    end

    it "stores budget_type attribute" do
      error = RubyLLM::Agents::BudgetExceededError.new(budget_type: "daily")
      expect(error.budget_type).to eq("daily")
    end
  end

  describe RubyLLM::Agents::ConfigurationError do
    it "inherits from Error" do
      expect(RubyLLM::Agents::ConfigurationError.superclass).to eq(RubyLLM::Agents::Error)
    end
  end
end
