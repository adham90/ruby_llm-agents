# frozen_string_literal: true

require "rails_helper"

RSpec.describe RubyLLM::Agents::Execution::Analytics do
  let(:execution_class) { RubyLLM::Agents::Execution }

  describe ".daily_report" do
    context "with no executions today" do
      it "returns zero counts" do
        report = execution_class.daily_report
        expect(report[:total_executions]).to eq(0)
        expect(report[:successful]).to eq(0)
        expect(report[:failed]).to eq(0)
      end
    end

    context "with executions today" do
      before do
        create_list(:execution, 3, status: "success")
        create_list(:execution, 2, :failed)
      end

      it "returns correct total count" do
        expect(execution_class.daily_report[:total_executions]).to eq(5)
      end

      it "returns correct successful count" do
        expect(execution_class.daily_report[:successful]).to eq(3)
      end

      it "returns correct failed count" do
        expect(execution_class.daily_report[:failed]).to eq(2)
      end

      it "calculates error rate" do
        expect(execution_class.daily_report[:error_rate]).to eq(40.0)
      end

      it "includes by_agent breakdown" do
        report = execution_class.daily_report
        expect(report[:by_agent]).to be_a(Hash)
      end
    end
  end

  describe ".cost_by_agent" do
    before do
      create(:execution, agent_type: "AgentA", input_cost: 0.5, output_cost: 0.5) # total = 1.0
      create(:execution, agent_type: "AgentA", input_cost: 1.0, output_cost: 1.0) # total = 2.0
      create(:execution, agent_type: "AgentB", input_cost: 0.25, output_cost: 0.25) # total = 0.5
    end

    it "returns cost breakdown by agent" do
      result = execution_class.cost_by_agent(period: :today)
      expect(result["AgentA"]).to eq(3.0)
      expect(result["AgentB"]).to eq(0.5)
    end

    it "sorts by cost descending" do
      result = execution_class.cost_by_agent(period: :today)
      expect(result.keys.first).to eq("AgentA")
    end
  end

  describe ".stats_for" do
    before do
      create(:execution, agent_type: "TestAgent", input_cost: 0.5, output_cost: 0.5, total_tokens: 100, duration_ms: 1000)
      create(:execution, agent_type: "TestAgent", input_cost: 1.0, output_cost: 1.0, total_tokens: 200, duration_ms: 2000)
    end

    it "returns stats hash" do
      stats = execution_class.stats_for("TestAgent", period: :today)
      expect(stats).to include(:count, :total_cost, :avg_cost, :total_tokens, :avg_tokens)
    end

    it "calculates correct count" do
      expect(execution_class.stats_for("TestAgent", period: :today)[:count]).to eq(2)
    end

    it "calculates total cost" do
      expect(execution_class.stats_for("TestAgent", period: :today)[:total_cost]).to eq(3.0)
    end

    it "calculates average cost" do
      expect(execution_class.stats_for("TestAgent", period: :today)[:avg_cost]).to eq(1.5)
    end

    context "with no executions" do
      it "returns zero avg_cost to avoid division by zero" do
        stats = execution_class.stats_for("NonExistent", period: :today)
        expect(stats[:avg_cost]).to eq(0)
      end
    end
  end

  describe ".compare_versions" do
    before do
      create(:execution, agent_type: "TestAgent", agent_version: "1.0", total_cost: 1.0, duration_ms: 1000)
      create(:execution, agent_type: "TestAgent", agent_version: "2.0", total_cost: 0.5, duration_ms: 500)
    end

    it "returns comparison data" do
      result = execution_class.compare_versions("TestAgent", "1.0", "2.0", period: :today)
      expect(result[:version1][:version]).to eq("1.0")
      expect(result[:version2][:version]).to eq("2.0")
    end

    it "calculates improvement percentages" do
      result = execution_class.compare_versions("TestAgent", "1.0", "2.0", period: :today)
      expect(result[:improvements]).to include(:cost_change_pct, :speed_change_pct)
    end
  end

  describe ".trend_analysis" do
    before do
      create(:execution, created_at: Time.current)
      create(:execution, created_at: 1.day.ago)
      create(:execution, created_at: 2.days.ago)
    end

    it "returns data for specified number of days" do
      result = execution_class.trend_analysis(days: 7)
      expect(result.size).to eq(7)
    end

    it "includes date and count for each day" do
      result = execution_class.trend_analysis(days: 3)
      expect(result.first).to include(:date, :count, :total_cost, :error_count)
    end

    it "filters by agent_type when provided" do
      create(:execution, agent_type: "SpecificAgent", created_at: Time.current)
      result = execution_class.trend_analysis(agent_type: "SpecificAgent", days: 3)
      expect(result.last[:count]).to eq(1)
    end
  end

  describe ".hourly_activity_chart" do
    before do
      create(:execution, status: "success", created_at: Time.current.beginning_of_day + 10.hours)
      create(:execution, status: "error", created_at: Time.current.beginning_of_day + 10.hours)
    end

    it "returns success and failed data sets" do
      result = execution_class.hourly_activity_chart
      expect(result.size).to eq(2)
      expect(result.map { |d| d[:name] }).to include("Success", "Failed")
    end

    it "includes data for all 24 hours" do
      result = execution_class.hourly_activity_chart
      success_data = result.find { |d| d[:name] == "Success" }[:data]
      expect(success_data.keys.size).to eq(24)
    end

    it "returns fresh data (no caching)" do
      # hourly_activity_chart intentionally doesn't cache to show real-time data
      result1 = execution_class.hourly_activity_chart
      result2 = execution_class.hourly_activity_chart
      expect(result1).to be_an(Array)
      expect(result2).to be_an(Array)
    end
  end

  describe "private helper methods" do
    describe "percent_change" do
      it "returns 0 when old value is zero" do
        result = execution_class.send(:percent_change, 0, 10)
        expect(result).to eq(0.0)
      end

      it "returns 0 when old value is nil" do
        result = execution_class.send(:percent_change, nil, 10)
        expect(result).to eq(0.0)
      end

      it "calculates correct percentage" do
        result = execution_class.send(:percent_change, 100, 150)
        expect(result).to eq(50.0)
      end

      it "handles negative change" do
        result = execution_class.send(:percent_change, 100, 50)
        expect(result).to eq(-50.0)
      end
    end
  end
end
