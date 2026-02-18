# frozen_string_literal: true

require "rails_helper"
require "ostruct"

RSpec.describe RubyLLM::Agents::Routing do
  # --- DSL ---

  describe "route DSL" do
    it "registers routes with descriptions" do
      klass = Class.new(RubyLLM::Agents::BaseAgent) do
        include RubyLLM::Agents::Routing

        route :billing, "Billing, charges, refunds"
        route :technical, "Bugs, errors, crashes"
      end

      expect(klass.routes).to include(
        billing: {description: "Billing, charges, refunds", agent: nil},
        technical: {description: "Bugs, errors, crashes", agent: nil}
      )
    end

    it "registers routes with agent mappings" do
      billing_agent = Class.new(RubyLLM::Agents::BaseAgent)
      agent_ref = billing_agent

      klass = Class.new(RubyLLM::Agents::BaseAgent) do
        include RubyLLM::Agents::Routing

        route :billing, "Billing questions", agent: agent_ref
      end

      expect(klass.routes[:billing][:agent]).to eq(billing_agent)
    end

    it "inherits routes from parent class" do
      parent = Class.new(RubyLLM::Agents::BaseAgent) do
        include RubyLLM::Agents::Routing

        route :billing, "Billing questions"
      end

      child = Class.new(parent) do
        route :technical, "Tech issues"
      end

      expect(child.routes.keys).to contain_exactly(:billing, :technical)
    end

    it "supports default_route" do
      klass = Class.new(RubyLLM::Agents::BaseAgent) do
        include RubyLLM::Agents::Routing

        route :billing, "Billing"
        default_route :general
      end

      expect(klass.default_route_name).to eq(:general)
      expect(klass.routes).to have_key(:general)
    end

    it "defaults to :general when no default_route set" do
      klass = Class.new(RubyLLM::Agents::BaseAgent) do
        include RubyLLM::Agents::Routing

        route :billing, "Billing"
      end

      expect(klass.default_route_name).to eq(:general)
    end

    it "raises if included in non-BaseAgent class" do
      expect {
        Class.new do
          include RubyLLM::Agents::Routing
        end
      }.to raise_error(ArgumentError, /must inherit from RubyLLM::Agents::BaseAgent/)
    end

    it "reports agent_type as :router" do
      klass = Class.new(RubyLLM::Agents::BaseAgent) do
        include RubyLLM::Agents::Routing

        route :billing, "Billing"
      end

      expect(klass.agent_type).to eq(:router)
    end

    it "auto-registers :message as an optional param" do
      klass = Class.new(RubyLLM::Agents::BaseAgent) do
        include RubyLLM::Agents::Routing

        route :billing, "Billing"
      end

      expect(klass.params).to have_key(:message)
      expect(klass.params[:message][:required]).to be false
    end

    it "allows default_route with agent mapping" do
      agent_class = Class.new(RubyLLM::Agents::BaseAgent)
      agent_ref = agent_class

      klass = Class.new(RubyLLM::Agents::BaseAgent) do
        include RubyLLM::Agents::Routing

        default_route :general, agent: agent_ref
      end

      expect(klass.routes[:general][:agent]).to eq(agent_class)
    end
  end

  # --- Prompt Generation ---

  describe "auto-generated prompts" do
    let(:router_class) do
      Class.new(RubyLLM::Agents::BaseAgent) do
        include RubyLLM::Agents::Routing

        model "gpt-4o-mini"

        route :billing, "Billing, charges, refunds"
        route :technical, "Bugs, errors, crashes"
        default_route :general
      end
    end

    it "generates system_prompt from route definitions" do
      agent = router_class.new(message: "test")
      prompt = agent.system_prompt

      expect(prompt).to include("message classifier")
      expect(prompt).to include("billing: Billing, charges, refunds")
      expect(prompt).to include("technical: Bugs, errors, crashes")
      expect(prompt).to include("general")
    end

    it "generates user_prompt from message param" do
      agent = router_class.new(message: "I was charged twice")

      expect(agent.user_prompt).to eq("I was charged twice")
    end

    it "includes default route name in system prompt" do
      agent = router_class.new(message: "test")

      expect(agent.system_prompt).to include("classify as: general")
    end

    it "provides routing_system_prompt helper" do
      agent = router_class.new(message: "test")

      expect(agent.routing_system_prompt).to include("billing")
      expect(agent.routing_system_prompt).to include("technical")
    end

    it "provides routing_categories_text helper" do
      agent = router_class.new(message: "test")

      expect(agent.routing_categories_text).to eq(
        "- billing: Billing, charges, refunds\n" \
        "- technical: Bugs, errors, crashes\n" \
        "- general: Default / general category"
      )
    end

    it "allows system_prompt override with routing_system_prompt helper" do
      custom_class = Class.new(RubyLLM::Agents::BaseAgent) do
        include RubyLLM::Agents::Routing

        route :billing, "Billing"
        route :technical, "Technical"
        default_route :general

        def system_prompt
          "Custom prefix.\n\n#{routing_system_prompt}"
        end
      end

      agent = custom_class.new(message: "test")
      expect(agent.system_prompt).to start_with("Custom prefix.")
      expect(agent.system_prompt).to include("billing")
    end

    it "allows custom routing_categories_text in overridden prompts" do
      custom_class = Class.new(RubyLLM::Agents::BaseAgent) do
        include RubyLLM::Agents::Routing

        route :billing, "Billing"
        default_route :general

        def system_prompt
          "Categories:\n#{routing_categories_text}\nClassify now."
        end
      end

      agent = custom_class.new(message: "test")
      expect(agent.system_prompt).to include("Categories:")
      expect(agent.system_prompt).to include("- billing: Billing")
    end
  end

  # --- Classification (process_response) ---

  describe "classification" do
    let(:router_class) do
      Class.new(RubyLLM::Agents::BaseAgent) do
        include RubyLLM::Agents::Routing

        model "gpt-4o-mini"

        route :billing, "Billing, charges, refunds"
        route :technical, "Bugs, errors, crashes"
        default_route :general
      end
    end

    let(:agent) { router_class.new(message: "test") }

    def fake_response(text)
      OpenStruct.new(content: text)
    end

    it "parses clean route names from LLM response" do
      result = agent.process_response(fake_response("billing"))
      expect(result[:route]).to eq(:billing)
    end

    it "strips whitespace from response" do
      result = agent.process_response(fake_response("  billing  \n"))
      expect(result[:route]).to eq(:billing)
    end

    it "strips special characters from response" do
      result = agent.process_response(fake_response("**billing**"))
      expect(result[:route]).to eq(:billing)
    end

    it "handles mixed case response" do
      result = agent.process_response(fake_response("BILLING"))
      expect(result[:route]).to eq(:billing)
    end

    it "falls back to default_route for unknown classifications" do
      result = agent.process_response(fake_response("unknown_category"))
      expect(result[:route]).to eq(:general)
    end

    it "falls back to default_route for empty responses" do
      result = agent.process_response(fake_response(""))
      expect(result[:route]).to eq(:general)
    end

    it "falls back to default_route for gibberish" do
      result = agent.process_response(fake_response("I think this is about billing matters"))
      expect(result[:route]).to eq(:general)
    end

    it "sets agent_class when route has agent mapping" do
      billing_agent = Class.new(RubyLLM::Agents::BaseAgent)
      agent_ref = billing_agent

      klass = Class.new(RubyLLM::Agents::BaseAgent) do
        include RubyLLM::Agents::Routing

        route :billing, "Billing", agent: agent_ref
        default_route :general
      end

      instance = klass.new(message: "test")
      result = instance.process_response(fake_response("billing"))
      expect(result[:agent_class]).to eq(billing_agent)
    end

    it "sets agent_class to nil when no mapping" do
      result = agent.process_response(fake_response("billing"))
      expect(result[:agent_class]).to be_nil
    end

    it "preserves raw_response from LLM" do
      result = agent.process_response(fake_response("  Billing  "))
      expect(result[:raw_response]).to eq("Billing")
    end
  end

  # --- RoutingResult ---

  describe RubyLLM::Agents::Routing::RoutingResult do
    let(:base_result) do
      RubyLLM::Agents::Result.new(
        content: "billing",
        input_tokens: 100,
        output_tokens: 5,
        input_cost: 0.0001,
        output_cost: 0.00001,
        total_cost: 0.00011,
        model_id: "gpt-4o-mini",
        chosen_model_id: "gpt-4o-mini",
        temperature: 0.0,
        started_at: Time.current,
        completed_at: Time.current + 0.3,
        duration_ms: 300,
        finish_reason: "stop",
        streaming: false,
        attempts_count: 1
      )
    end

    let(:route_data) do
      {
        route: :billing,
        agent_class: nil,
        raw_response: "billing"
      }
    end

    subject { described_class.new(base_result: base_result, route_data: route_data) }

    it "exposes .route as a symbol" do
      expect(subject.route).to eq(:billing)
    end

    it "exposes .agent_class" do
      expect(subject.agent_class).to be_nil
    end

    it "exposes .raw_response" do
      expect(subject.raw_response).to eq("billing")
    end

    it "delegates token info to base Result" do
      expect(subject.input_tokens).to eq(100)
      expect(subject.output_tokens).to eq(5)
      expect(subject.total_tokens).to eq(105)
    end

    it "delegates cost to base Result" do
      expect(subject.total_cost).to eq(0.00011)
    end

    it "delegates timing to base Result" do
      expect(subject.duration_ms).to eq(300)
    end

    it "delegates model info to base Result" do
      expect(subject.model_id).to eq("gpt-4o-mini")
      expect(subject.temperature).to eq(0.0)
    end

    it "supports .success?" do
      expect(subject.success?).to be true
    end

    it "supports .error?" do
      expect(subject.error?).to be false
    end

    it "supports .to_h with routing fields" do
      hash = subject.to_h

      expect(hash[:route]).to eq(:billing)
      expect(hash[:agent_class]).to be_nil
      expect(hash[:raw_response]).to eq("billing")
      expect(hash[:input_tokens]).to eq(100)
      expect(hash[:model_id]).to eq("gpt-4o-mini")
    end

    it "includes agent_class name in to_h when present" do
      agent = Class.new(RubyLLM::Agents::BaseAgent) do
        def self.name
          "BillingAgent"
        end
      end

      data = route_data.merge(agent_class: agent)
      result = described_class.new(base_result: base_result, route_data: data)

      expect(result.to_h[:agent_class]).to eq("BillingAgent")
      expect(result.agent_class).to eq(agent)
    end
  end

  # --- Full call flow with minimal stub ---

  describe "full call flow" do
    let(:router_class) do
      Class.new(RubyLLM::Agents::BaseAgent) do
        include RubyLLM::Agents::Routing

        model "gpt-4o-mini"
        temperature 0.0

        route :billing, "Billing, charges, refunds"
        route :technical, "Bugs, errors, crashes"
        default_route :general
      end
    end

    it "returns a RoutingResult through the call chain" do
      # Build a RoutingResult as if the pipeline ran
      routing_result = RubyLLM::Agents::Routing::RoutingResult.new(
        base_result: RubyLLM::Agents::Result.new(
          content: {route: :billing, agent_class: nil, raw_response: "billing"},
          input_tokens: 85,
          output_tokens: 3,
          model_id: "gpt-4o-mini",
          chosen_model_id: "gpt-4o-mini",
          temperature: 0.0,
          finish_reason: "stop",
          streaming: false,
          attempts_count: 1
        ),
        route_data: {route: :billing, agent_class: nil, raw_response: "billing"}
      )

      # Stub Pipeline::Executor to return our pre-built result
      allow(RubyLLM::Agents::Pipeline::Executor).to receive(:execute) do |context|
        context.output = routing_result
        context
      end

      result = router_class.call(message: "I was charged twice")

      expect(result).to be_a(RubyLLM::Agents::Routing::RoutingResult)
      expect(result.route).to eq(:billing)
      expect(result.success?).to be true
      expect(result.input_tokens).to eq(85)
      expect(result.output_tokens).to eq(3)
    end

    it "works with dry_run mode" do
      result = router_class.call(message: "test", dry_run: true)

      expect(result).to be_a(RubyLLM::Agents::Result)
      expect(result.content[:dry_run]).to be true
      expect(result.content[:system_prompt]).to include("message classifier")
      expect(result.content[:user_prompt]).to eq("test")
    end
  end

  # --- Context injection ---

  describe "context injection" do
    it "passes extra params to custom system_prompt" do
      klass = Class.new(RubyLLM::Agents::BaseAgent) do
        include RubyLLM::Agents::Routing

        model "gpt-4o-mini"

        route :billing, "Billing"
        route :technical, "Technical"
        default_route :general

        param :customer_tier, required: false

        def system_prompt
          base = routing_system_prompt
          if customer_tier
            base + "\n\nThe customer is on the #{customer_tier} tier."
          else
            base
          end
        end
      end

      agent = klass.new(message: "test", customer_tier: "enterprise")
      expect(agent.system_prompt).to include("enterprise tier")

      agent_no_tier = klass.new(message: "test")
      expect(agent_no_tier.system_prompt).not_to include("tier")
    end

    it "works with param DSL" do
      klass = Class.new(RubyLLM::Agents::BaseAgent) do
        include RubyLLM::Agents::Routing

        model "gpt-4o-mini"

        route :billing, "Billing"
        default_route :general

        param :locale, default: "en"
      end

      agent = klass.new(message: "test")
      expect(agent.locale).to eq("en")

      agent_fr = klass.new(message: "test", locale: "fr")
      expect(agent_fr.locale).to eq("fr")
    end
  end

  # --- Inline classify ---

  describe ".classify" do
    it "returns a symbol route" do
      # Stub the call on any BaseAgent subclass to avoid real LLM calls
      fake_routing_result = RubyLLM::Agents::Routing::RoutingResult.new(
        base_result: RubyLLM::Agents::Result.new(
          content: "billing",
          model_id: "gpt-4o-mini"
        ),
        route_data: {route: :billing, agent_class: nil, raw_response: "billing"}
      )

      allow_any_instance_of(RubyLLM::Agents::BaseAgent).to receive(:call).and_return(fake_routing_result)

      result = RubyLLM::Agents::Routing.classify(
        message: "I was charged twice",
        routes: {
          billing: "Billing, charges, refunds",
          technical: "Bugs, errors, crashes"
        },
        default: :general
      )

      expect(result).to eq(:billing)
    end

    it "creates router with correct routes" do
      # Capture the anonymous class to inspect its routes
      created_class = nil

      allow(Class).to receive(:new).and_wrap_original do |method, *args, &block|
        result = method.call(*args, &block)
        if result < RubyLLM::Agents::BaseAgent && result.respond_to?(:routes) && result.routes.any?
          created_class = result
        end
        result
      end

      # Stub to avoid LLM call
      allow_any_instance_of(RubyLLM::Agents::BaseAgent).to receive(:call).and_return(
        RubyLLM::Agents::Routing::RoutingResult.new(
          base_result: RubyLLM::Agents::Result.new(content: "billing", model_id: "gpt-4o-mini"),
          route_data: {route: :billing, agent_class: nil, raw_response: "billing"}
        )
      )

      RubyLLM::Agents::Routing.classify(
        message: "test",
        routes: {billing: "Billing", technical: "Technical"},
        default: :support
      )

      expect(created_class).not_to be_nil
      expect(created_class.routes.keys).to include(:billing, :technical, :support)
      expect(created_class.default_route_name).to eq(:support)
    end
  end
end
