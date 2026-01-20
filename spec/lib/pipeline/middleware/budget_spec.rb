# frozen_string_literal: true

require "rails_helper"

RSpec.describe RubyLLM::Agents::Pipeline::Middleware::Budget do
  let(:agent_class) do
    Class.new do
      def self.name
        "TestAgent"
      end

      def self.agent_type
        :embedding
      end

      def self.model
        "test-model"
      end
    end
  end

  let(:app) { double("app") }
  let(:middleware) { described_class.new(app, agent_class) }
  let(:config) { instance_double(RubyLLM::Agents::Configuration) }

  def build_context(options = {})
    RubyLLM::Agents::Pipeline::Context.new(
      input: "test",
      agent_class: agent_class,
      **options
    )
  end

  before do
    allow(RubyLLM::Agents).to receive(:configuration).and_return(config)
  end

  describe "#call" do
    context "when budgets are disabled" do
      before do
        allow(config).to receive(:budgets_enabled?).and_return(false)
      end

      it "passes through to the next middleware" do
        context = build_context
        expect(app).to receive(:call).with(context).and_return(context)

        result = middleware.call(context)
        expect(result).to eq(context)
      end
    end

    context "when budgets are enabled" do
      before do
        allow(config).to receive(:budgets_enabled?).and_return(true)
      end

      it "checks budget before execution" do
        context = build_context(tenant: { id: "org_123" })
        context.tenant_id = "org_123"

        expect(RubyLLM::Agents::BudgetTracker).to receive(:check!).with(
          agent_type: "TestAgent",
          tenant_id: "org_123",
          execution_type: "embedding"
        )
        allow(app).to receive(:call) do |ctx|
          ctx.output = "result"
          ctx
        end
        allow(RubyLLM::Agents::BudgetTracker).to receive(:record_spend!)

        middleware.call(context)
      end

      it "records spend after successful execution" do
        context = build_context
        context.output = "result"
        context.total_cost = 0.05

        allow(RubyLLM::Agents::BudgetTracker).to receive(:check!)
        allow(app).to receive(:call) do |ctx|
          ctx.output = "result"
          ctx.total_cost = 0.05
          ctx
        end

        expect(RubyLLM::Agents::BudgetTracker).to receive(:record_spend!).with(
          tenant_id: nil,
          cost: 0.05,
          tokens: 0
        )

        middleware.call(context)
      end

      it "does not record spend when result is cached" do
        context = build_context
        context.cached = true

        allow(RubyLLM::Agents::BudgetTracker).to receive(:check!)
        allow(app).to receive(:call) do |ctx|
          ctx.output = "cached_result"
          ctx.total_cost = 0.05
          ctx
        end

        expect(RubyLLM::Agents::BudgetTracker).not_to receive(:record_spend!)

        middleware.call(context)
      end

      it "does not record spend when cost is zero" do
        context = build_context

        allow(RubyLLM::Agents::BudgetTracker).to receive(:check!)
        allow(app).to receive(:call) do |ctx|
          ctx.output = "result"
          ctx.total_cost = 0
          ctx
        end

        expect(RubyLLM::Agents::BudgetTracker).not_to receive(:record_spend!)

        middleware.call(context)
      end

      it "re-raises BudgetExceededError" do
        context = build_context

        expect(RubyLLM::Agents::BudgetTracker).to receive(:check!).and_raise(
          RubyLLM::Agents::BudgetExceededError.new("Budget exceeded")
        )

        expect { middleware.call(context) }.to raise_error(RubyLLM::Agents::BudgetExceededError)
      end

      it "logs but does not fail on budget check errors" do
        context = build_context

        allow(RubyLLM::Agents::BudgetTracker).to receive(:check!).and_raise(
          StandardError.new("Database connection failed")
        )
        allow(app).to receive(:call) do |ctx|
          ctx.output = "result"
          ctx
        end

        # Should not raise, should continue execution
        expect { middleware.call(context) }.not_to raise_error
      end
    end
  end
end
