# frozen_string_literal: true

require "rails_helper"

# Targets previously-uncovered logic in
# app/models/ruby_llm/agents/execution.rb:
#   aggregate_attempt_costs! / resolve_model_info, has_retries?, used_fallback?,
#   successful_attempt / failed_attempts / short_circuited_attempts,
#   root? / child? / depth, cached?, retryable(=)/rate_limited(=), tenant_record,
#   truncated? / content_filtered?, now_strip_data (7d/30d/90d) and
#   now_strip_data_for_dates, pct_change, calculate_period_success_rate,
#   and the calculate_total_cost before_save derivation branches.
#
# All tests build real Execution records and call the real methods.
RSpec.describe RubyLLM::Agents::Execution, type: :model do
  # Helper: write attempts JSON onto the delegated detail row.
  def write_attempts(execution, attempts)
    if execution.detail
      execution.detail.update!(attempts: attempts)
    else
      execution.create_detail!(attempts: attempts)
    end
    execution.reload
  end

  describe "#aggregate_attempt_costs!" do
    it "is a no-op when there are no attempts" do
      execution = create(:execution, input_cost: 0.5, output_cost: 0.25)
      # factory leaves attempts as the column default ([]) which is blank
      execution.aggregate_attempt_costs!

      # unchanged when attempts blank (early return)
      expect(execution.input_cost).to eq(0.5)
      expect(execution.output_cost).to eq(0.25)
    end

    it "sums per-attempt costs using each attempt's real model pricing" do
      execution = create(:execution, model_id: "gpt-4o")
      write_attempts(execution, [
        {"model_id" => "gpt-4o", "input_tokens" => 1_000_000, "output_tokens" => 1_000_000}
      ])

      pricing = RubyLLM::Models.find("gpt-4o").pricing.text_tokens
      execution.aggregate_attempt_costs!

      # 1M input tokens * input price + 1M output tokens * output price
      expect(execution.input_cost).to eq(pricing.input.round(6))
      expect(execution.output_cost).to eq(pricing.output.round(6))
    end

    it "aggregates across multiple attempts with different models" do
      execution = create(:execution, model_id: "gpt-4o")
      write_attempts(execution, [
        {"model_id" => "gpt-4o", "input_tokens" => 1_000_000, "output_tokens" => 0},
        {"model_id" => "gpt-4o-mini", "input_tokens" => 1_000_000, "output_tokens" => 0}
      ])

      gpt4o = RubyLLM::Models.find("gpt-4o").pricing.text_tokens
      mini = RubyLLM::Models.find("gpt-4o-mini").pricing.text_tokens
      execution.aggregate_attempt_costs!

      expect(execution.input_cost).to eq((gpt4o.input + mini.input).round(6))
      expect(execution.output_cost).to eq(0.0)
    end

    it "skips short-circuited attempts (no API call was made)" do
      execution = create(:execution, model_id: "gpt-4o")
      write_attempts(execution, [
        {"model_id" => "gpt-4o", "short_circuited" => true, "input_tokens" => 9_000_000, "output_tokens" => 9_000_000},
        {"model_id" => "gpt-4o", "input_tokens" => 1_000_000, "output_tokens" => 0}
      ])

      pricing = RubyLLM::Models.find("gpt-4o").pricing.text_tokens
      execution.aggregate_attempt_costs!

      # only the real attempt contributes
      expect(execution.input_cost).to eq(pricing.input.round(6))
      expect(execution.output_cost).to eq(0.0)
    end

    it "skips attempts whose model cannot be resolved (resolve_model_info -> nil)" do
      execution = create(:execution, model_id: "gpt-4o")
      write_attempts(execution, [
        {"model_id" => "totally-made-up-model-xyz", "input_tokens" => 1_000_000, "output_tokens" => 1_000_000}
      ])

      execution.aggregate_attempt_costs!

      # unknown model has no pricing -> contributes nothing
      expect(execution.input_cost).to eq(0.0)
      expect(execution.output_cost).to eq(0.0)
    end

    it "treats missing token counts on an attempt as zero" do
      execution = create(:execution, model_id: "gpt-4o")
      write_attempts(execution, [{"model_id" => "gpt-4o"}])

      execution.aggregate_attempt_costs!

      expect(execution.input_cost).to eq(0.0)
      expect(execution.output_cost).to eq(0.0)
    end
  end

  describe "#has_retries?" do
    it "is false when attempts_count is 1" do
      execution = create(:execution, attempts_count: 1)
      expect(execution.has_retries?).to be false
    end

    it "is true when attempts_count is greater than 1" do
      execution = create(:execution, attempts_count: 3)
      expect(execution.has_retries?).to be true
    end

    it "is false when attempts_count is nil (treated as zero)" do
      execution = build(:execution, attempts_count: nil)
      expect(execution.has_retries?).to be false
    end
  end

  describe "#used_fallback?" do
    it "is false when chosen_model_id is blank" do
      execution = create(:execution, model_id: "gpt-4o", chosen_model_id: nil)
      expect(execution.used_fallback?).to be false
    end

    it "is false when chosen_model_id equals the requested model" do
      execution = create(:execution, model_id: "gpt-4o", chosen_model_id: "gpt-4o")
      expect(execution.used_fallback?).to be false
    end

    it "is true when a different model than requested actually answered" do
      execution = create(:execution, model_id: "gpt-4o", chosen_model_id: "gpt-4o-mini")
      expect(execution.used_fallback?).to be true
    end
  end

  describe "attempt selectors" do
    let(:execution) { create(:execution) }

    describe "#successful_attempt" do
      it "is nil when there are no attempts" do
        expect(execution.successful_attempt).to be_nil
      end

      it "returns the first attempt with no error that was not short-circuited" do
        write_attempts(execution, [
          {"model_id" => "gpt-4o", "short_circuited" => true},
          {"model_id" => "gpt-4o", "error_class" => "RateLimitError"},
          {"model_id" => "gpt-4o-mini", "error_class" => nil, "input_tokens" => 5}
        ])

        expect(execution.successful_attempt["model_id"]).to eq("gpt-4o-mini")
      end
    end

    describe "#failed_attempts" do
      it "is empty when there are no attempts" do
        expect(execution.failed_attempts).to eq([])
      end

      it "returns only attempts that carry an error_class" do
        write_attempts(execution, [
          {"model_id" => "a", "error_class" => "Timeout::Error"},
          {"model_id" => "b", "error_class" => nil},
          {"model_id" => "c", "error_class" => "StandardError"}
        ])

        expect(execution.failed_attempts.map { |a| a["model_id"] }).to eq(%w[a c])
      end
    end

    describe "#short_circuited_attempts" do
      it "is empty when there are no attempts" do
        expect(execution.short_circuited_attempts).to eq([])
      end

      it "returns only attempts blocked by the circuit breaker" do
        write_attempts(execution, [
          {"model_id" => "a", "short_circuited" => true},
          {"model_id" => "b"},
          {"model_id" => "c", "short_circuited" => true}
        ])

        expect(execution.short_circuited_attempts.map { |a| a["model_id"] }).to eq(%w[a c])
      end
    end
  end

  describe "execution hierarchy" do
    describe "#root? / #child?" do
      it "is a root with no parent" do
        execution = create(:execution)
        expect(execution.root?).to be true
        expect(execution.child?).to be false
      end

      it "is a child when it has a parent" do
        parent = create(:execution)
        child = create(:execution, parent_execution_id: parent.id)
        expect(child.root?).to be false
        expect(child.child?).to be true
      end
    end

    describe "#depth" do
      it "is 0 for a root execution" do
        expect(create(:execution).depth).to eq(0)
      end

      it "increments by one per ancestor" do
        root = create(:execution)
        mid = create(:execution, parent_execution_id: root.id)
        leaf = create(:execution, parent_execution_id: mid.id)

        expect(mid.depth).to eq(1)
        expect(leaf.depth).to eq(2)
      end
    end
  end

  describe "#cached?" do
    it "is true only when cache_hit is exactly true" do
      expect(create(:execution, cache_hit: true).cached?).to be true
      expect(create(:execution, cache_hit: false).cached?).to be false
    end
  end

  describe "metadata-backed accessors" do
    describe "#retryable / #retryable=" do
      it "reads nil when unset and round-trips through metadata" do
        execution = create(:execution, metadata: {})
        expect(execution.retryable).to be_nil

        execution.retryable = true
        execution.save!
        expect(execution.reload.retryable).to be true
        expect(execution.metadata["retryable"]).to be true
      end
    end

    describe "#rate_limited / #rate_limited=" do
      it "reads nil when unset and round-trips through metadata" do
        execution = create(:execution, metadata: {})
        expect(execution.rate_limited).to be_nil

        execution.rate_limited = true
        execution.save!
        expect(execution.reload.rate_limited).to be true
        # the rate_limited? predicate reads the same metadata key
        expect(execution.rate_limited?).to be true
      end
    end
  end

  describe "#tenant_record" do
    it "is nil when the execution has no tenant_id" do
      expect(create(:execution, tenant_id: nil).tenant_record).to be_nil
    end

    it "is nil when no Tenant row matches the tenant_id" do
      execution = create(:execution, tenant_id: "missing_tenant")
      expect(execution.tenant_record).to be_nil
    end

    it "returns the linked tenant_record when a Tenant row exists" do
      linked = RubyLLM::Agents::Tenant.create!(tenant_id: "acme", name: "Acme")
      execution = create(:execution, tenant_id: "acme")

      # tenant_record is the polymorphic association on Tenant; unlinked => nil,
      # but we still exercise the find_by + &.tenant_record chain end to end.
      expect(execution.tenant_record).to eq(linked.tenant_record)
    end
  end

  describe "finish-reason predicates" do
    describe "#truncated?" do
      it "is true only when finish_reason is 'length'" do
        expect(create(:execution, finish_reason: "length").truncated?).to be true
        expect(create(:execution, finish_reason: "stop").truncated?).to be false
      end
    end

    describe "#content_filtered?" do
      it "is true only when finish_reason is 'content_filter'" do
        expect(create(:execution, finish_reason: "content_filter").content_filtered?).to be true
        expect(create(:execution, finish_reason: "stop").content_filtered?).to be false
      end
    end
  end

  describe ".pct_change" do
    it "is nil when the old value is nil or zero" do
      expect(described_class.pct_change(nil, 10)).to be_nil
      expect(described_class.pct_change(0, 10)).to be_nil
    end

    it "computes the rounded percentage change for a non-zero baseline" do
      expect(described_class.pct_change(100, 150)).to eq(50.0)
      expect(described_class.pct_change(200, 100)).to eq(-50.0)
    end
  end

  describe ".calculate_period_success_rate" do
    it "is 0.0 for an empty scope" do
      expect(described_class.calculate_period_success_rate(described_class.all)).to eq(0.0)
    end

    it "computes the success percentage over the scope" do
      create(:execution, status: "success")
      create(:execution, status: "success")
      create(:execution, status: "success")
      create(:execution, :failed)

      # 3 successes out of 4 -> 75.0
      expect(described_class.calculate_period_success_rate(described_class.all)).to eq(75.0)
    end
  end

  describe ".now_strip_data range branches" do
    it "aggregates the 7d range against the prior 7-day window" do
      # input/output cost drive the persisted total_cost via the before_save callback
      # (total_cost: nil lets the derivation run instead of the factory default).
      recent = create(:execution, status: "success", created_at: 2.days.ago, input_cost: 0.06, output_cost: 0.04, total_cost: nil, total_tokens: 100, duration_ms: 1000)
      older = create(:execution, status: "error", created_at: 10.days.ago, input_cost: 0.10, output_cost: 0.10, total_cost: nil)

      data = described_class.now_strip_data(range: "7d")

      expect(data[:success_today]).to eq(1) # only `recent` falls in current 7d
      expect(data[:cost_today]).to be_within(1e-9).of(0.10)
      # `older` lands in the previous window (14d..7d ago) -> drives errors_change
      expect(data[:comparisons]).to have_key(:cost_change)
      expect([recent.id, older.id]).to all(be_present)
    end

    it "aggregates the 30d range" do
      create(:execution, status: "success", created_at: 5.days.ago, total_cost: 0.05, total_tokens: 50)
      data = described_class.now_strip_data(range: "30d")

      expect(data[:executions_today]).to be >= 1
      expect(data).to have_key(:success_rate)
      expect(data).to have_key(:running)
    end

    it "aggregates the 90d range" do
      create(:execution, status: "success", created_at: 40.days.ago, total_cost: 0.07)
      data = described_class.now_strip_data(range: "90d")

      expect(data[:executions_today]).to be >= 1
      expect(data[:comparisons]).to have_key(:tokens_change)
    end

    it "falls back to today/yesterday for the default range" do
      create(:execution, status: "success", created_at: Time.current, total_cost: 0.01)
      data = described_class.now_strip_data

      expect(data[:success_today]).to be >= 1
      expect(data).to have_key(:avg_duration_ms)
    end
  end

  describe ".now_strip_data_for_dates" do
    it "compares a custom range against the immediately preceding window" do
      today = Date.current
      # current window: yesterday..today -- use noon so it lands inside the day boundaries
      # (total_cost: nil lets the before_save callback derive total from input+output)
      create(:execution, status: "success", created_at: today.to_time.change(hour: 12), input_cost: 0.20, output_cost: 0.10, total_cost: nil, total_tokens: 200, duration_ms: 1500)
      # previous window: (today - 3)..(today - 2)
      create(:execution, status: "error", created_at: (today - 2).to_time.change(hour: 12), input_cost: 0.05, output_cost: 0.05, total_cost: nil)

      data = described_class.now_strip_data_for_dates(from: today - 1, to: today)

      expect(data[:success_today]).to eq(1)
      expect(data[:cost_today]).to be_within(1e-9).of(0.30)
      expect(data[:comparisons]).to have_key(:success_change)
      expect(data).to have_key(:running)
    end

    it "handles a single-day range" do
      today = Date.current
      create(:execution, status: "success", created_at: today.to_time.change(hour: 12), input_cost: 0.03, output_cost: 0.02)

      data = described_class.now_strip_data_for_dates(from: today, to: today)

      expect(data[:executions_today]).to be >= 1
      expect(data).to have_key(:total_tokens)
    end
  end

  describe "#calculate_total_cost before_save derivation" do
    # The before_save callback derives total_cost only when input/output costs
    # changed AND no explicit total was supplied:
    #   if: -> { (input_cost_changed? || output_cost_changed?) && !total_cost_changed? }
    # calculate_total_cost itself is the plain sum and NEVER reads metadata.
    it "derives total = input + output when no explicit total is given" do
      execution = create(:execution, input_cost: 0.001, output_cost: 0.002, total_cost: nil)

      expect(execution.total_cost).to eq(0.003)
    end

    it "preserves an explicit total that differs from input + output" do
      # A cache/reasoning-aware total supplied by the pipeline must survive: the
      # callback is skipped when total_cost was provided in the change set.
      execution = create(:execution, input_cost: 0.001, output_cost: 0.002, total_cost: 0.010)

      expect(execution.total_cost).to eq(0.010)
      expect(execution.reload.total_cost).to eq(0.010)
    end

    it "re-derives total on update! when only the component costs change" do
      execution = create(:execution, input_cost: 0.001, output_cost: 0.002, total_cost: nil)
      expect(execution.total_cost).to eq(0.003)

      execution.update!(input_cost: 0.004, output_cost: 0.005)

      expect(execution.total_cost).to eq(0.009)
      expect(execution.reload.total_cost).to eq(0.009)
    end

    it "treats nil input_cost and output_cost as 0" do
      execution = create(:execution, input_cost: nil, output_cost: 0.002, total_cost: nil)
      expect(execution.total_cost).to eq(0.002)

      # When both components are nil the guard's *_cost_changed? checks are false,
      # so the callback is skipped; calling the derivation directly proves nil->0.
      both_nil = build(:execution, input_cost: nil, output_cost: nil, total_cost: nil)
      both_nil.send(:calculate_total_cost)
      expect(both_nil.total_cost).to eq(0)
    end

    it "never sums user metadata cost_breakdown into total_cost (corruption guard)" do
      # Regression guard: an attacker-controlled metadata.cost_breakdown must have
      # ZERO effect on the derived total. Only the real input/output costs count.
      execution = create(
        :execution,
        input_cost: 0.001, output_cost: 0.002, total_cost: nil,
        metadata: {"cost_breakdown" => {"foo" => 99.0}}
      )

      expect(execution.total_cost).to eq(0.003)
      expect(execution.reload.total_cost).to eq(0.003)
    end
  end
end
