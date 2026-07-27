# frozen_string_literal: true

require "rails_helper"

# Cache reads are billed at a discount (4x cheaper on OpenAI, 10x on Anthropic).
# Charging them at the full input rate overstates spend by 2-3x on exactly the
# workload prompt caching exists for — a long stable system prompt replayed every
# turn — which is how a production app read its own margin as 31% when it was
# nearer 67%.
RSpec.describe "Cached token pricing" do
  before { stub_agent_configuration(track_executions: false) }

  let(:agent_class) { Class.new(RubyLLM::Agents::Base) { model "gpt-4.1" } }
  let(:agent) { agent_class.new }

  def pricing(input:, output:, cached:)
    text_tokens = double("PricingTier", input: input, output: output, cached_input: cached)
    double("ModelInfo", pricing: double("Pricing", text_tokens: text_tokens))
  end

  def model_info(provider:, input: 2.0, output: 8.0, cached: 0.5)
    info = pricing(input: input, output: output, cached: cached)
    allow(info).to receive(:provider).and_return(provider)
    allow(info).to receive(:id).and_return("test-model")
    info
  end

  def context_with(input_tokens:, output_tokens: 0, cached_tokens: nil)
    ctx = RubyLLM::Agents::Pipeline::Context.new(input: "hi", agent_class: agent_class)
    ctx.input_tokens = input_tokens
    ctx.output_tokens = output_tokens
    ctx.cached_tokens = cached_tokens
    ctx
  end

  # A response that exposes no #cost, matching RubyLLM::Message in 1.14.x —
  # so extra_token_costs contributes nothing and input_cost is isolated.
  def response_for(model_id = "gpt-4.1")
    double("Message", model_id: model_id)
  end

  def calculate(ctx, info)
    allow(agent).to receive(:find_model_info).and_return(info)
    agent.send(:calculate_costs, response_for, ctx)
    ctx
  end

  describe "providers whose input_tokens INCLUDE the cache reads (OpenAI, Gemini)" do
    it "bills the cached portion at the cached rate, not the full rate" do
      ctx = calculate(context_with(input_tokens: 7112, cached_tokens: 6016), model_info(provider: "openai"))

      # 1096 uncached @ $2/M + 6016 cached @ $0.50/M
      expect(ctx.input_cost).to be_within(1e-9).of((1096 / 1e6 * 2.0) + (6016 / 1e6 * 0.5))
    end

    it "is materially cheaper than charging every input token at full rate" do
      ctx = calculate(context_with(input_tokens: 7112, cached_tokens: 6016), model_info(provider: "openai"))

      naive = 7112 / 1e6 * 2.0
      expect(ctx.input_cost).to be < naive / 2 # the bug overstated by ~2.7x
    end

    it "treats Gemini the same way" do
      ctx = calculate(context_with(input_tokens: 1000, cached_tokens: 800), model_info(provider: "gemini"))

      expect(ctx.input_cost).to be_within(1e-9).of((200 / 1e6 * 2.0) + (800 / 1e6 * 0.5))
    end
  end

  describe "Anthropic, whose input_tokens EXCLUDE the cache reads" do
    # Its reported input_tokens is already net of the cache read, so the cache
    # is genuinely additive and extra_token_costs prices it. Subtracting here
    # would bill a prefix that was never in input_tokens to begin with.
    it "leaves the input charge at the full rate on all reported input tokens" do
      ctx = calculate(context_with(input_tokens: 1096, cached_tokens: 6016), model_info(provider: "anthropic"))

      expect(ctx.input_cost).to be_within(1e-9).of(1096 / 1e6 * 2.0)
    end

    it "leaves cache_read for extra_token_costs to charge" do
      ctx = calculate(context_with(input_tokens: 1096, cached_tokens: 6016), model_info(provider: "anthropic"))

      expect(ctx[:cache_read_priced]).to be_nil
    end
  end

  describe "fallbacks" do
    it "charges everything at the full rate when no cache was reported" do
      ctx = calculate(context_with(input_tokens: 5000), model_info(provider: "openai"))

      expect(ctx.input_cost).to be_within(1e-9).of(5000 / 1e6 * 2.0)
    end

    it "never under-bills a model whose registry entry has no cached price" do
      info = model_info(provider: "openai", cached: nil)
      ctx = calculate(context_with(input_tokens: 7112, cached_tokens: 6016), info)

      expect(ctx.input_cost).to be_within(1e-9).of(7112 / 1e6 * 2.0)
    end

    it "does not mark the cache as priced when it fell back to full rate" do
      info = model_info(provider: "openai", cached: nil)
      ctx = calculate(context_with(input_tokens: 7112, cached_tokens: 6016), info)

      # extra_token_costs must still be free to add cache_read itself
      expect(ctx[:cache_read_priced]).to be_nil
    end

    it "flags the cache as priced so extra_token_costs does not charge it twice" do
      ctx = calculate(context_with(input_tokens: 7112, cached_tokens: 6016), model_info(provider: "openai"))

      expect(ctx[:cache_read_priced]).to be true
    end
  end
end
