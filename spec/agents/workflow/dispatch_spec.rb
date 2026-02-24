# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Workflow dispatch" do
  let(:mock_chat) { build_mock_chat_client(response: mock_response) }
  let(:mock_response) { build_mock_response(content: "Result", input_tokens: 100, output_tokens: 50) }

  before do
    stub_ruby_llm_chat(mock_chat)
    stub_agent_configuration(track_executions: false)
  end

  let(:billing_agent) do
    Class.new(RubyLLM::Agents::BaseAgent) do
      def self.name = "BillingAgent"
      model "gpt-4o"
      param :message, required: false
      user "Handle billing: {message}"
    end
  end

  let(:technical_agent) do
    Class.new(RubyLLM::Agents::BaseAgent) do
      def self.name = "TechnicalAgent"
      model "gpt-4o"
      param :message, required: false
      user "Handle tech: {message}"
    end
  end

  let(:general_agent) do
    Class.new(RubyLLM::Agents::BaseAgent) do
      def self.name = "GeneralAgent"
      model "gpt-4o"
      param :message, required: false
      user "Handle general: {message}"
    end
  end

  describe RubyLLM::Agents::Workflow::DispatchBuilder do
    it "registers routes and resolves them" do
      builder = described_class.new(:classify)
      builder.on(:billing, agent: billing_agent)
      builder.on(:technical, agent: technical_agent)

      resolved = builder.resolve(:billing)
      expect(resolved[:agent]).to eq(billing_agent)
    end

    it "returns default for unknown routes" do
      builder = described_class.new(:classify)
      builder.on(:billing, agent: billing_agent)
      builder.on_default(agent: general_agent)

      resolved = builder.resolve(:unknown)
      expect(resolved[:agent]).to eq(general_agent)
    end

    it "returns nil when no default and route unknown" do
      builder = described_class.new(:classify)
      builder.on(:billing, agent: billing_agent)

      expect(builder.resolve(:unknown)).to be_nil
    end
  end

  describe "DSL dispatch method" do
    it "registers dispatch configuration" do
      ba = billing_agent
      ta = technical_agent

      wf = Class.new(RubyLLM::Agents::Workflow) {
        dispatch :classify do |d|
          d.on :billing, agent: ba
          d.on :technical, agent: ta
        end
      }

      expect(wf.dispatches.size).to eq(1)
      expect(wf.dispatches.first[:builder].router_step).to eq(:classify)
      expect(wf.dispatches.first[:handler_name]).to eq(:handler)
    end

    it "supports custom handler step name via as:" do
      ba = billing_agent

      wf = Class.new(RubyLLM::Agents::Workflow) {
        dispatch :classify, as: :support_handler do |d|
          d.on :billing, agent: ba
        end
      }

      expect(wf.dispatches.first[:handler_name]).to eq(:support_handler)
    end
  end

  describe "dispatch execution" do
    it "routes to the correct handler after a routing step" do
      # Create a router agent that returns a RoutingResult
      router_agent = Class.new(RubyLLM::Agents::BaseAgent) do
        include RubyLLM::Agents::Routing

        def self.name = "TestRouter"
        model "gpt-4o"
        temperature 0.0

        route :billing, "Billing issues"
        route :technical, "Technical issues"
        default_route :general
      end

      # Make the router return "billing" route
      routing_response = build_mock_response(content: "billing", input_tokens: 50, output_tokens: 10)
      routing_chat = build_mock_chat_client(response: routing_response)
      allow(RubyLLM).to receive(:chat).and_return(routing_chat)

      handler_called = nil
      ba = billing_agent
      ta = technical_agent
      ga = general_agent

      allow(ba).to receive(:call).and_wrap_original do |method, **kwargs|
        handler_called = :billing
        method.call(**kwargs)
      end

      ra = router_agent
      wf = Class.new(RubyLLM::Agents::Workflow) {
        step :classify, ra

        dispatch :classify do |d|
          d.on :billing, agent: ba
          d.on :technical, agent: ta
          d.on_default agent: ga
        end
      }

      result = wf.call(message: "I was charged twice")

      expect(handler_called).to eq(:billing)
      expect(result.step(:handler)).to be_a(RubyLLM::Agents::Result)
    end

    it "uses default handler for unknown routes" do
      router_agent = Class.new(RubyLLM::Agents::BaseAgent) do
        include RubyLLM::Agents::Routing

        def self.name = "TestRouter"
        model "gpt-4o"
        temperature 0.0

        route :billing, "Billing issues"
        default_route :general
      end

      # Router returns "general" (the default)
      routing_response = build_mock_response(content: "something_unknown", input_tokens: 50, output_tokens: 10)
      routing_chat = build_mock_chat_client(response: routing_response)
      allow(RubyLLM).to receive(:chat).and_return(routing_chat)

      default_called = false
      ga = general_agent
      allow(ga).to receive(:call).and_wrap_original do |method, **kwargs|
        default_called = true
        method.call(**kwargs)
      end

      ba = billing_agent
      ra = router_agent
      wf = Class.new(RubyLLM::Agents::Workflow) {
        step :classify, ra

        dispatch :classify do |d|
          d.on :billing, agent: ba
          d.on_default agent: ga
        end
      }

      result = wf.call(message: "hello")

      expect(default_called).to be true
      expect(result.step(:handler)).to be_a(RubyLLM::Agents::Result)
    end

    it "aggregates cost from both routing and handler steps" do
      router_agent = Class.new(RubyLLM::Agents::BaseAgent) do
        include RubyLLM::Agents::Routing

        def self.name = "TestRouter"
        model "gpt-4o"
        temperature 0.0

        route :billing, "Billing issues"
        default_route :general
      end

      routing_response = build_mock_response(content: "billing", input_tokens: 50, output_tokens: 10)
      routing_chat = build_mock_chat_client(response: routing_response)
      allow(RubyLLM).to receive(:chat).and_return(routing_chat)

      ba = billing_agent
      ra = router_agent
      wf = Class.new(RubyLLM::Agents::Workflow) {
        step :classify, ra

        dispatch :classify do |d|
          d.on :billing, agent: ba
        end
      }

      result = wf.call(message: "refund please")

      # Both the classify step and handler step should have results
      expect(result.step(:classify)).not_to be_nil
      expect(result.step(:handler)).not_to be_nil
      expect(result.total_tokens).to be > 0
    end

    it "handles dispatch with no matching route gracefully" do
      router_agent = Class.new(RubyLLM::Agents::BaseAgent) do
        include RubyLLM::Agents::Routing

        def self.name = "TestRouter"
        model "gpt-4o"
        temperature 0.0

        route :billing, "Billing issues"
        default_route :general
      end

      # Returns "general" but no handler for general and no default
      routing_response = build_mock_response(content: "general", input_tokens: 50, output_tokens: 10)
      routing_chat = build_mock_chat_client(response: routing_response)
      allow(RubyLLM).to receive(:chat).and_return(routing_chat)

      ba = billing_agent
      ra = router_agent
      wf = Class.new(RubyLLM::Agents::Workflow) {
        step :classify, ra

        dispatch :classify do |d|
          d.on :billing, agent: ba
          # No default — general route unhandled
        end
      }

      result = wf.call(message: "hello")

      # Classify succeeded, but no handler was dispatched
      expect(result.step(:classify)).not_to be_nil
      expect(result.step(:handler)).to be_nil
    end
  end
end
