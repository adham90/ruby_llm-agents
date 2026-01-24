# frozen_string_literal: true

require "rails_helper"

RSpec.describe RubyLLM::Agents::Workflow::DSL::RouteBuilder do
  let(:agent_a) { Class.new(RubyLLM::Agents::Base) }
  let(:agent_b) { Class.new(RubyLLM::Agents::Base) }
  let(:default_agent) { Class.new(RubyLLM::Agents::Base) }

  describe "#method_missing for route definition" do
    it "defines routes via method calls" do
      builder = described_class.new
      builder.premium agent_a
      builder.standard agent_b

      expect(builder.routes[:premium]).to eq({ agent: agent_a, options: {} })
      expect(builder.routes[:standard]).to eq({ agent: agent_b, options: {} })
    end

    it "accepts options for routes" do
      builder = described_class.new
      builder.premium agent_a, timeout: 60, input: -> { { vip: true } }

      expect(builder.routes[:premium][:agent]).to eq(agent_a)
      expect(builder.routes[:premium][:options][:timeout]).to eq(60)
      expect(builder.routes[:premium][:options][:input]).to be_a(Proc)
    end
  end

  describe "#default" do
    it "sets the default route" do
      builder = described_class.new
      builder.default default_agent

      expect(builder.default).to eq({ agent: default_agent, options: {} })
    end

    it "accepts options for default route" do
      builder = described_class.new
      builder.default default_agent, timeout: 30

      expect(builder.default[:options][:timeout]).to eq(30)
    end
  end

  describe "#resolve" do
    let(:builder) do
      b = described_class.new
      b.premium agent_a
      b.standard agent_b
      b.default default_agent
      b
    end

    it "resolves matching route by symbol" do
      result = builder.resolve(:premium)
      expect(result[:agent]).to eq(agent_a)
    end

    it "resolves matching route by string" do
      result = builder.resolve("premium")
      expect(result[:agent]).to eq(agent_a)
    end

    it "resolves to default when no match" do
      result = builder.resolve(:unknown)
      expect(result[:agent]).to eq(default_agent)
    end

    it "normalizes boolean values" do
      builder = described_class.new
      builder.true agent_a
      builder.false agent_b

      expect(builder.resolve(true)[:agent]).to eq(agent_a)
      expect(builder.resolve(false)[:agent]).to eq(agent_b)
    end

    it "normalizes nil" do
      builder = described_class.new
      builder.nil agent_a

      expect(builder.resolve(nil)[:agent]).to eq(agent_a)
    end

    it "raises NoRouteError when no match and no default" do
      builder = described_class.new
      builder.premium agent_a

      expect { builder.resolve(:unknown) }.to raise_error(
        RubyLLM::Agents::Workflow::DSL::RouteBuilder::NoRouteError,
        /No route defined for value/
      )
    end

    it "includes available routes in error" do
      builder = described_class.new
      builder.premium agent_a
      builder.standard agent_b

      error = nil
      begin
        builder.resolve(:unknown)
      rescue RubyLLM::Agents::Workflow::DSL::RouteBuilder::NoRouteError => e
        error = e
      end

      expect(error.available_routes).to eq([:premium, :standard])
      expect(error.value).to eq(:unknown)
    end
  end

  describe "#route_names" do
    it "returns all defined route names" do
      builder = described_class.new
      builder.premium agent_a
      builder.standard agent_b
      builder.basic agent_a

      expect(builder.route_names).to eq([:premium, :standard, :basic])
    end
  end

  describe "#route_exists?" do
    it "returns true for defined routes" do
      builder = described_class.new
      builder.premium agent_a

      expect(builder.route_exists?(:premium)).to be true
    end

    it "returns true when default is defined" do
      builder = described_class.new
      builder.default default_agent

      expect(builder.route_exists?(:anything)).to be true
    end

    it "returns false when route not defined and no default" do
      builder = described_class.new
      builder.premium agent_a

      expect(builder.route_exists?(:unknown)).to be false
    end
  end

  describe "#to_h" do
    it "serializes routes" do
      stub_const("AgentA", agent_a)
      stub_const("DefaultAgent", default_agent)

      builder = described_class.new
      builder.premium agent_a, timeout: 60
      builder.default default_agent

      hash = builder.to_h

      expect(hash[:routes][:premium][:agent]).to eq("AgentA")
      expect(hash[:routes][:premium][:options][:timeout]).to eq(60)
      expect(hash[:default][:agent]).to eq("DefaultAgent")
    end
  end
end
