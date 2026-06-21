# frozen_string_literal: true

require "rails_helper"

# tokens-per-million divisor used by the pipeline
COST_PER_MILLION = 1_000_000.0

# Exhaustive real-number correctness spec for cost calculation.
#
# NO MOCKS except real RubyLLM objects. Most responses are a real
# RubyLLM::Message built from controlled token counts, and every price is
# pulled live from RubyLLM::Models.find(id).pricing.text_tokens. The agent
# instances are real subclasses of BaseAgent; we drive the *real*
# BaseAgent#calculate_costs / #extra_token_costs via .send on an instance
# configured with the matching model. Reasoning-token exclusion now happens
# INSIDE calculate_costs (private #reasoning_tokens_charged) — there is no
# #billable_output_tokens method to call.
#
# All expected dollar values are derived independently below (arithmetic
# hardcoded), so a wrong implementation fails. The pipeline formula is:
#
#   input_cost  = (input_tokens  / 1_000_000.0) * input_price
#   output_cost = (billable_out  / 1_000_000.0) * output_price
#   billable_out = output_tokens - reasoning_charged   # reasoning_charged is the
#                  reasoning tokens ONLY when they were actually billed at the
#                  reasoning rate (the cost breakdown recorded a :thinking
#                  component); otherwise 0, so reasoning is never billed at $0.
#   extra        = round6(cache_read) + round6(cache_write) + round6(thinking)
#   total_cost   = round6(input_cost + output_cost + extra)
#
# where cache_read / cache_write / thinking come from
#   RubyLLM::Message#cost(model:).{cache_read,cache_write,thinking}
# priced against the resolved model_info.
#
# The Execution model's own total rule is simpler and separate: its before_save
# sets total_cost = (input_cost || 0) + (output_cost || 0), but ONLY when the
# caller didn't supply an explicit total in the same save (see section 8).
RSpec.describe "cost calculation correctness", type: :model do
  # Build a real BaseAgent subclass bound to a model, then allocate an
  # instance with an empty options hash (so #model returns the class model).
  # We never call .new through the pipeline — calculate_costs only needs
  # @model + @options, which #initialize sets. We use allocate + ivar set to
  # mirror spec/lib/base_agent_cost_spec.rb and avoid param validation.
  def agent_for(model_id)
    klass = Class.new(RubyLLM::Agents::BaseAgent) do
      define_singleton_method(:name) { "CostCorrectnessAgent_#{model_id.gsub(/\W/, "_")}" }
      model model_id
    end
    klass.allocate.tap do |a|
      a.instance_variable_set(:@options, {})
      a.instance_variable_set(:@model, model_id)
    end
  end

  # A real Pipeline::Context carrying the authoritative token counts. The
  # pipeline prices text input/output from context tokens (they may aggregate
  # across retries), so context — not the message — holds input/output_tokens.
  def context_for(agent, input_tokens:, output_tokens:)
    ctx = RubyLLM::Agents::Pipeline::Context.new(
      input: "hi",
      agent_class: agent.class,
      agent_instance: agent
    )
    ctx.input_tokens = input_tokens
    ctx.output_tokens = output_tokens
    ctx
  end

  # Real RubyLLM::Message. cache/reasoning tokens live on the message and are
  # priced by RubyLLM::Cost; text in/out live on the context.
  def message(model_id:, input_tokens:, output_tokens:, cached_tokens: nil,
    cache_creation_tokens: nil, reasoning_tokens: nil)
    RubyLLM::Message.new(
      role: :assistant,
      content: "ok",
      model_id: model_id,
      input_tokens: input_tokens,
      output_tokens: output_tokens,
      cached_tokens: cached_tokens,
      cache_creation_tokens: cache_creation_tokens,
      reasoning_tokens: reasoning_tokens
    )
  end

  # Builds a real RubyLLM::Cost from controlled token counts and the live
  # perplexity/sonar-deep-research prices, mirroring spec/lib/base_agent_cost_spec.rb.
  # Used to drive the reasoning-exclusion path deterministically: a Cost with a
  # thinking component makes calculate_costs record :thinking in the breakdown,
  # which is the signal reasoning_tokens_charged uses to exclude reasoning tokens
  # from the output charge.
  def perplexity_cost(cache_read: nil, cache_write: nil, thinking: nil)
    p = sonar
    tokens = RubyLLM::Tokens.new(
      input: 1, output: 1,
      cached: cache_read, cache_creation: cache_write, thinking: thinking
    )
    text = Struct.new(
      :input, :output, :cache_read_input, :cache_write_input, :reasoning_output,
      keyword_init: true
    ).new(
      input: p.input, output: p.output,
      cache_read_input: p.cache_read_input, cache_write_input: p.cache_write_input,
      reasoning_output: p.reasoning_output
    )
    pricing = Struct.new(:text_tokens).new(text)
    model = Struct.new(:pricing).new(pricing)
    RubyLLM::Cost.new(tokens: tokens, model: model)
  end

  # Live prices straight from the registry. We assert the registry shape we
  # depend on so a registry change that invalidates the math fails loudly
  # here instead of silently weakening the assertions below.
  let(:gpt4o) { RubyLLM::Models.find("gpt-4o").pricing.text_tokens }
  let(:haiku) { RubyLLM::Models.find("claude-3-5-haiku-20241022").pricing.text_tokens }
  let(:sonar) { RubyLLM::Models.find("perplexity/sonar-deep-research").pricing.text_tokens }

  it "registry pricing matches the fixtures this spec's arithmetic relies on" do
    # gpt-4o: input 2.5, output 10, cache_read 1.25, NO cache_write, NO reasoning.
    expect(gpt4o.input).to eq(2.5)
    expect(gpt4o.output).to eq(10)
    expect(gpt4o.cache_read_input).to eq(1.25)
    expect(gpt4o.cache_write_input).to be_nil

    # claude-3-5-haiku: full cache pricing.
    expect(haiku.input).to eq(0.8)
    expect(haiku.output).to eq(4)
    expect(haiku.cache_read_input).to eq(0.08)
    expect(haiku.cache_write_input).to eq(1)

    # perplexity/sonar-deep-research: reasoning priced apart from output.
    expect(sonar.input).to eq(2)
    expect(sonar.output).to eq(8)
    expect(sonar.reasoning_output).to eq(3)
    expect(sonar.reasoning_output).not_to eq(sonar.output)
  end

  # ---------------------------------------------------------------------------
  # (1) TEXT-ONLY  — gpt-4o, in=1000 out=500
  #   input  = 1000/1e6 * 2.5 = 0.0025
  #   output =  500/1e6 * 10  = 0.005
  #   extra  = 0  (no cache/reasoning tokens)
  #   total  = round6(0.0075) = 0.0075
  # ---------------------------------------------------------------------------
  describe "(1) text-only" do
    it "prices input and output, no breakdown" do
      agent = agent_for("gpt-4o")
      ctx = context_for(agent, input_tokens: 1000, output_tokens: 500)
      resp = message(model_id: "gpt-4o", input_tokens: 1000, output_tokens: 500)

      agent.send(:calculate_costs, resp, ctx)

      expect(ctx.input_cost).to be_within(1e-12).of(0.0025)
      expect(ctx.output_cost).to be_within(1e-12).of(0.005)
      expect(ctx.total_cost).to eq(0.0075)
      expect(ctx[:cost_breakdown]).to be_nil
    end
  end

  # ---------------------------------------------------------------------------
  # (2) CACHE READ ONLY — gpt-4o, in=1000 out=500 cached=400
  #   input      = 0.0025
  #   output     = 0.005
  #   cache_read = 400/1e6 * 1.25 = 0.0005   (round6 -> 0.0005)
  #   gpt-4o has NO cache_write price -> no cache_write component even if tokens present
  #   total      = round6(0.0025 + 0.005 + 0.0005) = 0.008
  # ---------------------------------------------------------------------------
  describe "(2) cache read only" do
    it "adds only the priced cache-read component" do
      agent = agent_for("gpt-4o")
      ctx = context_for(agent, input_tokens: 1000, output_tokens: 500)
      resp = message(model_id: "gpt-4o", input_tokens: 1000, output_tokens: 500, cached_tokens: 400)

      agent.send(:calculate_costs, resp, ctx)

      expect(ctx.input_cost).to be_within(1e-12).of(0.0025)
      expect(ctx.output_cost).to be_within(1e-12).of(0.005)
      expect(ctx[:cost_breakdown]).to eq(cache_read: 0.0005)
      expect(ctx[:cost_breakdown]).not_to have_key(:cache_write)
      expect(ctx.total_cost).to eq(0.008)
    end

    it "ignores cache-write tokens the registry cannot price (gpt-4o)" do
      # cache_creation tokens present, but gpt-4o has no cache_write_input price,
      # so RubyLLM::Cost#cache_write is nil and contributes nothing.
      agent = agent_for("gpt-4o")
      ctx = context_for(agent, input_tokens: 1000, output_tokens: 500)
      resp = message(model_id: "gpt-4o", input_tokens: 1000, output_tokens: 500,
        cached_tokens: 400, cache_creation_tokens: 9999)

      agent.send(:calculate_costs, resp, ctx)

      expect(ctx[:cost_breakdown]).to eq(cache_read: 0.0005)
      expect(ctx.total_cost).to eq(0.008)
    end
  end

  # ---------------------------------------------------------------------------
  # (3) CACHE READ + WRITE — claude-3-5-haiku, in=1000 out=500 cached=2000 creation=800
  #   input       = 1000/1e6 * 0.8 = 0.0008
  #   output      =  500/1e6 * 4   = 0.002
  #   cache_read  = 2000/1e6 * 0.08 = 0.00016  (round6 -> 0.00016)
  #   cache_write =  800/1e6 * 1.0  = 0.0008   (round6 -> 0.0008)
  #   total       = round6(0.0008 + 0.002 + 0.00016 + 0.0008) = 0.00376
  # ---------------------------------------------------------------------------
  describe "(3) cache read + write" do
    it "adds both cache components at their own rates" do
      agent = agent_for("claude-3-5-haiku-20241022")
      ctx = context_for(agent, input_tokens: 1000, output_tokens: 500)
      resp = message(model_id: "claude-3-5-haiku-20241022", input_tokens: 1000,
        output_tokens: 500, cached_tokens: 2000, cache_creation_tokens: 800)

      agent.send(:calculate_costs, resp, ctx)

      expect(ctx.input_cost).to be_within(1e-12).of(0.0008)
      expect(ctx.output_cost).to be_within(1e-12).of(0.002)
      expect(ctx[:cost_breakdown]).to eq(cache_read: 0.00016, cache_write: 0.0008)
      expect(ctx.total_cost).to eq(0.00376)
    end
  end

  # ---------------------------------------------------------------------------
  # (4) REASONING MODEL — perplexity/sonar-deep-research
  #     in=1000 out=500 reasoning=300 (reasoning folded into output_tokens)
  #   reasoning_output(3) != output(8) -> reasoning tokens are EXCLUDED from the
  #   output charge and re-added at the reasoning rate (no double counting).
  #   input          = 1000/1e6 * 2 = 0.002
  #   billable_out   = 500 - 300 = 200
  #   output_cost    = 200/1e6 * 8 = 0.0016
  #   thinking(reasoning) = 300/1e6 * 3 = 0.0009  (round6 -> 0.0009)
  #   total          = round6(0.002 + 0.0016 + 0.0009) = 0.0045
  #
  #   Double-count check: naive output (all 500 @ 8) = 0.004; correct = 0.0016.
  #   Difference removed by exclusion = 0.004 - 0.0016 = 0.0024.
  # ---------------------------------------------------------------------------
  describe "(4) reasoning model — no double counting" do
    it "excludes reasoning from output and adds it at the reasoning rate" do
      agent = agent_for("perplexity/sonar-deep-research")
      ctx = context_for(agent, input_tokens: 1000, output_tokens: 500)
      resp = message(model_id: "perplexity/sonar-deep-research",
        input_tokens: 1000, output_tokens: 500, reasoning_tokens: 300)

      # Sanity: the real message reports 300 reasoning tokens.
      expect(resp.reasoning_tokens).to eq(300)

      agent.send(:calculate_costs, resp, ctx)

      expect(ctx.input_cost).to be_within(1e-12).of(0.002)
      # 200 billable output tokens, NOT 500.
      expect(ctx.output_cost).to be_within(1e-12).of(0.0016)
      expect(ctx[:cost_breakdown]).to eq(thinking: 0.0009)
      expect(ctx.total_cost).to eq(0.0045)
    end

    it "removes exactly the reasoning tokens from the output charge (the double-count delta)" do
      # Reasoning exclusion now lives inside calculate_costs via the private
      # reasoning_tokens_charged hook — there is no billable_output_tokens method
      # to call directly. We drive the real path with a RubyLLM::Cost that prices
      # reasoning (thinking:300) so the breakdown records :thinking and the
      # excluded tokens are exactly the reasoning tokens.
      agent = agent_for("perplexity/sonar-deep-research")
      ctx = context_for(agent, input_tokens: 1000, output_tokens: 500)
      resp = double("RubyLLM::Message",
        model_id: "perplexity/sonar-deep-research", reasoning_tokens: 300)
      allow(resp).to receive(:cost).and_return(perplexity_cost(thinking: 300))

      agent.send(:calculate_costs, resp, ctx)

      # 200 billable output tokens (500 - 300 reasoning), NOT 500.
      expect(ctx.output_cost).to be_within(1e-12).of(((500 - 300) / COST_PER_MILLION) * sonar.output)

      # The dollar delta avoided: (500-200)/1e6 * output(8) = 0.0024
      naive_output = (500 / COST_PER_MILLION) * sonar.output
      correct_output = ((500 - 300) / COST_PER_MILLION) * sonar.output
      expect((naive_output - correct_output).round(6)).to eq(0.0024)
    end

    it "never bills reasoning at $0: keeps full output when the cost helper degrades" do
      # If the response's #cost raises (degraded cost helper), no :thinking
      # component is recorded, so reasoning_tokens_charged returns 0 and the
      # reasoning tokens are NOT subtracted from the output charge. They stay in
      # the output at the output rate rather than vanishing (billed at neither
      # the reasoning rate nor zero).
      agent = agent_for("perplexity/sonar-deep-research")
      ctx = context_for(agent, input_tokens: 1000, output_tokens: 500)
      resp = double("RubyLLM::Message",
        model_id: "perplexity/sonar-deep-research", reasoning_tokens: 300)
      allow(resp).to receive(:cost).and_raise(StandardError.new("pricing shape unsupported"))

      agent.send(:calculate_costs, resp, ctx)

      # Full 500 output tokens billed at the output rate — reasoning not excluded.
      expect(ctx.output_cost).to be_within(1e-12).of((500 / COST_PER_MILLION) * sonar.output)
      expect(ctx[:cost_breakdown]).to be_nil
      # input 0.002 + output 0.004 + nothing extra -> 0.006
      expect(ctx.total_cost).to eq(0.006)
    end
  end

  # ---------------------------------------------------------------------------
  # (5) ROUNDING TO 6 DP — gpt-4o
  #   case A: in=333 out=777
  #     input  = 333/1e6 * 2.5 = 0.0008325
  #     output = 777/1e6 * 10  = 0.00777
  #     raw    = 0.0086025  -> round6 = 0.008603  (7th digit 5 rounds up)
  #   case B: in=7 out=13 (float path lands just below the half, truncates down)
  #     input  = 7/1e6 * 2.5  = 1.75e-5
  #     output = 13/1e6 * 10  = 1.3e-4
  #     raw    = 0.00014749999999999998 -> round6 = 0.000147
  #   The pipeline rounds the float sum, so 0.000147 (NOT 0.000148) is correct;
  #   this pins the float rounding path rather than exact-decimal rounding.
  # ---------------------------------------------------------------------------
  describe "(5) rounding to 6 dp" do
    it "rounds the float total up at the 7th decimal (in=333 out=777)" do
      agent = agent_for("gpt-4o")
      ctx = context_for(agent, input_tokens: 333, output_tokens: 777)
      resp = message(model_id: "gpt-4o", input_tokens: 333, output_tokens: 777)

      agent.send(:calculate_costs, resp, ctx)

      expect(ctx.total_cost).to eq(0.008603)
    end

    it "follows the float rounding path, not exact decimal (in=7 out=13)" do
      agent = agent_for("gpt-4o")
      ctx = context_for(agent, input_tokens: 7, output_tokens: 13)
      resp = message(model_id: "gpt-4o", input_tokens: 7, output_tokens: 13)

      agent.send(:calculate_costs, resp, ctx)

      expect(ctx.total_cost).to eq(0.000147)
    end
  end

  # ---------------------------------------------------------------------------
  # (6) MODEL-NOT-FOUND FALLBACK
  #   The response's model_id ("gpt-4o-2099-12-31-preview") is NOT in the
  #   registry, so find_model_info(response.model_id) returns nil and
  #   calculate_costs falls back to find_model_info(model) = the agent's
  #   configured "gpt-4o". Prices come from gpt-4o.
  #   input=1000 out=500 -> 0.0025 / 0.005 / total 0.0075.
  # ---------------------------------------------------------------------------
  describe "(6) model-not-found fallback to configured model" do
    it "prices off the agent's configured model when the response model_id misses" do
      agent = agent_for("gpt-4o")
      ctx = context_for(agent, input_tokens: 1000, output_tokens: 500)
      bogus_id = "gpt-4o-2099-12-31-preview"
      # Confirm the bogus id truly misses the registry (raises -> rescued to nil).
      expect { RubyLLM::Models.find(bogus_id) }.to raise_error(RubyLLM::ModelNotFoundError)

      resp = message(model_id: bogus_id, input_tokens: 1000, output_tokens: 500)

      agent.send(:calculate_costs, resp, ctx)

      expect(ctx.input_cost).to be_within(1e-12).of(0.0025)
      expect(ctx.output_cost).to be_within(1e-12).of(0.005)
      expect(ctx.total_cost).to eq(0.0075)
    end

    it "returns without touching costs when neither model resolves" do
      # Configured model is also bogus -> both lookups nil -> early return.
      # calculate_costs must leave the context's cost fields untouched; we set
      # sentinels and assert they survive (the pipeline default is 0.0, so a
      # nil assertion would be wrong — we prove "no write" with sentinels).
      agent = agent_for("totally-made-up-model-zzz")
      ctx = context_for(agent, input_tokens: 1000, output_tokens: 500)
      ctx.input_cost = -1.0
      ctx.output_cost = -2.0
      ctx.total_cost = -3.0
      resp = message(model_id: "also-bogus-model-yyy", input_tokens: 1000, output_tokens: 500)

      expect { RubyLLM::Models.find("also-bogus-model-yyy") }.to raise_error(RubyLLM::ModelNotFoundError)
      expect { RubyLLM::Models.find("totally-made-up-model-zzz") }.to raise_error(RubyLLM::ModelNotFoundError)

      agent.send(:calculate_costs, resp, ctx)

      expect(ctx.input_cost).to eq(-1.0)
      expect(ctx.output_cost).to eq(-2.0)
      expect(ctx.total_cost).to eq(-3.0)
      expect(ctx[:cost_breakdown]).to be_nil
    end
  end

  # ---------------------------------------------------------------------------
  # (7) ZERO / NIL TOKENS — gpt-4o
  #   zero tokens -> 0.0 input, 0.0 output, 0.0 total, no breakdown.
  #   nil output_tokens -> treated as 0 (context.output_tokens || 0).
  # ---------------------------------------------------------------------------
  describe "(7) zero / nil tokens" do
    it "produces zero cost for zero tokens" do
      agent = agent_for("gpt-4o")
      ctx = context_for(agent, input_tokens: 0, output_tokens: 0)
      resp = message(model_id: "gpt-4o", input_tokens: 0, output_tokens: 0)

      agent.send(:calculate_costs, resp, ctx)

      expect(ctx.input_cost).to eq(0.0)
      expect(ctx.output_cost).to eq(0.0)
      expect(ctx.total_cost).to eq(0.0)
      expect(ctx[:cost_breakdown]).to be_nil
    end

    it "treats nil output_tokens as zero (input still priced)" do
      agent = agent_for("gpt-4o")
      ctx = context_for(agent, input_tokens: 1000, output_tokens: nil)
      resp = message(model_id: "gpt-4o", input_tokens: 1000, output_tokens: nil)

      agent.send(:calculate_costs, resp, ctx)

      expect(ctx.input_cost).to be_within(1e-12).of(0.0025)
      expect(ctx.output_cost).to eq(0.0)
      expect(ctx.total_cost).to eq(0.0025)
    end
  end

  # ---------------------------------------------------------------------------
  # (8) EXECUTION MODEL END-TO-END — total = input + output (the corrected rule)
  #   The Execution before_save calculate_total_cost sets
  #     total_cost = (input_cost || 0) + (output_cost || 0)
  #   and runs ONLY when the caller did not supply an explicit total in the same
  #   save. The guard is:
  #     (input_cost_changed? || output_cost_changed?) && !total_cost_changed?
  #   so:
  #     - total_cost: nil (unchanged from a new record's nil) -> derive input+output
  #     - an explicit total_cost that differs from input+output -> PRESERVED
  #   metadata["cost_breakdown"] is NEVER summed into total_cost — it carries
  #   user-supplied agent data, and a colliding key would corrupt the total.
  # ---------------------------------------------------------------------------
  describe "(8) Execution model total = input + output (end-to-end)" do
    it "derives total_cost = input + output when no explicit total is given (total_cost: nil)" do
      # total_cost: nil leaves total_cost_changed? false for a new record, so the
      # before_save derives it from the components.
      ex = build(
        :execution,
        model_id: "claude-3-5-haiku-20241022",
        input_tokens: 1000,
        output_tokens: 500,
        input_cost: 0.0008,
        output_cost: 0.002,
        total_cost: nil
      )
      ex.save!
      ex.reload

      # 0.0008 + 0.002 = 0.0028 (breakdown NOT involved)
      expect(ex.total_cost).to eq(BigDecimal("0.0028"))
      expect(ex.input_cost).to eq(BigDecimal("0.0008"))
      expect(ex.output_cost).to eq(BigDecimal("0.002"))
    end

    it "preserves an explicit total_cost that differs from input + output" do
      # The pipeline records a cache/reasoning-aware total alongside the
      # components. Supplying it explicitly must NOT collapse it to input+output.
      explicit_total = 0.00376 # e.g. the (3) claude figure incl. cache components
      ex = build(
        :execution,
        model_id: "claude-3-5-haiku-20241022",
        input_tokens: 1000,
        output_tokens: 500,
        input_cost: 0.0008,
        output_cost: 0.002,
        total_cost: explicit_total
      )
      ex.save!
      ex.reload

      # input + output would be 0.0028, but the explicit total survives.
      expect(ex.total_cost).to eq(BigDecimal("0.00376"))
      expect(ex.total_cost).not_to eq(BigDecimal("0.0028"))
    end

    it "never sums metadata cost_breakdown into total_cost" do
      # metadata merges user-supplied agent data; a "cost_breakdown" key there
      # must not influence total_cost. With total_cost: nil the model derives
      # purely from input + output.
      ex = build(
        :execution,
        model_id: "gpt-4o",
        input_tokens: 1000,
        output_tokens: 500,
        input_cost: 0.0025,
        output_cost: 0.005,
        total_cost: nil,
        metadata: {"cost_breakdown" => {"foo" => 99.0}}
      )
      ex.save!
      ex.reload

      # 0.0025 + 0.005 = 0.0075; the bogus 99.0 in metadata is ignored.
      expect(ex.total_cost).to eq(BigDecimal("0.0075"))
    end

    it "matches the pipeline result fed into a persisted Execution end-to-end" do
      # Drive the real pipeline cost calc, then persist its full total (which
      # already includes cache components) explicitly so it is preserved, and
      # confirm the model's stored total reconciles with the pipeline's.
      agent = agent_for("claude-3-5-haiku-20241022")
      ctx = context_for(agent, input_tokens: 1000, output_tokens: 500)
      resp = message(model_id: "claude-3-5-haiku-20241022", input_tokens: 1000,
        output_tokens: 500, cached_tokens: 2000, cache_creation_tokens: 800)
      agent.send(:calculate_costs, resp, ctx)

      ex = build(
        :execution,
        model_id: "claude-3-5-haiku-20241022",
        input_tokens: 1000,
        output_tokens: 500,
        input_cost: ctx.input_cost,
        output_cost: ctx.output_cost,
        total_cost: ctx.total_cost
      )
      ex.save!
      ex.reload

      # The pipeline's cache-aware total (0.00376) is persisted as-is, not
      # collapsed to the text-only input + output sum (0.0028).
      expect(ctx.total_cost).to eq(0.00376)
      expect(ex.total_cost).to eq(BigDecimal("0.00376"))
      expect(ex.total_cost.to_f).to be_within(1e-9).of(ctx.total_cost)
    end
  end
end
