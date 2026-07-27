# frozen_string_literal: true

require "rails_helper"

# Cache reads are billed at a discount (4x cheaper on OpenAI, 10x on Anthropic)
# and must be billed exactly once.
#
# The subtlety is WHERE they live. Every RubyLLM provider reports input_tokens
# already NET of the cache reads — Anthropic natively, and OpenAI, Gemini,
# Bedrock and OpenRouter by subtracting the cache counters while parsing usage
# (see e.g. Providers::OpenAI::Chat#input_tokens). So the cache read is always
# additive, and the cost is input_tokens @ full rate + cached_tokens @ cache
# rate. Treating any provider as "cached tokens are already inside input_tokens"
# subtracts them a second time, clamps the remainder to zero, and bills the real
# uncached input at $0 — measured at -24% on gpt-4.1 and -26% on Bedrock Claude.
RSpec.describe "Cached token pricing" do
  before { stub_agent_configuration(track_executions: false) }

  # Builds a message exactly the way the provider's own parser would, so the
  # input_tokens/cached_tokens pairing under test is one RubyLLM really emits.
  def openai_message(model_id, prompt_tokens:, cached:, completion_tokens: 0)
    usage = {
      "prompt_tokens" => prompt_tokens,
      "completion_tokens" => completion_tokens,
      "total_tokens" => prompt_tokens + completion_tokens,
      "prompt_tokens_details" => {"cached_tokens" => cached}
    }
    RubyLLM::Message.new(
      role: :assistant,
      content: "ok",
      input_tokens: RubyLLM::Providers::OpenAI::Chat.input_tokens(usage),
      output_tokens: RubyLLM::Providers::OpenAI::Chat.output_tokens(usage),
      cached_tokens: RubyLLM::Providers::OpenAI::Chat.cache_read_tokens(usage),
      cache_creation_tokens: RubyLLM::Providers::OpenAI::Chat.cache_write_tokens(usage),
      model_id: model_id
    )
  end

  def anthropic_message(model_id, input:, cached:, cache_creation: 0, output: 0)
    RubyLLM::Message.new(
      role: :assistant, content: "ok",
      input_tokens: input, output_tokens: output,
      cached_tokens: cached, cache_creation_tokens: cache_creation,
      model_id: model_id
    )
  end

  # Runs the real cost path and returns the context it wrote to.
  def cost_for(message, model_id)
    agent_class = Class.new(RubyLLM::Agents::Base) { model model_id }
    agent = agent_class.new
    ctx = RubyLLM::Agents::Pipeline::Context.new(input: "hi", agent_class: agent_class)
    agent.send(:capture_response, message, ctx)
    ctx
  end

  describe "agreement with RubyLLM::Cost, the provider-neutral source of truth" do
    # RubyLLM::Cost already knows each component's rate. The gem computes text
    # input/output itself and adds the cache/reasoning components on top, so the
    # two must land on the same number for any model in the registry.
    {
      "OpenAI" => "gpt-4.1",
      "Anthropic" => "claude-sonnet-4-5-20250929"
    }.each do |label, model_id|
      it "matches RubyLLM::Cost#total for a prompt-cached #{label} call" do
        info = RubyLLM::Models.find(model_id)
        message = if label == "OpenAI"
          openai_message(model_id, prompt_tokens: 7112, cached: 6016, completion_tokens: 500)
        else
          anthropic_message(model_id, input: 1096, cached: 6016, output: 500)
        end

        ctx = cost_for(message, model_id)

        expect(ctx.total_cost).to be_within(1e-6).of(message.cost(model: info).total)
      end
    end

    it "matches RubyLLM::Cost for an Anthropic call that also writes the cache" do
      model_id = "claude-sonnet-4-5-20250929"
      info = RubyLLM::Models.find(model_id)
      message = anthropic_message(model_id, input: 1096, cached: 6016, cache_creation: 2048, output: 500)

      ctx = cost_for(message, model_id)

      expect(ctx.total_cost).to be_within(1e-6).of(message.cost(model: info).total)
    end

    it "matches RubyLLM::Cost for Anthropic hosted on Bedrock" do
      model = RubyLLM.models.all.find do |m|
        m.provider.to_s == "bedrock" && m.id.include?("claude") &&
          m.pricing&.text_tokens&.cache_read_input
      end
      skip "registry has no Bedrock Claude with cache pricing" unless model

      message = anthropic_message(model.id, input: 1096, cached: 6016, output: 500)

      ctx = cost_for(message, model.id)

      expect(ctx.total_cost).to be_within(1e-6).of(message.cost(model: model).total)
    end
  end

  describe "the input charge" do
    it "bills every reported input token at the full rate" do
      # input_tokens is already the uncached remainder (7112 - 6016), so all of
      # it is genuinely uncached and none of it may be discounted.
      message = openai_message("gpt-4.1", prompt_tokens: 7112, cached: 6016)
      input_price = RubyLLM::Models.find("gpt-4.1").pricing.text_tokens.input

      ctx = cost_for(message, "gpt-4.1")

      expect(message.input_tokens).to eq(1096)
      expect(ctx.input_cost).to be_within(1e-9).of(1096 / 1e6 * input_price)
    end

    it "never subtracts the cache read from the input charge" do
      # The regression this guards: cached (6016) exceeds input (1096), so a
      # subtraction clamps to zero and the uncached input is billed at $0.
      message = openai_message("gpt-4.1", prompt_tokens: 7112, cached: 6016)

      ctx = cost_for(message, "gpt-4.1")

      expect(ctx.input_cost).to be > 0
    end
  end

  describe "the cache-read charge" do
    it "bills the cache read once, at the cached rate, on top of input" do
      tier = RubyLLM::Models.find("gpt-4.1").pricing.text_tokens
      message = openai_message("gpt-4.1", prompt_tokens: 7112, cached: 6016)

      ctx = cost_for(message, "gpt-4.1")

      expect(ctx[:cost_breakdown][:cache_read])
        .to be_within(1e-9).of((6016 / 1e6 * tier.cache_read_input).round(6))
      expect(ctx.total_cost)
        .to be_within(1e-6).of(ctx.input_cost + ctx.output_cost + ctx[:cost_breakdown][:cache_read])
    end

    it "is materially cheaper than billing the cache read at the full input rate" do
      tier = RubyLLM::Models.find("gpt-4.1").pricing.text_tokens
      message = openai_message("gpt-4.1", prompt_tokens: 7112, cached: 6016)

      ctx = cost_for(message, "gpt-4.1")

      expect(ctx.total_cost).to be < (7112 / 1e6 * tier.input)
    end

    it "falls back to the full input rate when the registry has no cached price" do
      # Never silently free: an unpriced cache read is charged as ordinary input.
      agent = Class.new(RubyLLM::Agents::Base) { model "gpt-4.1" }.new
      ctx = RubyLLM::Agents::Pipeline::Context.new(input: "hi", agent_class: agent.class)
      ctx.cached_tokens = 6016

      tier = double("PricingTier", input: 2.0)
      info = double("ModelInfo", pricing: double("Pricing", text_tokens: tier))
      cost = double("Cost", cache_read: nil)

      expect(agent.send(:cache_read_cost, cost, info, ctx)).to be_within(1e-9).of(6016 / 1e6 * 2.0)
    end

    it "bills nothing when no cache was reported" do
      agent = Class.new(RubyLLM::Agents::Base) { model "gpt-4.1" }.new
      ctx = RubyLLM::Agents::Pipeline::Context.new(input: "hi", agent_class: agent.class)
      cost = double("Cost", cache_read: nil)

      expect(agent.send(:cache_read_cost, cost, double("ModelInfo"), ctx)).to be_nil
    end
  end

  describe "uncached calls" do
    it "charges input and output at the plain rates" do
      tier = RubyLLM::Models.find("gpt-4.1").pricing.text_tokens
      message = openai_message("gpt-4.1", prompt_tokens: 5000, cached: 0, completion_tokens: 200)

      ctx = cost_for(message, "gpt-4.1")

      expect(ctx.input_cost).to be_within(1e-9).of(5000 / 1e6 * tier.input)
      expect(ctx.output_cost).to be_within(1e-9).of(200 / 1e6 * tier.output)
      expect(ctx[:cost_breakdown]).to be_nil
    end
  end
end
