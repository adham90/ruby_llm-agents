# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Version Upgrade Paths", type: :migration do
  describe "0.1.0 to 0.4.0 (full upgrade)" do
    before do
      build_schema_for_version("0.1.0")
    end

    it "creates the base schema successfully" do
      expect(table_exists?(:ruby_llm_agents_executions)).to be true

      # Core columns exist
      expect(column_exists?(:agent_type)).to be true
      expect(column_exists?(:model_id)).to be true
      expect(column_exists?(:status)).to be true
      expect(column_exists?(:parameters)).to be true
      expect(column_exists?(:response)).to be true
    end

    it "applies all migrations to reach 0.4.0" do
      # Seed data at v0.1.0
      records = MigrationTestData.seed_v0_1_0_data(count: 5)
      expect(record_count).to eq(5)

      # Apply migrations to 0.4.0
      apply_migrations_from_to("0.1.0", "0.4.0")

      # Verify new columns exist
      expect(column_exists?(:streaming)).to be true
      expect(column_exists?(:trace_id)).to be true
      expect(column_exists?(:tool_calls)).to be true
      expect(column_exists?(:attempts)).to be true
      expect(column_exists?(:tenant_id)).to be true
      expect(column_exists?(:messages_count)).to be true

      # Verify new tables exist
      expect(table_exists?(:ruby_llm_agents_tenant_budgets)).to be true
      expect(table_exists?(:ruby_llm_agents_api_configurations)).to be true

      # Verify data preserved
      expect(record_count).to eq(5)
    end

    it "preserves original data values" do
      records = MigrationTestData.seed_v0_1_0_data(count: 3)
      original_agents = records.map { |r| r[:agent_type] }

      apply_migrations_from_to("0.1.0", "0.4.0")

      current = all_records
      current_agents = current.map { |r| r["agent_type"] }

      expect(current_agents).to match_array(original_agents)
    end

    it "sets proper defaults for new columns" do
      MigrationTestData.seed_v0_1_0_data(count: 1)
      apply_migrations_from_to("0.1.0", "0.4.0")

      record = all_records.first

      # Check defaults are applied
      expect(record["streaming"]).to be_in([false, 0, "0", nil])
      expect(record["cache_hit"]).to be_in([false, 0, "0", nil])
      expect(record["tool_calls_count"]).to be_in([0, nil])
      expect(record["attempts_count"]).to be_in([0, nil])
      expect(record["messages_count"]).to be_in([0, nil])
    end
  end

  describe "0.2.3 to 0.4.0 (streaming/caching to latest)" do
    before do
      build_schema_for_version("0.2.3")
    end

    it "has streaming and caching columns" do
      expect(column_exists?(:streaming)).to be true
      expect(column_exists?(:cache_hit)).to be true
      expect(column_exists?(:trace_id)).to be true
      expect(column_exists?(:system_prompt)).to be true
    end

    it "upgrades to 0.4.0 preserving streaming data" do
      records = MigrationTestData.seed_v0_2_3_data(count: 5)

      # Verify streaming data exists
      streaming_records = all_records.select { |r| r["streaming"] == true || r["streaming"] == 1 }
      expect(streaming_records).not_to be_empty

      # Apply remaining migrations
      apply_migrations_from_to("0.2.3", "0.4.0")

      # Verify data preserved
      expect(record_count).to eq(5)

      # New columns exist
      expect(column_exists?(:tool_calls)).to be true
      expect(column_exists?(:attempts)).to be true
      expect(column_exists?(:tenant_id)).to be true
    end

    it "preserves trace hierarchy data" do
      records = MigrationTestData.seed_v0_2_3_data(count: 3)
      original_trace_ids = records.map { |r| r[:trace_id] }

      apply_migrations_from_to("0.2.3", "0.4.0")

      current = all_records
      current_trace_ids = current.map { |r| r["trace_id"] }

      expect(current_trace_ids).to match_array(original_trace_ids)
    end
  end

  describe "0.3.3 to 0.4.0 (tool calls to latest)" do
    before do
      build_schema_for_version("0.3.3")
    end

    it "has tool calls columns" do
      expect(column_exists?(:tool_calls)).to be true
      expect(column_exists?(:tool_calls_count)).to be true
      expect(column_exists?(:workflow_id)).to be true
    end

    it "upgrades to 0.4.0 preserving tool calls" do
      records = MigrationTestData.seed_v0_3_3_data(count: 5)

      # Verify tool calls exist
      records_with_tools = all_records.select { |r| (r["tool_calls_count"] || 0) > 0 }
      expect(records_with_tools).not_to be_empty

      apply_migrations_from_to("0.3.3", "0.4.0")

      # Verify data preserved
      expect(record_count).to eq(5)

      # New columns exist
      expect(column_exists?(:attempts)).to be true
      expect(column_exists?(:tenant_id)).to be true
      expect(column_exists?(:messages_count)).to be true
    end

    it "preserves workflow data" do
      records = MigrationTestData.seed_v0_3_3_data(count: 3)
      original_workflow_ids = records.map { |r| r[:workflow_id] }

      apply_migrations_from_to("0.3.3", "0.4.0")

      current = all_records
      current_workflow_ids = current.map { |r| r["workflow_id"] }

      expect(current_workflow_ids).to match_array(original_workflow_ids)
    end
  end

  describe "idempotent migration safety" do
    it "applying the same migration twice does not error" do
      build_schema_for_version("0.1.0")

      # Apply migrations once
      apply_migrations_from_to("0.1.0", "0.4.0")

      # Apply again - should be idempotent
      expect {
        apply_migrations_from_to("0.1.0", "0.4.0")
      }.not_to raise_error

      expect(table_exists?(:ruby_llm_agents_executions)).to be true
    end

    it "partial upgrade then full upgrade works" do
      build_schema_for_version("0.1.0")
      MigrationTestData.seed_v0_1_0_data(count: 3)

      # Partial upgrade
      apply_migrations_from_to("0.1.0", "0.2.3")
      expect(column_exists?(:streaming)).to be true

      # Continue upgrade
      apply_migrations_from_to("0.2.3", "0.4.0")
      expect(column_exists?(:tenant_id)).to be true

      # Data preserved
      expect(record_count).to eq(3)
    end
  end

  describe "rollback testing" do
    it "can rollback v0.4.0 reliability features" do
      build_schema_for_version("0.4.0")
      MigrationTestData.seed_v0_4_0_data(count: 3)

      expect(column_exists?(:attempts)).to be true
      expect(column_exists?(:fallback_chain)).to be true

      rollback_migration(:v0_4_0_reliability)

      expect(column_exists?(:attempts)).to be false
      expect(column_exists?(:fallback_chain)).to be false
    end

    it "can rollback v0.4.0 tenant tables" do
      build_schema_for_version("0.4.0")

      expect(table_exists?(:ruby_llm_agents_tenant_budgets)).to be true

      rollback_migration(:v0_4_0_tenant_budgets)

      expect(table_exists?(:ruby_llm_agents_tenant_budgets)).to be false
    end

    it "can rollback v0.4.0 api_configurations table" do
      build_schema_for_version("0.4.0")

      expect(table_exists?(:ruby_llm_agents_api_configurations)).to be true

      rollback_migration(:v0_4_0_api_configurations)

      expect(table_exists?(:ruby_llm_agents_api_configurations)).to be false
    end

    it "can rollback tool calls migration" do
      build_schema_for_version("0.3.3")

      expect(column_exists?(:tool_calls)).to be true
      expect(column_exists?(:workflow_id)).to be true

      rollback_migration(:v0_3_3_tool_calls)

      expect(column_exists?(:tool_calls)).to be false
      expect(column_exists?(:workflow_id)).to be false
    end

    it "can rollback streaming/tracing migration" do
      build_schema_for_version("0.2.3")

      expect(column_exists?(:streaming)).to be true
      expect(column_exists?(:trace_id)).to be true

      rollback_migration(:v0_2_3_streaming_tracing_caching)

      expect(column_exists?(:streaming)).to be false
      expect(column_exists?(:trace_id)).to be false
    end
  end

  describe "migration order verification" do
    it "applies migrations in correct order" do
      build_schema_for_version("0.1.0")

      # Track which columns exist after each migration
      columns_after_each = []

      # Apply v0.2.3
      apply_migration(:v0_2_3_streaming_tracing_caching)
      columns_after_each << column_names.dup

      # Apply v0.3.3
      apply_migration(:v0_3_3_tool_calls)
      columns_after_each << column_names.dup

      # Apply v0.4.0 reliability
      apply_migration(:v0_4_0_reliability)
      columns_after_each << column_names.dup

      # Streaming should exist after first migration
      expect(columns_after_each[0]).to include("streaming")
      expect(columns_after_each[0]).not_to include("tool_calls")

      # Tool calls should exist after second migration
      expect(columns_after_each[1]).to include("tool_calls")
      expect(columns_after_each[1]).not_to include("attempts")

      # Attempts should exist after third migration
      expect(columns_after_each[2]).to include("attempts")
    end
  end
end
