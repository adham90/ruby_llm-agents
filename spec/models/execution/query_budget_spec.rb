# frozen_string_literal: true

require "rails_helper"

RSpec.describe RubyLLM::Agents::Execution, "query time limits" do
  let(:connection) { described_class.connection }
  let(:postgres) { connection.adapter_name.downcase.include?("postg") }

  def statement_timeout
    connection.select_value("SELECT setting FROM pg_settings WHERE name = 'statement_timeout'").to_i
  end

  describe ".with_statement_timeout" do
    it "returns the block's value" do
      create_list(:execution, 2)

      expect(described_class.with_statement_timeout(5) { described_class.count }).to eq(2)
    end

    it "runs the block unguarded when the timeout is nil" do
      queries = capture_sql { expect(described_class.with_statement_timeout(nil) { :ran }).to eq(:ran) }

      expect(queries).to be_empty
    end

    it "lets other errors through" do
      expect { described_class.with_statement_timeout(5) { raise ArgumentError, "boom" } }
        .to raise_error(ArgumentError, "boom")
    end

    context "on PostgreSQL" do
      before { skip "PostgreSQL only" unless postgres }

      it "cancels a statement that outlives the timeout" do
        expect { described_class.with_statement_timeout(0.05) { connection.select_value("SELECT pg_sleep(2)") } }
          .to raise_error(ActiveRecord::QueryCanceled)
      end

      it "leaves the surrounding transaction usable after a cancellation" do
        create(:execution)

        begin
          described_class.with_statement_timeout(0.05) { connection.select_value("SELECT pg_sleep(2)") }
        rescue ActiveRecord::QueryCanceled
          nil
        end

        expect(described_class.count).to eq(1)
      end

      it "restores the previous timeout once the block is done" do
        before = statement_timeout

        described_class.with_statement_timeout(3) { expect(statement_timeout).to eq(3000) }
        expect(statement_timeout).to eq(before)

        begin
          described_class.with_statement_timeout(0.05) { connection.select_value("SELECT pg_sleep(2)") }
        rescue ActiveRecord::QueryCanceled
          nil
        end
        expect(statement_timeout).to eq(before)
      end

      it "nests, applying the innermost timeout and restoring the outer one" do
        described_class.with_statement_timeout(4) do
          described_class.with_statement_timeout(1) { expect(statement_timeout).to eq(1000) }
          expect(statement_timeout).to eq(4000)
        end
      end

      it "never loosens a stricter timeout that is already in force" do
        described_class.with_statement_timeout(0.05) do
          expect { described_class.with_statement_timeout(30) { connection.select_value("SELECT pg_sleep(2)") } }
            .to raise_error(ActiveRecord::QueryCanceled)
        end
      end
    end
  end

  describe ".best_effort" do
    it "returns the block's value when the query finishes" do
      create_list(:execution, 3)

      expect(described_class.best_effort(timeout: 5) { described_class.totals[:total_count] }).to eq(3)
    end

    it "returns nil when the database cancels the query" do
      result = described_class.best_effort(timeout: 5) { raise ActiveRecord::QueryCanceled, "canceling statement" }

      expect(result).to be_nil
    end

    it "does not swallow other database errors" do
      expect { described_class.best_effort(timeout: 5) { raise ActiveRecord::StatementInvalid, "syntax error" } }
        .to raise_error(ActiveRecord::StatementInvalid)
    end

    context "on PostgreSQL" do
      before { skip "PostgreSQL only" unless postgres }

      it "gives up on a slow query and leaves the connection usable" do
        create(:execution)

        result = described_class.best_effort(timeout: 0.05) { connection.select_value("SELECT pg_sleep(2)") }

        expect(result).to be_nil
        expect(described_class.count).to eq(1)
      end
    end
  end

  describe ".usage_summary" do
    before do
      create(:execution, agent_type: "SearchAgent", input_cost: 1.0, output_cost: 0, input_tokens: 100,
        output_tokens: 0, duration_ms: 1000, cache_hit: true, streaming: true)
      create(:execution, agent_type: "SearchAgent", input_cost: 3.0, output_cost: 0, input_tokens: 300,
        output_tokens: 0, duration_ms: 3000)
      create(:execution, :failed, agent_type: "SearchAgent", input_cost: 0, output_cost: 0, input_tokens: 20,
        output_tokens: 0, duration_ms: 500)
      create(:execution, :timeout, agent_type: "SearchAgent", input_cost: 0, output_cost: 0, input_tokens: 0,
        output_tokens: 0, total_tokens: 0, duration_ms: 500)
      create(:execution, agent_type: "OtherAgent")
    end

    let(:scope) { described_class.where(agent_type: "SearchAgent") }

    it "summarises the scope in one query" do
      queries = capture_sql { scope.usage_summary }

      expect(queries.size).to eq(1)
    end

    it "reports usage, reliability, cache and streaming figures" do
      expect(scope.usage_summary).to eq(
        count: 4,
        total_cost: 4.0,
        avg_cost: 1.0,
        total_tokens: 420,
        avg_tokens: 105,
        avg_duration_ms: 1250,
        success_rate: 50.0,
        error_rate: 50.0,
        cache_hit_rate: 25.0,
        streaming_rate: 25.0
      )
    end

    it "is all zeros for an empty scope" do
      expect(described_class.none.usage_summary).to include(
        count: 0, total_cost: 0, avg_cost: 0, total_tokens: 0, avg_tokens: 0, avg_duration_ms: 0,
        success_rate: 0.0, error_rate: 0.0, cache_hit_rate: 0.0, streaming_rate: 0.0
      )
    end

    it "backs stats_for" do
      stats = described_class.stats_for("SearchAgent", period: :today)

      expect(stats).to include(agent_type: "SearchAgent", period: :today, count: 4, success_rate: 50.0)
    end
  end
end
