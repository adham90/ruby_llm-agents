# frozen_string_literal: true

require "rails_helper"

RSpec.describe RubyLLM::Agents::Workflow::Router do
  # Mock agent classes for testing
  let(:mock_result) do
    ->(content, cost: 0.001) do
      RubyLLM::Agents::Result.new(
        content: content,
        input_tokens: 100,
        output_tokens: 50,
        total_cost: cost,
        model_id: "gpt-4o"
      )
    end
  end

  let(:billing_agent) do
    result_builder = mock_result
    Class.new(RubyLLM::Agents::Base) do
      model "gpt-4o"
      param :message, required: false

      define_method(:call) do |&_block|
        result_builder.call("Billing response for: #{@options[:message]}", cost: 0.01)
      end

      def user_prompt
        "billing"
      end
    end
  end

  let(:technical_agent) do
    result_builder = mock_result
    Class.new(RubyLLM::Agents::Base) do
      model "gpt-4o"
      param :message, required: false

      define_method(:call) do |&_block|
        result_builder.call("Technical response", cost: 0.02)
      end

      def user_prompt
        "technical"
      end
    end
  end

  let(:general_agent) do
    result_builder = mock_result
    Class.new(RubyLLM::Agents::Base) do
      model "gpt-4o"
      param :message, required: false

      define_method(:call) do |&_block|
        result_builder.call("General response", cost: 0.005)
      end

      def user_prompt
        "general"
      end
    end
  end

  describe "DSL class methods" do
    describe ".route" do
      it "defines routes" do
        agent = billing_agent
        klass = Class.new(described_class) do
          route :billing, to: agent, description: "Billing issues"
        end
        expect(klass.routes.keys).to eq([:billing])
      end

      it "stores agent class" do
        agent = billing_agent
        klass = Class.new(described_class) do
          route :billing, to: agent, description: "Billing"
        end
        expect(klass.routes[:billing][:agent]).to eq(agent)
      end

      it "stores description" do
        agent = billing_agent
        klass = Class.new(described_class) do
          route :billing, to: agent, description: "Billing and payment issues"
        end
        expect(klass.routes[:billing][:description]).to eq("Billing and payment issues")
      end

      it "supports match proc for rule-based routing" do
        agent = billing_agent
        match_proc = ->(input) { input[:type] == "billing" }
        klass = Class.new(described_class) do
          route :billing, to: agent, match: match_proc
        end
        expect(klass.routes[:billing][:match]).to eq(match_proc)
      end

      it "allows default route without description" do
        agent = general_agent
        klass = Class.new(described_class) do
          route :default, to: agent
        end
        expect(klass.routes[:default][:description]).to be_nil
      end
    end

    describe ".classifier_model" do
      it "sets classifier model" do
        klass = Class.new(described_class) do
          classifier_model "gpt-4o-mini"
        end
        expect(klass.classifier_model).to eq("gpt-4o-mini")
      end

      it "has a default classifier model" do
        klass = Class.new(described_class)
        expect(klass.classifier_model).to be_present
      end
    end

    describe ".classifier_temperature" do
      it "sets classifier temperature" do
        klass = Class.new(described_class) do
          classifier_temperature 0.3
        end
        expect(klass.classifier_temperature).to eq(0.3)
      end

      it "defaults to 0.0" do
        klass = Class.new(described_class)
        expect(klass.classifier_temperature).to eq(0.0)
      end
    end

    describe "inheritance" do
      it "inherits routes from parent" do
        agent = billing_agent
        parent = Class.new(described_class) do
          route :billing, to: agent, description: "Billing"
        end
        child = Class.new(parent)
        expect(child.routes.keys).to eq([:billing])
      end

      it "inherits classifier_model from parent" do
        parent = Class.new(described_class) do
          classifier_model "gpt-4o-mini"
        end
        child = Class.new(parent)
        expect(child.classifier_model).to eq("gpt-4o-mini")
      end
    end
  end

  describe "rule-based routing" do
    it "routes based on match proc without LLM" do
      bill = billing_agent
      tech = technical_agent
      gen = general_agent

      router = Class.new(described_class) do
        route :billing, to: bill, match: ->(input) { input[:category] == "billing" }
        route :technical, to: tech, match: ->(input) { input[:category] == "tech" }
        route :default, to: gen
      end

      result = router.call(message: "Help!", category: "billing")

      expect(result.routed_to).to eq(:billing)
      expect(result.content).to include("Billing response")
      expect(result.classification[:method]).to eq("rule")
    end

    it "falls back to default when no rule matches" do
      bill = billing_agent
      gen = general_agent

      router = Class.new(described_class) do
        route :billing, to: bill, match: ->(input) { input[:category] == "billing" }
        route :default, to: gen

        # Override classify to avoid LLM call
        def classify(input)
          :default
        end
      end

      result = router.call(message: "Random question")

      expect(result.routed_to).to eq(:default)
      expect(result.content).to eq("General response")
    end

    it "tries rules in order" do
      bill = billing_agent
      tech = technical_agent
      gen = general_agent

      first_matched = nil

      router = Class.new(described_class) do
        route :billing, to: bill, match: ->(input) do
          first_matched = :billing if first_matched.nil?
          input[:priority] == "high"
        end
        route :technical, to: tech, match: ->(input) do
          first_matched = :technical if first_matched.nil?
          input[:priority] == "high"
        end
        route :default, to: gen
      end

      result = router.call(message: "Urgent!", priority: "high")

      expect(result.routed_to).to eq(:billing) # First matching rule wins
    end
  end

  describe "custom classification" do
    it "allows override of classify method" do
      bill = billing_agent
      tech = technical_agent
      gen = general_agent

      router = Class.new(described_class) do
        route :billing, to: bill, description: "Billing"
        route :technical, to: tech, description: "Tech"
        route :default, to: gen

        def classify(input)
          if input[:message].downcase.include?("invoice")
            :billing
          elsif input[:message].downcase.include?("error")
            :technical
          else
            :default
          end
        end
      end

      result = router.call(message: "My invoice is wrong")
      expect(result.routed_to).to eq(:billing)

      result2 = router.call(message: "I got an error")
      expect(result2.routed_to).to eq(:technical)
    end
  end

  describe "#call" do
    it "returns WorkflowResult with routing info" do
      bill = billing_agent
      gen = general_agent

      router = Class.new(described_class) do
        route :billing, to: bill, match: ->(input) { true }
        route :default, to: gen
      end

      result = router.call(message: "Billing question")

      expect(result).to be_a(RubyLLM::Agents::Workflow::Result)
      expect(result.routed_to).to eq(:billing)
      expect(result.classification).to include(:route, :method)
    end

    it "includes routed agent result in branches" do
      bill = billing_agent

      router = Class.new(described_class) do
        route :billing, to: bill, match: ->(input) { true }
      end

      result = router.call(message: "test")

      expect(result.branches[:billing]).to be_a(RubyLLM::Agents::Result)
      expect(result.branches[:billing].content).to include("Billing response")
    end

    it "sets status to success when routing succeeds" do
      bill = billing_agent

      router = Class.new(described_class) do
        route :billing, to: bill, match: ->(input) { true }
      end

      result = router.call(message: "test")

      expect(result.status).to eq("success")
      expect(result.success?).to be true
    end
  end

  describe "input transformation" do
    it "calls before_route to transform input" do
      received_input = nil

      capturing_agent = Class.new(RubyLLM::Agents::Base) do
        model "gpt-4o"
        param :message, required: false
        param :route_context, required: false

        define_method(:call) do |&_block|
          received_input = @options
          RubyLLM::Agents::Result.new(content: "done", input_tokens: 10, output_tokens: 10, total_cost: 0.001)
        end

        def user_prompt
          "test"
        end
      end

      router = Class.new(described_class) do
        route :capture, to: capturing_agent, match: ->(input) { true }

        def before_route(input, chosen_route)
          input.merge(route_context: chosen_route, priority: "high")
        end
      end

      router.call(message: "original")

      expect(received_input[:message]).to eq("original")
      expect(received_input[:route_context]).to eq(:capture)
      expect(received_input[:priority]).to eq("high")
    end
  end

  describe "error handling" do
    it "raises RouterError when no routes defined" do
      router = Class.new(described_class)

      expect {
        router.call(message: "test")
      }.to raise_error(RubyLLM::Agents::Workflow::RouterError)
    end

    let(:failing_agent) do
      Class.new(RubyLLM::Agents::Base) do
        model "gpt-4o"

        def call(&_block)
          raise StandardError, "Agent failed"
        end

        def user_prompt
          "fail"
        end
      end
    end

    it "sets status to error when routed agent fails" do
      fail_agent = failing_agent

      router = Class.new(described_class) do
        route :fail, to: fail_agent, match: ->(input) { true }
      end

      result = router.call(message: "test")

      expect(result.status).to eq("error")
      expect(result.error?).to be true
    end
  end

  describe "classifier prompt building" do
    it "extracts classifiable content from common keys" do
      bill = billing_agent

      received_message = nil

      # Create a router that captures what it tries to classify
      router = Class.new(described_class) do
        route :billing, to: bill, description: "Billing"

        def classify(input)
          @captured_input = input
          :billing
        end
      end

      router.call(message: "Hello world")
      # The classify method received the input with :message key
    end

    it "builds prompt with route descriptions" do
      bill = billing_agent
      tech = technical_agent

      router = Class.new(described_class) do
        route :billing, to: bill, description: "Billing, invoices, payments"
        route :technical, to: tech, description: "Bugs, errors, crashes"

        def classify(input)
          :billing
        end
      end

      # Just test that it doesn't raise
      result = router.call(message: "test")
      expect(result.routed_to).to eq(:billing)
    end
  end
end
