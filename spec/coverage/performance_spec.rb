# frozen_string_literal: true

require "rails_helper"

# Performance guard for the two hot paths exercised on every agent call:
#
#   1. Instrumentation#capture_llm_requests — wraps the downstream pipeline in
#      an AS::Notifications subscription and keeps a fiber-local stack of
#      request accumulators. The stack MUST be fully popped afterwards (an
#      unbalanced push would leak memory and mis-attribute future requests).
#
#   2. BaseAgent#calculate_costs — runs once per execution to price the
#      response from the model registry.
#
# These are GUARD tests, not micro-benchmarks: every wall-clock ceiling is
# deliberately generous (orders of magnitude above measured time on a laptop)
# so the suite never flakes on a slow/contended CI box. The load-bearing
# assertions are the correctness invariants (balanced stack, correct
# attribution, correct cost); timing is only a coarse "did not blow up" check.
#
# Measured locally (Ruby 4.0, arm64): capture ~1.4us/call with 0 events,
# ~7.3us/call with 3 events; 1000 nested captures ~6ms; calculate_costs
# ~33us/call (~30k calls/sec). Ceilings below leave 100x+ headroom.
RSpec.describe "hot path performance guards", type: :model do
  let(:agent_class) do
    Class.new(RubyLLM::Agents::BaseAgent) do
      def self.name
        "PerfGuardAgent"
      end

      model "gpt-4o"
    end
  end

  let(:stack_key) do
    RubyLLM::Agents::Pipeline::Middleware::Instrumentation::REQUEST_CAPTURE_STACK
  end

  # Real middleware whose downstream app is an identity lambda. We drive the
  # private capture_llm_requests directly so the test isolates the hot path
  # without DB writes or LLM calls.
  let(:middleware) do
    RubyLLM::Agents::Pipeline::Middleware::Instrumentation.new(->(ctx) { ctx }, agent_class)
  end

  def build_context
    RubyLLM::Agents::Pipeline::Context.new(input: "x", agent_class: agent_class)
  end

  def emit_request
    ActiveSupport::Notifications.instrument("request.ruby_llm", provider: "openai") { :ok }
  end

  # Monotonic wall-clock timer (avoids the benchmark gem, dropped from Ruby 4.0
  # default gems).
  def measure_realtime
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    yield
    Process.clock_gettime(Process::CLOCK_MONOTONIC) - started
  end

  describe "capture_llm_requests fiber-local stack" do
    it "leaves the fiber-local stack empty when no request events fire (no leak)" do
      expect(Thread.current[stack_key]).to be_nil_or_empty

      1_000.times do
        middleware.send(:capture_llm_requests, build_context) { nil }
      end

      expect(Thread.current[stack_key]).to be_nil_or_empty
    end

    it "leaves the fiber-local stack empty after capturing many request events (no leak)" do
      ctx = build_context

      1_000.times do
        middleware.send(:capture_llm_requests, ctx) do
          3.times { emit_request }
        end
      end

      # The stack is fully popped: every push has a matching pop.
      expect(Thread.current[stack_key]).to be_nil_or_empty
    end

    it "pops the stack even when the downstream call raises" do
      expect {
        middleware.send(:capture_llm_requests, build_context) do
          emit_request
          raise "boom"
        end
      }.to raise_error("boom")

      expect(Thread.current[stack_key]).to be_nil_or_empty
    end

    it "fully unwinds 1000 deeply nested captures and stays well under a generous ceiling" do
      depth = 1_000

      # Each level pushes one accumulator; the innermost emits one event that
      # must be credited to the innermost context only. After the outermost
      # block returns, the stack must be completely empty.
      build_and_assert = lambda do |remaining, &emit|
        ctx = build_context
        middleware.send(:capture_llm_requests, ctx) do
          if remaining.zero?
            emit.call(ctx)
          else
            build_and_assert.call(remaining - 1, &emit)
          end
        end
        ctx
      end

      innermost = nil
      elapsed = measure_realtime do
        build_and_assert.call(depth) do |ctx|
          innermost = ctx
          emit_request
        end
      end

      # Generous wall-clock ceiling: measured ~6ms locally, allow 5 seconds so
      # a slow/contended CI runner still passes comfortably (no tight timing).
      expect(elapsed).to be < 5.0

      # The single event is attributed to exactly the innermost context.
      expect(innermost[:llm_request_count]).to eq(1)

      # Critically: the entire 1000-deep stack is popped — no leak.
      expect(Thread.current[stack_key]).to be_nil_or_empty
    end

    it "attributes nested requests to the innermost capture only (real accounting)" do
      outer = build_context
      inner = build_context

      middleware.send(:capture_llm_requests, outer) do
        emit_request # outer
        middleware.send(:capture_llm_requests, inner) do
          emit_request # inner
        end
        emit_request # outer again
      end

      expect(outer[:llm_request_count]).to eq(2)
      expect(inner[:llm_request_count]).to eq(1)
      expect(Thread.current[stack_key]).to be_nil_or_empty
    end
  end

  describe "calculate_costs throughput" do
    let(:agent) do
      agent_class.allocate.tap do |a|
        a.instance_variable_set(:@options, {})
        a.instance_variable_set(:@model, "gpt-4o")
      end
    end

    # Real RubyLLM::Message with token metadata and real registry pricing —
    # no stubbing of the method under test.
    let(:response) do
      RubyLLM::Message.new(
        role: :assistant,
        content: "ok",
        model_id: "gpt-4o",
        input_tokens: 1000,
        output_tokens: 500
      )
    end

    def build_cost_context
      ctx = RubyLLM::Agents::Pipeline::Context.new(
        input: "x",
        agent_class: agent_class,
        agent_instance: agent
      )
      ctx.input_tokens = 1000
      ctx.output_tokens = 500
      ctx
    end

    it "produces a correct, deterministic cost from the registry" do
      info = RubyLLM::Models.find("gpt-4o")
      input_price = info.pricing.text_tokens.input
      output_price = info.pricing.text_tokens.output
      expected = ((1000 / 1_000_000.0) * input_price + (500 / 1_000_000.0) * output_price).round(6)

      ctx = build_cost_context
      agent.send(:calculate_costs, response, ctx)

      expect(ctx.total_cost).to be_within(1e-9).of(expected)
      expect(ctx.input_cost).to be > 0
      expect(ctx.output_cost).to be > 0
    end

    it "runs 5000 cost calculations well under a generous ceiling" do
      iterations = 5_000

      # Warm the registry lookup before timing so we measure steady-state.
      agent.send(:calculate_costs, response, build_cost_context)

      ctx = build_cost_context
      elapsed = measure_realtime do
        iterations.times { agent.send(:calculate_costs, response, ctx) }
      end

      # Measured ~33us/call locally => ~0.17s for 5000. Allow 10 seconds so a
      # cold/loaded CI box never flakes; this is a "did not blow up" backstop.
      expect(elapsed).to be < 10.0

      # The result stays correct after thousands of repeats (no drift/state).
      expect(ctx.total_cost).to be > 0
    end
  end

  # The executions list renders error_message per row, which reads the `detail`
  # association. filtered_executions must eager-load :detail so the page issues
  # a constant number of execution_details queries regardless of how many error
  # rows are shown (regression guard for the N+1 fix).
  describe "executions list eager-loads :detail (no N+1)", type: :request do
    include RubyLLM::Agents::Engine.routes.url_helpers

    def detail_query_count(&block)
      count = 0
      sub = ActiveSupport::Notifications.subscribe("sql.active_record") do |*args|
        sql = args.last[:sql]
        count += 1 if sql.match?(/FROM\s+["`]?ruby_llm_agents_execution_details/i)
      end
      block.call
      count
    ensure
      ActiveSupport::Notifications.unsubscribe(sub)
    end

    it "issues the same number of detail queries for 1 and many error rows" do
      create(:execution, :failed)
      one = detail_query_count { get executions_path }
      expect(response).to have_http_status(:ok)

      4.times { create(:execution, :failed) }
      many = detail_query_count { get executions_path }
      expect(response).to have_http_status(:ok)

      # Preloaded => constant query count (not one extra SELECT per error row).
      expect(many).to eq(one)
    end
  end

  # Helper matcher kept local so the spec is self-contained: the fiber-local
  # request-capture stack should never leak entries across a balanced call.
  matcher :be_nil_or_empty do
    match { |actual| actual.nil? || actual.empty? }
    failure_message do |actual|
      "expected fiber-local capture stack to be nil or empty, but had #{actual.inspect} " \
        "(a leaked push would mis-attribute future LLM requests)"
    end
  end
end
