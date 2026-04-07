# frozen_string_literal: true

require "rails_helper"

# Regression specs proving issues found during deep dive review.
# Each describe block demonstrates a specific bug or code quality issue.
RSpec.describe "Review issue regressions" do
  # ── Issue 1: Prior period boundary overlap ────────────────────────
  #
  # AnalyticsController#prior_period_scope uses an inclusive range that
  # can overlap with the current period at the boundary. While the exact
  # boundary varies by time precision, the pattern is fragile.
  # We verify the fix uses exclusive boundaries.
  describe "AnalyticsController prior period boundary" do
    it "prior_period_scope end should be exclusive of the current period start" do
      source = File.read(
        Rails.root.join("../../app/controllers/ruby_llm/agents/analytics_controller.rb")
      )

      # The prior period should end BEFORE the current period starts.
      # The fix uses exclusive range (...) so @days.days.ago is not in both periods.
      has_exclusive_boundary = source.include?("(@days * 2).days.ago...@days.days.ago")
      expect(has_exclusive_boundary).to be(true),
        "Prior period scope should use exclusive range (...) to avoid boundary overlap"
    end
  end

  # ── Issue 2: check_total_timeout! math bug ────────────────────────
  #
  # The TotalTimeoutError was created with: timeout_value = deadline - started_at + elapsed
  # which added the elapsed time twice. Fixed to: timeout_value = deadline - started_at
  describe "Reliability#check_total_timeout! reports correct timeout value" do
    it "reports the configured timeout, not an inflated value" do
      middleware_class = RubyLLM::Agents::Pipeline::Middleware::Reliability

      # Directly test the private method via a test subclass
      test_instance = middleware_class.allocate
      test_instance.instance_variable_set(:@app, nil)
      test_instance.instance_variable_set(:@agent_class, nil)

      started_at = Time.current - 6.seconds  # started 6 seconds ago
      deadline = started_at + 5.seconds       # deadline was 5 seconds after start

      # Time.current is now past the deadline
      error = nil
      begin
        test_instance.send(:check_total_timeout!, deadline, started_at)
      rescue RubyLLM::Agents::Reliability::TotalTimeoutError => e
        error = e
      end

      expect(error).not_to be_nil, "Expected TotalTimeoutError to be raised"
      expect(error.timeout_seconds).to eq(5),
        "Expected timeout_seconds=5 (configured), got #{error.timeout_seconds}"
      expect(error.elapsed_seconds).to be >= 5,
        "Expected elapsed_seconds >= 5, got #{error.elapsed_seconds}"
    end
  end

  # ── Issue 3: CHART_AGENT_LIMIT dead code removed ────────────────────
  describe "AnalyticsController does not contain dead code" do
    it "does not define unused CHART_AGENT_LIMIT constant" do
      source = File.read(
        Rails.root.join("../../app/controllers/ruby_llm/agents/analytics_controller.rb")
      )

      expect(source).not_to include("CHART_AGENT_LIMIT"),
        "CHART_AGENT_LIMIT should have been removed — it was dead code"
    end
  end

  # ── Issue 4: Budget middleware does two tenant lookups ─────────────
  describe "Budget middleware tenant lookup efficiency" do
    let(:agent_class) do
      Class.new do
        def self.name = "BudgetTestAgent"
        def self.agent_type = :conversation
        def self.model = "test-model"
      end
    end

    before do
      RubyLLM::Agents.reset_configuration!
      RubyLLM::Agents.configure do |c|
        c.budgets = {
          enforcement: :hard,
          global_daily: 100.0,
          global_monthly: 1000.0
        }
      end
    end

    after { RubyLLM::Agents.reset_configuration! }

    it "does not query Tenant.find_by twice for the same tenant_id" do
      RubyLLM::Agents::Tenant.create!(tenant_id: "budget_test_tenant")
      context = RubyLLM::Agents::Pipeline::Context.new(
        input: "test",
        agent_class: agent_class,
        model: "test-model"
      )
      context.tenant_id = "budget_test_tenant"
      context.output = "result"
      context.input_tokens = 10
      context.output_tokens = 5
      context.total_cost = 0.001

      app = double("app")
      allow(app).to receive(:call) { |ctx| ctx }

      middleware = RubyLLM::Agents::Pipeline::Middleware::Budget.new(app, agent_class)

      # Count how many times Tenant.find_by is called
      find_by_count = 0
      allow(RubyLLM::Agents::Tenant).to receive(:find_by).and_wrap_original do |method, *args|
        find_by_count += 1
        method.call(*args)
      end

      middleware.call(context)

      expect(find_by_count).to be <= 1,
        "Budget middleware called Tenant.find_by #{find_by_count} times for the same tenant_id — should be at most 1"
    end
  end

  # ── Issue 5: trend_analysis fires N queries per day ────────────────
  describe "Execution.trend_analysis query count" do
    it "does not fire more queries than necessary for a 7-day analysis" do
      # Create some executions across multiple days
      7.times do |i|
        create(:execution, created_at: i.days.ago)
      end

      query_count = 0
      callback = lambda { |_name, _start, _finish, _id, _payload|
        query_count += 1
      }

      ActiveSupport::Notifications.subscribed(callback, "sql.active_record") do
        RubyLLM::Agents::Execution.trend_analysis(days: 7)
      end

      # A well-optimized implementation should use ~1-3 queries (GROUP BY).
      # The current implementation fires ~4 queries per day (28+ for 7 days).
      expect(query_count).to be <= 10,
        "trend_analysis fired #{query_count} queries for 7 days — should use GROUP BY (expected <= 10)"
    end
  end

  # ── Issue 6: daily_report fires many individual queries ────────────
  describe "Execution.daily_report query count" do
    it "does not fire excessive individual queries" do
      create_list(:execution, 3)
      create(:execution, :failed)

      query_count = 0
      callback = lambda { |_name, _start, _finish, _id, _payload|
        query_count += 1
      }

      ActiveSupport::Notifications.subscribed(callback, "sql.active_record") do
        RubyLLM::Agents::Execution.daily_report
      end

      # A well-optimized implementation should use ~3-5 queries.
      # The current implementation fires ~9+ individual count/sum queries.
      expect(query_count).to be <= 7,
        "daily_report fired #{query_count} queries — should consolidate with conditional aggregation (expected <= 7)"
    end
  end

  # ── Issue 7: Original analytics savings spec uses conditional assertion ──
  #
  # The existing analytics_controller_spec.rb (lines 124-128) has:
  #   if savings
  #     expect(savings[:expensive_model]).to eq("gpt-4o")
  #   end
  # This passes silently when @savings is nil, masking potential failures.
  # This is a test quality issue, not a code bug.
  describe "Original analytics savings spec conditional assertion" do
    it "proves the conditional assertion pattern silently passes when nil" do
      # This demonstrates the anti-pattern: conditional assertions hide failures
      savings = nil # simulating what happens when @savings is nil

      # The original spec does this — it passes even though savings is nil:
      original_would_pass = true
      if savings
        original_would_pass = (savings[:expensive_model] == "gpt-4o")
      end
      expect(original_would_pass).to be(true) # proves the conditional is meaningless

      # The correct pattern should be:
      # expect(savings).not_to be_nil
      # expect(savings[:expensive_model]).to eq("gpt-4o")
    end
  end

  # ── Issue 8: raw helper usage in analytics view ─────────────────────
  #
  # The view uses `raw ... .to_json` to inject data into JavaScript.
  # While .to_json escapes angle brackets in strings, using `raw` is
  # bad practice. The view should use `json_escape` instead.
  describe "Analytics view does not use raw helper for user data" do
    it "uses json_escape instead of raw for data injection" do
      source = File.read(
        Rails.root.join("../../app/views/ruby_llm/agents/analytics/index.html.erb")
      )

      # Ensure no lines use `raw` with dynamic data
      raw_with_data = source.lines.select { |l| l.include?("raw @") || l.include?("raw(") }

      expect(raw_with_data).to be_empty,
        "Analytics view uses `raw` with dynamic data (#{raw_with_data.size} occurrences). " \
        "Use .to_json.html_safe instead"
    end
  end
end
