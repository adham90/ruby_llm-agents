# frozen_string_literal: true

require "rails_helper"

# How the dashboard behaves when the executions table is too large to
# aggregate freely: which queries each page is allowed to run, what is cached,
# and what the user sees when the database gives up on one.
RSpec.describe "Dashboard on a large executions table", type: :request do
  let(:paths) { RubyLLM::Agents::Engine.routes.url_helpers }
  let(:execution_class) { RubyLLM::Agents::Execution }
  let(:postgres) { execution_class.connection.adapter_name.downcase.include?("postg") }

  after { RubyLLM::Agents.reset_configuration! }

  def executions_sql(queries)
    queries.grep(/FROM "ruby_llm_agents_executions"/)
  end

  def aggregates(queries)
    executions_sql(queries).grep(/COUNT\(|SUM\(|AVG\(|MAX\(|GROUP BY/)
  end

  # Stands in for the database cancelling a statement, which SQLite cannot do.
  def cancel(method)
    allow(execution_class).to receive(method).and_raise(ActiveRecord::QueryCanceled, "canceling statement due to statement timeout")
  end

  def with_memory_cache
    allow(Rails).to receive(:cache).and_return(ActiveSupport::Cache::MemoryStore.new)
  end

  describe "executions list" do
    before { RubyLLM::Agents.configure { |c| c.per_page = 5 } }

    it "pages with one aggregate and no standalone COUNT" do
      create_list(:execution, 12)

      queries = capture_sql { get paths.executions_path }

      expect(response).to have_http_status(:ok)
      expect(aggregates(queries).size).to eq(1)
      expect(response.body).to include("1-5 of 12")
    end

    context "when the totals cannot be computed in time" do
      before do
        create_list(:execution, 12)
        cancel(:totals)
      end

      it "still renders the list" do
        get paths.executions_path

        expect(response).to have_http_status(:ok)
        expect(response.body.scan(%r{executions/\d+}).uniq.size).to eq(5)
      end

      it "replaces the totals with a hint" do
        get paths.executions_path

        expect(response.body).to include("totals: pick a time range")
      end

      it "paginates with prev/next and no page count" do
        get paths.executions_path

        expect(response.body).to include("1-5")
        expect(response.body).not_to match(/1-5\s+of/)
        expect(response.body).to include("page=2")
        expect(response.body).not_to include("page=3")
      end

      it "knows when the last page has been reached" do
        get paths.executions_path(page: 3)

        expect(response.body).to include("11-12")
        expect(response.body).to include("page=2")
        expect(response.body).not_to include("page=4")
      end

      it "fetches one row past the page instead of counting" do
        queries = capture_sql { get paths.executions_path }

        expect(aggregates(queries)).to be_empty
        expect(executions_sql(queries).grep(/LIMIT/).last).to match(/OFFSET/)
      end
    end

    it "does not recompute the totals while they are cached" do
      with_memory_cache
      create_list(:execution, 3)

      first = capture_sql { get paths.executions_path }
      second = capture_sql { get paths.executions_path(page: 1, sort: "total_cost") }

      expect(aggregates(first).size).to eq(1)
      expect(aggregates(second)).to be_empty
      expect(response.body).to include("badge-success")
    end

    it "caches totals separately per filter" do
      with_memory_cache
      create(:execution, status: "success")
      create(:execution, :failed)

      get paths.executions_path
      queries = capture_sql { get paths.executions_path(statuses: ["error"]) }

      expect(aggregates(queries).size).to eq(1)
    end

    it "remembers that totals were unavailable instead of retrying every request" do
      with_memory_cache
      create_list(:execution, 2)
      cancel(:totals)

      get paths.executions_path
      get paths.executions_path

      expect(execution_class).to have_received(:totals).once
      expect(response.body).to include("totals: pick a time range")
    end

    it "reads the filter dropdowns without a DISTINCT scan" do
      create(:execution, agent_type: "SearchAgent", model_id: "gpt-4o")

      queries = capture_sql { get paths.executions_path }

      expect(queries.grep(/SELECT DISTINCT/)).to be_empty
      expect(response.body).to include("Search")
    end
  end

  describe "a query the database cancels" do
    it "renders an explanation with a 503 instead of an error page" do
      cancel(:breakdown)

      get paths.root_path

      expect(response).to have_http_status(:service_unavailable)
      expect(response.body).to include("query timed out")
      expect(response.body).to include("dashboard_query_timeout")
    end

    it "is not mistaken for a pending migration" do
      cancel(:breakdown)

      get paths.root_path

      expect(response.body).not_to include("migrations are pending")
    end

    it "answers JSON endpoints with a JSON error" do
      cancel(:activity_chart_json)

      get paths.chart_data_path(range: "30d")

      expect(response).to have_http_status(:service_unavailable)
      expect(response.parsed_body).to eq("error" => "query_timeout")
    end

    it "reports the configured limit" do
      RubyLLM::Agents.configure { |c| c.dashboard_query_timeout = 12 }
      cancel(:breakdown)

      get paths.root_path

      expect(response.body).to include("more than 12s")
    end

    it "is cancelled for real by PostgreSQL once it passes the configured limit" do
      skip "PostgreSQL only" unless postgres

      RubyLLM::Agents.configure { |c| c.dashboard_query_timeout = 0.1 }
      allow(execution_class).to receive(:breakdown) do
        execution_class.connection.select_value("SELECT pg_sleep(3)")
      end

      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      get paths.root_path
      elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started

      expect(response).to have_http_status(:service_unavailable)
      expect(elapsed).to be < 2
      expect(execution_class.count).to eq(0)
    end

    it "does not time-limit pages when the limit is disabled" do
      RubyLLM::Agents.configure { |c| c.dashboard_query_timeout = nil }

      queries = capture_sql { get paths.root_path }

      expect(response).to have_http_status(:ok)
      expect(queries.grep(/statement_timeout/)).to be_empty
    end
  end

  describe "dashboard home" do
    before do
      create(:execution, agent_type: "SearchAgent", model_id: "gpt-4o")
      create(:execution, :failed, agent_type: "SearchAgent", model_id: "gpt-4o")
      create(:execution, agent_type: "SummaryAgent", model_id: "claude-sonnet", cache_hit: true)
    end

    it "derives agents, models, errors and cache savings from one scan of the range" do
      queries = capture_sql { get paths.root_path(range: "7d") }

      expect(response).to have_http_status(:ok)
      grouped = executions_sql(queries).grep(/GROUP BY/)
      expect(grouped.size).to eq(1)
      expect(grouped.first).to match(/created_at/)
      expect(response.body).to include("gpt-4o", "claude-sonnet", "StandardError")
    end

    it "scans the selected range once and the comparison period once" do
      queries = capture_sql { get paths.root_path(range: "30d") }

      windowed = aggregates(queries).grep(/SUM\(/)
      expect(windowed.size).to eq(2)
    end

    it "serves a repeat view from cache, apart from the live figures" do
      with_memory_cache
      get paths.root_path(range: "30d")

      queries = capture_sql { get paths.root_path(range: "30d") }

      expect(aggregates(queries).grep(/SUM\(/)).to be_empty
      expect(response.body).to include("gpt-4o")
    end

    it "keeps ranges apart in the cache" do
      with_memory_cache
      create(:execution, agent_type: "OldAgent", model_id: "legacy-model", created_at: 20.days.ago)

      get paths.root_path(range: "7d")
      expect(assigns(:model_stats).map { |m| m[:model_id] }).not_to include("legacy-model")

      get paths.root_path(range: "30d")
      expect(assigns(:model_stats).map { |m| m[:model_id] }).to include("legacy-model")
    end

    it "caches the chart per range" do
      with_memory_cache
      get paths.chart_data_path(range: "7d")

      queries = capture_sql { get paths.chart_data_path(range: "7d") }

      expect(response).to have_http_status(:ok)
      expect(executions_sql(queries)).to be_empty
      expect(response.parsed_body["series"].size).to eq(5)
    end
  end

  describe "agents list" do
    before do
      create_list(:execution, 2, agent_type: "SearchAgent")
      create(:execution, :failed, agent_type: "SearchAgent")
      create(:execution, agent_type: "SummaryAgent")
      create(:execution, agent_type: "RetiredAgent", created_at: 45.days.ago)
    end

    it "computes every agent's stats with one grouped query" do
      queries = capture_sql { get paths.agents_path }

      expect(response).to have_http_status(:ok)
      grouped = executions_sql(queries).grep(/GROUP BY/)
      expect(grouped.size).to eq(1)
      expect(grouped.first).to match(/created_at >=/)
      expect(aggregates(queries).grep(/SUM\(/).size).to eq(1)
    end

    it "labels the stats with the window they cover" do
      get paths.agents_path

      expect(response.body).to include("cover the last 30 days")
    end

    it "still lists agents whose only runs are older than the window" do
      get paths.agents_path

      expect(response.body).to include("Retired")
      expect(response.body).to include("about 2 months")
    end

    it "lists the agents without stats when the stats query is cancelled" do
      cancel(:breakdown)

      get paths.agents_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Search", "Summary")
      expect(response.body).to include("usage stats took too long to load")
    end

    it "caches the stats across requests" do
      with_memory_cache
      get paths.agents_path

      queries = capture_sql { get paths.agents_path }

      expect(executions_sql(queries).grep(/GROUP BY/)).to be_empty
      expect(response.body).to include("Search")
    end
  end

  describe "agent page" do
    before do
      RubyLLM::Agents.configure { |c| c.per_page = 5 }
      create_list(:execution, 8, agent_type: "SearchAgent")
    end

    it "renders with prev/next when the count is cancelled" do
      cancel(:totals)

      get paths.agent_path("SearchAgent")

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("1-5")
      expect(response.body).to include("page=2")
    end

    it "labels the headline stats with their window" do
      get paths.agent_path("SearchAgent")

      expect(response.body).to include(">30d<")
      expect(response.body).to include("show all executions")
    end
  end

  describe "tenants" do
    before { RubyLLM::Agents.configure { |c| c.multi_tenancy_enabled = true } }

    let!(:tenant) do
      RubyLLM::Agents::Tenant.create!(
        tenant_id: "acme", name: "Acme",
        monthly_cost_spent: 12.5, monthly_reset_date: Date.current.beginning_of_month,
        last_execution_at: 3.hours.ago
      )
    end

    it "lists tenants without aggregating the executions table" do
      create_list(:execution, 3, tenant_id: "acme")

      queries = capture_sql { get paths.tenants_path }

      expect(response).to have_http_status(:ok)
      expect(aggregates(queries)).to be_empty
    end

    it "shows month-to-date cost and last run from the tenant's counters" do
      get paths.tenants_path

      expect(response.body).to include("$12.50")
      expect(response.body).to include("about 3 hours")
    end

    it "does not show a counter left over from an earlier month" do
      tenant.update_columns(monthly_reset_date: 2.months.ago.beginning_of_month.to_date)

      get paths.tenants_path

      expect(response.body).to include("$0.00")
      expect(response.body).not_to include("$12.50")
    end

    it "bounds every aggregate on the tenant page to a time range" do
      create_list(:execution, 2, tenant_id: "acme")

      queries = capture_sql { get paths.tenant_path(tenant) }

      expect(response).to have_http_status(:ok)
      expect(aggregates(queries)).to be_present
      expect(aggregates(queries)).to all(match(/created_at/))
    end

    it "reports this month's usage on the tenant page" do
      create(:execution, tenant_id: "acme", agent_type: "SearchAgent", model_id: "gpt-4o",
        input_cost: 2.0, output_cost: 0, created_at: Time.current.beginning_of_month + 1.minute)
      create(:execution, :failed, tenant_id: "acme", agent_type: "SearchAgent", model_id: "gpt-4o",
        input_cost: 1.0, output_cost: 0, created_at: Time.current.beginning_of_month + 2.minutes)
      create(:execution, tenant_id: "acme", agent_type: "AncientAgent", model_id: "legacy-model",
        input_cost: 50.0, output_cost: 0, created_at: 3.months.ago)

      get paths.tenant_path(tenant)

      expect(response.body).to include("this month")
      expect(response.body).to include("$3.0000")
      expect(response.body).to include("50% ok")
      expect(response.body).to include("failed executions this month")
      expect(assigns(:usage_by_model).keys).to eq(%w[gpt-4o])
      expect(assigns(:usage_by_agent).keys).to eq(%w[SearchAgent])
      expect(assigns(:usage_stats)).to include(total_executions: 2, success_count: 1)
    end
  end

  describe "requests list" do
    before { RubyLLM::Agents.configure { |c| c.per_page = 2 } }

    def tracked(request_id, at, **attrs)
      create(:execution, request_id: request_id, created_at: at, started_at: at, **attrs)
    end

    before do
      tracked("req_month", 20.days.ago)
      tracked("req_week", 3.days.ago)
      tracked("req_today", 2.hours.ago)
      tracked("req_quarter", 60.days.ago)
      # Straddles the one-day window the list searches first.
      tracked("req_spanning", 30.hours.ago, input_cost: 1.0, output_cost: 0)
      tracked("req_spanning", 1.hour.ago, input_cost: 2.0, output_cost: 0)
    end

    def listed_requests
      response.body.scan(/title="(req_\w+)"/).flatten
    end

    it "lists the most recently active requests first" do
      get paths.requests_path

      expect(response).to have_http_status(:ok)
      expect(listed_requests).to eq(%w[req_spanning req_today])
    end

    it "widens the search window until the page is full" do
      get paths.requests_path(page: 2)
      expect(listed_requests).to eq(%w[req_week req_month])

      get paths.requests_path(page: 3)
      expect(listed_requests).to eq(%w[req_quarter])
    end

    it "aggregates a request in full even when it began before the window" do
      get paths.requests_path

      row = response.body[/title="req_spanning".*?title="req_today"/m]
      expect(row).to include("$3.0000")
    end

    it "only aggregates the requests on the page" do
      queries = capture_sql { get paths.requests_path }

      row_queries = executions_sql(queries).grep(/call_count/)
      expect(row_queries.size).to eq(1)
      expect(row_queries.first).to match(/"request_id" IN/)
    end

    it "pages by row count when the totals are cancelled" do
      allow(execution_class).to receive(:best_effort).and_return(nil)

      get paths.requests_path

      expect(response).to have_http_status(:ok)
      expect(listed_requests).to eq(%w[req_spanning req_today])
      expect(response.body).not_to include("tracked")
      expect(response.body).to include("page=2")
    end

    it "applies the days filter to the header totals as well as the list" do
      get paths.requests_path(days: 7)

      expect(response.body).to include("3 tracked")
    end

    it "still sorts on an aggregate" do
      get paths.requests_path(sort: "total_cost", direction: "desc")

      expect(listed_requests.first).to eq("req_spanning")
    end
  end
end
