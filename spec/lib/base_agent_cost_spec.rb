# frozen_string_literal: true

require "rails_helper"

RSpec.describe RubyLLM::Agents::BaseAgent, "cost calculation" do
  let(:agent_class) do
    Class.new(described_class) do
      def self.name
        "CostTestAgent"
      end

      model "gpt-4o"
    end
  end

  let(:agent) do
    agent_class.allocate.tap { |a| a.instance_variable_set(:@options, {}) }
  end

  let(:context) do
    ctx = RubyLLM::Agents::Pipeline::Context.new(
      input: "hi",
      agent_class: agent_class,
      agent_instance: agent
    )
    ctx.input_tokens = 1000
    ctx.output_tokens = 500
    ctx
  end

  # Builds a real RubyLLM::Cost from controlled tokens and pricing so we can
  # assert the agent prices cache/reasoning components via the library without
  # depending on whatever the live model registry charges for them.
  def build_cost(prices:, cache_read: nil, cache_write: nil, thinking: nil)
    tokens = RubyLLM::Tokens.new(
      input: 1,
      output: 1,
      cached: cache_read,
      cache_creation: cache_write,
      thinking: thinking
    )
    text = Struct.new(
      :input, :output, :cache_read_input, :cache_write_input, :reasoning_output,
      keyword_init: true
    ).new(**prices)
    pricing = Struct.new(:text_tokens).new(text)
    model = Struct.new(:pricing).new(pricing)

    RubyLLM::Cost.new(tokens: tokens, model: model)
  end

  let(:full_prices) do
    {input: 3.0, output: 15.0, cache_read_input: 0.3, cache_write_input: 3.75, reasoning_output: 20.0}
  end

  describe "#calculate_costs non-text components" do
    it "adds cache and reasoning cost on top of text input/output" do
      extra = build_cost(cache_read: 2000, cache_write: 100, thinking: 300, prices: full_prices)
      response = double("RubyLLM::Message", model_id: "gpt-4o")
      allow(response).to receive(:cost).and_return(extra)

      agent.send(:calculate_costs, response, context)

      extra_sum = extra.cache_read + extra.cache_write + extra.thinking
      expect(context.total_cost).to eq((context.input_cost + context.output_cost + extra_sum).round(6))
      expect(context.total_cost).to be > (context.input_cost + context.output_cost)
    end

    it "records the non-text components into metadata" do
      extra = build_cost(cache_read: 2000, cache_write: 100, thinking: 300, prices: full_prices)
      response = double("RubyLLM::Message", model_id: "gpt-4o")
      allow(response).to receive(:cost).and_return(extra)

      agent.send(:calculate_costs, response, context)

      expect(context[:cost_breakdown]).to eq(
        cache_read: extra.cache_read.round(6),
        cache_write: extra.cache_write.round(6),
        thinking: extra.thinking.round(6)
      )
    end

    it "records no breakdown and adds nothing for an ordinary response" do
      extra = build_cost(prices: full_prices) # no cache/reasoning tokens
      response = double("RubyLLM::Message", model_id: "gpt-4o")
      allow(response).to receive(:cost).and_return(extra)

      agent.send(:calculate_costs, response, context)

      expect(context.total_cost).to eq((context.input_cost + context.output_cost).round(6))
      expect(context[:cost_breakdown]).to be_nil
    end

    it "ignores components the registry cannot price" do
      # cache tokens present but no cache price -> nothing to add for cache.
      extra = build_cost(
        cache_read: 2000, thinking: 300,
        prices: {input: 3.0, output: 15.0, cache_read_input: nil, cache_write_input: nil, reasoning_output: 20.0}
      )
      response = double("RubyLLM::Message", model_id: "gpt-4o")
      allow(response).to receive(:cost).and_return(extra)

      agent.send(:calculate_costs, response, context)

      # Only the reasoning component (which has a price) is added/recorded.
      expect(context[:cost_breakdown]).to eq(thinking: extra.thinking.round(6))
      expect(context.total_cost).to eq((context.input_cost + context.output_cost + extra.thinking).round(6))
    end
  end

  describe "#calculate_costs without a cost-bearing response" do
    it "prices text input/output and adds nothing" do
      response = double("LegacyResponse", model_id: "gpt-4o")

      agent.send(:calculate_costs, response, context)

      expect(context.input_cost).to be > 0
      expect(context.output_cost).to be > 0
      expect(context.total_cost).to eq((context.input_cost + context.output_cost).round(6))
      expect(context[:cost_breakdown]).to be_nil
    end
  end

  describe "#calculate_costs when reasoning is priced separately" do
    # Providers fold reasoning tokens into output_tokens, so pricing the full
    # output at the output rate AND adding the reasoning component would charge
    # those tokens twice. Use a registry model that prices reasoning apart from
    # output (output != reasoning_output).
    let(:model_id) { "perplexity/sonar-deep-research" }
    let(:pricing) { RubyLLM::Models.find(model_id).pricing.text_tokens }

    let(:reasoning_agent_class) do
      Class.new(described_class) do
        def self.name
          "ReasoningCostAgent"
        end

        model "perplexity/sonar-deep-research"
      end
    end

    let(:reasoning_agent) do
      reasoning_agent_class.allocate.tap { |a| a.instance_variable_set(:@options, {}) }
    end

    let(:reasoning_context) do
      ctx = RubyLLM::Agents::Pipeline::Context.new(
        input: "hi",
        agent_class: reasoning_agent_class,
        agent_instance: reasoning_agent
      )
      ctx.input_tokens = 1000
      ctx.output_tokens = 500 # of which 300 are reasoning tokens
      ctx
    end

    it "excludes reasoning tokens from the output charge so they aren't billed twice" do
      expect(pricing.reasoning_output).to be_present
      expect(pricing.reasoning_output).not_to eq(pricing.output)

      extra = build_cost(
        thinking: 300,
        prices: {
          input: pricing.input,
          output: pricing.output,
          cache_read_input: pricing.cache_read_input,
          cache_write_input: pricing.cache_write_input,
          reasoning_output: pricing.reasoning_output
        }
      )
      response = double("RubyLLM::Message", model_id: model_id, reasoning_tokens: 300)
      allow(response).to receive(:cost).and_return(extra)

      reasoning_agent.send(:calculate_costs, response, reasoning_context)

      # 300 of the 500 output tokens are reasoning -> priced only at the
      # reasoning rate, so output cost covers the remaining 200 tokens.
      expected_output = ((500 - 300) / 1_000_000.0) * pricing.output
      expect(reasoning_context.output_cost).to be_within(1e-12).of(expected_output)

      reasoning_cost = (300 / 1_000_000.0) * pricing.reasoning_output
      expected_total = (reasoning_context.input_cost + expected_output + reasoning_cost).round(6)
      expect(reasoning_context.total_cost).to be_within(1e-9).of(expected_total)
    end
  end
end
