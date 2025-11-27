# frozen_string_literal: true

require "rails_helper"

RSpec.describe RubyLLM::Agents::Execution, type: :model do
  describe "validations" do
    it "is valid with valid attributes" do
      execution = build(:execution)
      expect(execution).to be_valid
    end

    it "requires agent_type" do
      execution = build(:execution, agent_type: nil)
      expect(execution).not_to be_valid
      expect(execution.errors[:agent_type]).to include("can't be blank")
    end

    it "requires model_id" do
      execution = build(:execution, model_id: nil)
      expect(execution).not_to be_valid
      expect(execution.errors[:model_id]).to include("can't be blank")
    end

    it "requires started_at" do
      execution = build(:execution, started_at: nil)
      expect(execution).not_to be_valid
      expect(execution.errors[:started_at]).to include("can't be blank")
    end

    it "validates temperature range" do
      execution = build(:execution, temperature: 2.5)
      expect(execution).not_to be_valid

      execution.temperature = -0.5
      expect(execution).not_to be_valid

      execution.temperature = 1.0
      expect(execution).to be_valid
    end
  end

  describe "callbacks" do
    it "calculates total_tokens before save" do
      execution = build(:execution, input_tokens: 100, output_tokens: 50, total_tokens: nil)
      execution.save!
      expect(execution.total_tokens).to eq(150)
    end

    it "calculates total_cost before save" do
      execution = build(:execution, input_cost: 0.001, output_cost: 0.002, total_cost: nil)
      execution.save!
      expect(execution.total_cost).to eq(0.003)
    end
  end

  describe "scopes" do
    describe ".today" do
      it "returns only today's executions" do
        today_execution = create(:execution)
        yesterday_execution = create(:execution, :yesterday)

        expect(described_class.today).to include(today_execution)
        expect(described_class.today).not_to include(yesterday_execution)
      end
    end

    describe ".successful" do
      it "returns only successful executions" do
        successful = create(:execution, status: "success")
        failed = create(:execution, :failed)

        expect(described_class.successful).to include(successful)
        expect(described_class.successful).not_to include(failed)
      end
    end

    describe ".failed" do
      it "returns only non-successful executions" do
        successful = create(:execution, status: "success")
        failed = create(:execution, :failed)
        timeout = create(:execution, :timeout)

        expect(described_class.failed).not_to include(successful)
        expect(described_class.failed).to include(failed)
        expect(described_class.failed).to include(timeout)
      end
    end

    describe ".by_agent" do
      it "filters by agent type" do
        test_agent = create(:execution, agent_type: "TestAgent")
        other_agent = create(:execution, agent_type: "OtherAgent")

        expect(described_class.by_agent("TestAgent")).to include(test_agent)
        expect(described_class.by_agent("TestAgent")).not_to include(other_agent)
      end
    end

    describe ".expensive" do
      it "filters by cost threshold" do
        cheap = create(:execution, total_cost: 0.50)
        expensive = create(:execution, :expensive)

        expect(described_class.expensive(1.00)).not_to include(cheap)
        expect(described_class.expensive(1.00)).to include(expensive)
      end
    end

    describe ".slow" do
      it "filters by duration threshold" do
        fast = create(:execution, duration_ms: 1000)
        slow = create(:execution, :slow)

        expect(described_class.slow(5000)).not_to include(fast)
        expect(described_class.slow(5000)).to include(slow)
      end
    end

    describe ".yesterday" do
      it "returns only yesterday's executions" do
        today_exec = create(:execution)
        yesterday_exec = create(:execution, :yesterday)

        expect(described_class.yesterday).to include(yesterday_exec)
        expect(described_class.yesterday).not_to include(today_exec)
      end
    end

    describe ".this_week" do
      it "returns executions from this week" do
        this_week_exec = create(:execution)
        old_exec = create(:execution, created_at: 2.weeks.ago)

        expect(described_class.this_week).to include(this_week_exec)
        expect(described_class.this_week).not_to include(old_exec)
      end
    end

    describe ".this_month" do
      it "returns executions from this month" do
        this_month_exec = create(:execution)
        old_exec = create(:execution, created_at: 2.months.ago)

        expect(described_class.this_month).to include(this_month_exec)
        expect(described_class.this_month).not_to include(old_exec)
      end
    end

    describe ".last_n_days" do
      it "returns executions from last n days" do
        recent = create(:execution, created_at: 3.days.ago)
        old = create(:execution, created_at: 10.days.ago)

        expect(described_class.last_n_days(7)).to include(recent)
        expect(described_class.last_n_days(7)).not_to include(old)
      end
    end

    describe ".by_version" do
      it "filters by agent version" do
        v1 = create(:execution, agent_version: "1.0")
        v2 = create(:execution, agent_version: "2.0")

        expect(described_class.by_version("1.0")).to include(v1)
        expect(described_class.by_version("1.0")).not_to include(v2)
      end
    end

    describe ".by_model" do
      it "filters by model" do
        gpt4 = create(:execution, model_id: "gpt-4")
        claude = create(:execution, model_id: "claude-3")

        expect(described_class.by_model("gpt-4")).to include(gpt4)
        expect(described_class.by_model("gpt-4")).not_to include(claude)
      end
    end

    describe ".recent" do
      it "returns limited recent executions ordered by created_at desc" do
        old = create(:execution, created_at: 1.day.ago)
        new = create(:execution, created_at: Time.current)

        result = described_class.recent(1)
        expect(result).to include(new)
        expect(result).not_to include(old)
      end
    end

    describe ".search" do
      it "returns all records when query is blank" do
        create_list(:execution, 3)
        expect(described_class.search("")).to eq(described_class.all)
        expect(described_class.search(nil)).to eq(described_class.all)
      end

      it "searches by error_class" do
        create(:execution, error_class: "TimeoutError")
        create(:execution, error_class: "NetworkError")

        result = described_class.search("Timeout")
        expect(result.count).to eq(1)
        expect(result.first.error_class).to eq("TimeoutError")
      end

      it "searches by error_message" do
        create(:execution, error_message: "Connection refused by server")
        create(:execution, error_message: "Request timed out")

        result = described_class.search("Connection")
        expect(result.count).to eq(1)
        expect(result.first.error_message).to include("Connection")
      end

      it "searches within parameters JSON" do
        create(:execution, parameters: { query: "find special item" })
        create(:execution, parameters: { query: "normal search" })

        result = described_class.search("special")
        expect(result.count).to eq(1)
      end

      it "is case insensitive" do
        create(:execution, error_class: "TimeoutError")

        expect(described_class.search("timeout").count).to eq(1)
        expect(described_class.search("TIMEOUT").count).to eq(1)
        expect(described_class.search("TimeOut").count).to eq(1)
      end

      it "sanitizes SQL wildcards in search input" do
        create(:execution, error_message: "100% complete")

        # Should not match all records due to unsanitized %
        result = described_class.search("%")
        expect(result.count).to eq(1)
      end

      it "can be chained with other scopes" do
        create(:execution, error_class: "TimeoutError", status: "error")
        create(:execution, error_class: "TimeoutError", status: "success")

        result = described_class.errors.search("Timeout")
        expect(result.count).to eq(1)
        expect(result.first.status).to eq("error")
      end
    end
  end

  describe "aggregations" do
    before do
      create(:execution, input_cost: 0.05, output_cost: 0.05, total_tokens: 100, duration_ms: 1000)
      create(:execution, input_cost: 0.10, output_cost: 0.10, total_tokens: 200, duration_ms: 2000)
    end

    describe ".total_cost_sum" do
      it "returns sum of total_cost" do
        expect(described_class.total_cost_sum).to eq(0.30)
      end
    end

    describe ".total_tokens_sum" do
      it "returns sum of total_tokens" do
        expect(described_class.total_tokens_sum).to eq(300)
      end
    end

    describe ".avg_duration" do
      it "returns average duration" do
        expect(described_class.avg_duration).to eq(1500)
      end
    end

    describe ".avg_tokens" do
      it "returns average tokens" do
        expect(described_class.avg_tokens).to eq(150)
      end
    end
  end

  describe "status enum" do
    it "has correct status values" do
      expect(described_class.statuses.keys).to contain_exactly("running", "success", "error", "timeout")
    end

    it "provides status query methods" do
      execution = build(:execution, status: "success")
      expect(execution.status_success?).to be true
      expect(execution.status_error?).to be false
    end
  end

  describe "metrics" do
    describe "#duration_seconds" do
      it "converts milliseconds to seconds" do
        execution = build(:execution, duration_ms: 1500)
        expect(execution.duration_seconds).to eq(1.5)
      end

      it "returns nil when duration_ms is nil" do
        execution = build(:execution, duration_ms: nil)
        expect(execution.duration_seconds).to be_nil
      end
    end

    describe "#tokens_per_second" do
      it "calculates tokens per second" do
        execution = build(:execution, total_tokens: 300, duration_ms: 1000)
        expect(execution.tokens_per_second).to eq(300.0)
      end
    end

    describe "#formatted_total_cost" do
      it "formats cost as currency string" do
        execution = build(:execution, total_cost: 0.000045)
        expect(execution.formatted_total_cost).to eq("$0.000045")
      end
    end
  end

  describe "tool calls" do
    describe "#has_tool_calls?" do
      it "returns true when tool_calls_count > 0" do
        execution = build(:execution, tool_calls_count: 2)
        expect(execution.has_tool_calls?).to be true
      end

      it "returns false when tool_calls_count is 0" do
        execution = build(:execution, tool_calls_count: 0)
        expect(execution.has_tool_calls?).to be false
      end

      it "returns false when tool_calls_count is nil" do
        execution = build(:execution, tool_calls_count: nil)
        expect(execution.has_tool_calls?).to be false
      end
    end

    describe "scopes" do
      describe ".with_tool_calls" do
        it "returns executions with tool calls" do
          with_calls = create(:execution, :with_tool_calls)
          without_calls = create(:execution, tool_calls_count: 0)

          expect(described_class.with_tool_calls).to include(with_calls)
          expect(described_class.with_tool_calls).not_to include(without_calls)
        end
      end

      describe ".without_tool_calls" do
        it "returns executions without tool calls" do
          with_calls = create(:execution, :with_tool_calls)
          without_calls = create(:execution, tool_calls_count: 0)

          expect(described_class.without_tool_calls).to include(without_calls)
          expect(described_class.without_tool_calls).not_to include(with_calls)
        end
      end
    end

    describe "factory trait" do
      it "creates execution with tool calls" do
        execution = create(:execution, :with_tool_calls)

        expect(execution.tool_calls.size).to eq(2)
        expect(execution.tool_calls_count).to eq(2)
        expect(execution.finish_reason).to eq("tool_calls")
        expect(execution.tool_calls.first["name"]).to eq("search_database")
      end
    end
  end
end
