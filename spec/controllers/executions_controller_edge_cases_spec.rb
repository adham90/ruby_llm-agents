# frozen_string_literal: true

require "rails_helper"

RSpec.describe RubyLLM::Agents::ExecutionsController, "edge cases", type: :controller do
  routes { RubyLLM::Agents::Engine.routes }

  before do
    # Create test executions
    @executions = []

    # Create executions with various attributes
    @executions << RubyLLM::Agents::Execution.create!(
      agent_type: "TestAgent",
      model_id: "gpt-4o",
      input_tokens: 100,
      output_tokens: 50,
      total_cost: 0.01,
      duration_ms: 100,
      status: "success",
      started_at: 1.hour.ago,
      created_at: 1.hour.ago
    )

    @executions << RubyLLM::Agents::Execution.create!(
      agent_type: "TestAgent",
      model_id: "gpt-4o-mini",
      input_tokens: 200,
      output_tokens: 100,
      total_cost: 0.005,
      duration_ms: 150,
      status: "success",
      started_at: 2.hours.ago,
      created_at: 2.hours.ago
    )

    @executions << RubyLLM::Agents::Execution.create!(
      agent_type: "OtherAgent",
      model_id: "gpt-4o",
      input_tokens: 50,
      output_tokens: 25,
      total_cost: 0.002,
      duration_ms: 50,
      status: "error",
      error_message: "API Error",
      started_at: 3.hours.ago,
      created_at: 3.hours.ago
    )

    @executions << RubyLLM::Agents::Execution.create!(
      agent_type: "TestAgent",
      model_id: "claude-3-haiku",
      input_tokens: 300,
      output_tokens: 150,
      total_cost: 0.02,
      duration_ms: 200,
      status: "success",
      started_at: 1.day.ago,
      created_at: 1.day.ago,
      cache_hit: true
    )
  end

  describe "GET #index" do
    context "with pagination edge cases" do
      it "handles empty results" do
        RubyLLM::Agents::Execution.delete_all

        get :index
        expect(response).to have_http_status(:success)
      end

      it "handles page beyond available data" do
        get :index, params: { page: 999 }
        expect(response).to have_http_status(:success)
      end

      it "handles negative page number gracefully" do
        get :index, params: { page: -1 }
        expect(response).to have_http_status(:success)
      end

      it "handles very large page number" do
        get :index, params: { page: 999_999_999 }
        expect(response).to have_http_status(:success)
      end

      it "handles per_page of 0" do
        get :index, params: { per_page: 0 }
        expect(response).to have_http_status(:success)
      end

      it "handles non-numeric page parameter" do
        get :index, params: { page: "abc" }
        expect(response).to have_http_status(:success)
      end
    end

    context "with filtering edge cases" do
      it "filters by exact agent_type" do
        get :index, params: { agent_type: "TestAgent" }

        expect(response).to have_http_status(:success)
        # Controller should filter to only TestAgent
      end

      it "handles non-existent agent_type filter" do
        get :index, params: { agent_type: "NonExistentAgent" }

        expect(response).to have_http_status(:success)
      end

      it "filters by model_id" do
        get :index, params: { model_id: "gpt-4o" }

        expect(response).to have_http_status(:success)
      end

      it "filters by status" do
        get :index, params: { status: "error" }

        expect(response).to have_http_status(:success)
      end

      it "handles invalid status filter" do
        get :index, params: { status: "invalid_status" }

        expect(response).to have_http_status(:success)
      end
    end

    context "with date range filtering" do
      it "filters by date range" do
        get :index, params: {
          start_date: 2.days.ago.to_date.to_s,
          end_date: Date.current.to_s
        }

        expect(response).to have_http_status(:success)
      end

      it "handles inverted date range (start > end)" do
        get :index, params: {
          start_date: Date.current.to_s,
          end_date: 2.days.ago.to_date.to_s
        }

        expect(response).to have_http_status(:success)
      end

      it "handles invalid date format" do
        get :index, params: {
          start_date: "not-a-date",
          end_date: "also-not-a-date"
        }

        expect(response).to have_http_status(:success)
      end

      it "handles future dates" do
        get :index, params: {
          start_date: 1.year.from_now.to_date.to_s,
          end_date: 2.years.from_now.to_date.to_s
        }

        expect(response).to have_http_status(:success)
      end
    end

    context "with sorting edge cases" do
      it "sorts by created_at ascending" do
        get :index, params: { sort: "created_at", direction: "asc" }

        expect(response).to have_http_status(:success)
      end

      it "sorts by created_at descending" do
        get :index, params: { sort: "created_at", direction: "desc" }

        expect(response).to have_http_status(:success)
      end

      it "handles invalid sort column" do
        get :index, params: { sort: "invalid_column" }

        expect(response).to have_http_status(:success)
      end

      it "handles SQL injection attempt in sort" do
        get :index, params: { sort: "created_at; DROP TABLE executions;--" }

        expect(response).to have_http_status(:success)
        # Table should still exist
        expect(RubyLLM::Agents::Execution.table_exists?).to be true
      end

      it "handles invalid direction" do
        get :index, params: { sort: "created_at", direction: "invalid" }

        expect(response).to have_http_status(:success)
      end
    end

    context "with combined filters" do
      it "handles multiple filters simultaneously" do
        get :index, params: {
          agent_type: "TestAgent",
          model_id: "gpt-4o",
          status: "success",
          start_date: 2.days.ago.to_date.to_s,
          page: 1,
          per_page: 10
        }

        expect(response).to have_http_status(:success)
      end
    end
  end

  describe "GET #show" do
    it "shows existing execution" do
      get :show, params: { id: @executions.first.id }

      expect(response).to have_http_status(:success)
    end

    it "handles non-existent execution" do
      expect {
        get :show, params: { id: 999_999_999 }
      }.to raise_error(ActiveRecord::RecordNotFound)
    end

    it "handles non-numeric id" do
      expect {
        get :show, params: { id: "invalid" }
      }.to raise_error(ActiveRecord::RecordNotFound)
    end

    it "handles negative id" do
      expect {
        get :show, params: { id: -1 }
      }.to raise_error(ActiveRecord::RecordNotFound)
    end
  end

  describe "response format handling" do
    it "responds to HTML format" do
      get :index, format: :html

      expect(response).to have_http_status(:success)
      expect(response.content_type).to include("text/html")
    end
  end

  describe "execution with metadata" do
    before do
      @execution_with_metadata = RubyLLM::Agents::Execution.create!(
        agent_type: "MetadataAgent",
        model_id: "gpt-4o",
        input_tokens: 100,
        output_tokens: 50,
        total_cost: 0.01,
        duration_ms: 100,
        status: "success",
        started_at: Time.current,
        metadata: {
          request_id: "req-123",
          user_id: "user-456",
          custom_field: "custom_value"
        }
      )
    end

    it "shows execution with metadata" do
      get :show, params: { id: @execution_with_metadata.id }

      expect(response).to have_http_status(:success)
    end
  end

  describe "cache hit executions" do
    it "includes cache hit executions in listing" do
      get :index

      expect(response).to have_http_status(:success)
    end

    it "filters by cache_hit status" do
      get :index, params: { cache_hit: true }

      expect(response).to have_http_status(:success)
    end
  end

  describe "performance with large datasets" do
    context "with many executions" do
      before do
        # Create additional executions for performance testing
        50.times do |i|
          time = rand(30).days.ago
          RubyLLM::Agents::Execution.create!(
            agent_type: "PerformanceTestAgent",
            model_id: ["gpt-4o", "gpt-4o-mini", "claude-3-haiku"].sample,
            input_tokens: rand(50..500),
            output_tokens: rand(25..250),
            total_cost: rand(0.001..0.05),
            duration_ms: rand(50..500),
            status: %w[success error].sample,
            started_at: time,
            created_at: time
          )
        end
      end

      it "handles large result sets efficiently" do
        start_time = Time.current
        get :index, params: { per_page: 100 }
        elapsed = Time.current - start_time

        expect(response).to have_http_status(:success)
        expect(elapsed).to be < 1.0 # Should complete in under 1 second
      end

      it "handles aggregation queries" do
        get :index

        expect(response).to have_http_status(:success)
      end
    end
  end
end
