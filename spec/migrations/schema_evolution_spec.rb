# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Schema Evolution Compatibility", type: :migration do
  describe "column type stability" do
    it "agent_type remains string across all versions" do
      build_schema_for_version("0.1.0")
      expect(column_type(:agent_type)).to eq(:string)

      apply_migrations_from_to("0.1.0", "0.4.0")
      expect(column_type(:agent_type)).to eq(:string)
    end

    it "model_id remains string across all versions" do
      build_schema_for_version("0.1.0")
      expect(column_type(:model_id)).to eq(:string)

      apply_migrations_from_to("0.1.0", "0.4.0")
      expect(column_type(:model_id)).to eq(:string)
    end

    it "parameters remains json across all versions" do
      build_schema_for_version("0.1.0")
      expect(column_type(:parameters)).to eq(:json)

      apply_migrations_from_to("0.1.0", "0.4.0")
      expect(column_type(:parameters)).to eq(:json)
    end

    it "total_cost remains decimal with correct precision" do
      build_schema_for_version("0.1.0")
      expect(column_type(:total_cost)).to eq(:decimal)

      apply_migrations_from_to("0.1.0", "0.4.0")
      expect(column_type(:total_cost)).to eq(:decimal)
    end

    it "duration_ms remains integer across all versions" do
      build_schema_for_version("0.1.0")
      expect(column_type(:duration_ms)).to eq(:integer)

      apply_migrations_from_to("0.1.0", "0.4.0")
      expect(column_type(:duration_ms)).to eq(:integer)
    end

    it "streaming is boolean type in v0.2.3+" do
      build_schema_for_version("0.2.3")
      expect(column_type(:streaming)).to eq(:boolean)

      apply_migrations_from_to("0.2.3", "0.4.0")
      expect(column_type(:streaming)).to eq(:boolean)
    end

    it "tool_calls is json type in v0.3.3+" do
      build_schema_for_version("0.3.3")
      expect(column_type(:tool_calls)).to eq(:json)

      apply_migrations_from_to("0.3.3", "0.4.0")
      expect(column_type(:tool_calls)).to eq(:json)
    end

    it "attempts is json type in v0.4.0" do
      build_schema_for_version("0.4.0")
      expect(column_type(:attempts)).to eq(:json)
    end
  end

  describe "NULL constraint additions only with defaults" do
    it "new columns with NOT NULL have defaults" do
      build_schema_for_version("0.1.0")
      apply_migrations_from_to("0.1.0", "0.4.0")

      # Check columns added with NOT NULL constraint have defaults
      connection = ActiveRecord::Base.connection
      columns = connection.columns(:ruby_llm_agents_executions)

      not_null_columns = columns.select { |c| !c.null }

      not_null_columns.each do |col|
        # Skip columns that were in original schema
        next if %w[id agent_type model_id started_at status created_at updated_at].include?(col.name)

        expect(col.default).not_to be_nil,
          "Column #{col.name} has NOT NULL but no default"
      end
    end

    it "tool_calls_count defaults to 0" do
      build_schema_for_version("0.3.3")

      expect(column_default(:tool_calls_count)).to eq("0").or eq(0)
    end

    it "attempts_count defaults to 0" do
      build_schema_for_version("0.4.0")

      expect(column_default(:attempts_count)).to eq("0").or eq(0)
    end

    it "messages_count defaults to 0" do
      build_schema_for_version("0.4.0")

      expect(column_default(:messages_count)).to eq("0").or eq(0)
    end

    it "streaming defaults to false" do
      build_schema_for_version("0.2.3")

      expect(column_default(:streaming)).to be_in(["0", 0, false, "false", "f"])
    end

    it "cache_hit defaults to false" do
      build_schema_for_version("0.2.3")

      expect(column_default(:cache_hit)).to be_in(["0", 0, false, "false", "f"])
    end
  end

  describe "index preservation" do
    it "agent_type index preserved across upgrades" do
      build_schema_for_version("0.1.0")
      expect(index_exists?(:ruby_llm_agents_executions, :agent_type)).to be true

      apply_migrations_from_to("0.1.0", "0.4.0")
      expect(index_exists?(:ruby_llm_agents_executions, :agent_type)).to be true
    end

    it "status index preserved across upgrades" do
      build_schema_for_version("0.1.0")
      expect(index_exists?(:ruby_llm_agents_executions, :status)).to be true

      apply_migrations_from_to("0.1.0", "0.4.0")
      expect(index_exists?(:ruby_llm_agents_executions, :status)).to be true
    end

    it "created_at index preserved across upgrades" do
      build_schema_for_version("0.1.0")
      expect(index_exists?(:ruby_llm_agents_executions, :created_at)).to be true

      apply_migrations_from_to("0.1.0", "0.4.0")
      expect(index_exists?(:ruby_llm_agents_executions, :created_at)).to be true
    end

    it "composite agent_type+created_at index preserved" do
      build_schema_for_version("0.1.0")
      expect(index_exists?(:ruby_llm_agents_executions, [:agent_type, :created_at])).to be true

      apply_migrations_from_to("0.1.0", "0.4.0")
      expect(index_exists?(:ruby_llm_agents_executions, [:agent_type, :created_at])).to be true
    end

    it "trace_id index added in v0.2.3" do
      build_schema_for_version("0.1.0")
      expect(index_exists?(:ruby_llm_agents_executions, :trace_id)).to be false

      apply_migrations_from_to("0.1.0", "0.2.3")
      expect(index_exists?(:ruby_llm_agents_executions, :trace_id)).to be true
    end

    it "tool_calls_count index added in v0.3.3" do
      build_schema_for_version("0.2.3")
      expect(index_exists?(:ruby_llm_agents_executions, :tool_calls_count)).to be false

      apply_migrations_from_to("0.2.3", "0.3.3")
      expect(index_exists?(:ruby_llm_agents_executions, :tool_calls_count)).to be true
    end

    it "tenant_id indexes added in v0.4.0" do
      build_schema_for_version("0.3.3")
      expect(index_exists?(:ruby_llm_agents_executions, :tenant_id)).to be false

      apply_migrations_from_to("0.3.3", "0.4.0")
      expect(index_exists?(:ruby_llm_agents_executions, :tenant_id)).to be true
      expect(index_exists?(:ruby_llm_agents_executions, [:tenant_id, :agent_type])).to be true
    end
  end

  describe "foreign key integrity" do
    # Note: Foreign key support depends on database adapter
    # SQLite doesn't enforce foreign keys by default

    it "parent_execution_id references executions table" do
      build_schema_for_version("0.2.3")

      # Create parent and child
      hierarchy = MigrationTestData.seed_execution_hierarchy

      # Verify referential integrity maintained after upgrade
      apply_migrations_from_to("0.2.3", "0.4.0")

      records = all_records
      parent = records.find { |r| r["parent_execution_id"].nil? && r["root_execution_id"] == r["id"] }
      children = records.select { |r| r["parent_execution_id"] == parent["id"] }

      expect(children.length).to eq(3)
    end

    it "deleting parent does not cascade delete children (nullify)" do
      build_schema_for_version("0.4.0")

      hierarchy = MigrationTestData.seed_execution_hierarchy
      root_id = hierarchy[:root][:id]

      # Delete parent
      connection = ActiveRecord::Base.connection
      connection.execute("DELETE FROM ruby_llm_agents_executions WHERE id = #{root_id}")

      # Children should still exist (with nullified parent)
      remaining = all_records
      expect(remaining.length).to eq(3)
    end
  end

  describe "backward compatibility with model code" do
    before do
      build_schema_for_version("0.4.0")
    end

    it "schema supports Execution model operations" do
      # The schema should support standard ActiveRecord operations
      connection = ActiveRecord::Base.connection

      # Insert
      connection.execute(
        ActiveRecord::Base.sanitize_sql_array([
          "INSERT INTO ruby_llm_agents_executions
           (agent_type, model_id, started_at, status, parameters, metadata, tool_calls, created_at, updated_at)
           VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)",
          "TestAgent", "gpt-4", Time.current, "success", "{}", "{}", "[]", Time.current, Time.current
        ])
      )

      # Select
      result = connection.select_all("SELECT * FROM ruby_llm_agents_executions")
      expect(result.to_a.length).to eq(1)

      # Update
      connection.execute("UPDATE ruby_llm_agents_executions SET status = 'error' WHERE agent_type = 'TestAgent'")

      # Verify
      result = connection.select_one("SELECT status FROM ruby_llm_agents_executions WHERE agent_type = 'TestAgent'")
      expect(result["status"]).to eq("error")

      # Delete
      connection.execute("DELETE FROM ruby_llm_agents_executions WHERE agent_type = 'TestAgent'")
      expect(record_count).to eq(0)
    end

    it "schema supports TenantBudget model operations" do
      connection = ActiveRecord::Base.connection

      # Insert
      connection.execute(
        ActiveRecord::Base.sanitize_sql_array([
          "INSERT INTO ruby_llm_agents_tenant_budgets
           (tenant_id, daily_limit, per_agent_daily, per_agent_monthly, created_at, updated_at)
           VALUES (?, ?, ?, ?, ?, ?)",
          "test_tenant", 100.0, "{}", "{}", Time.current, Time.current
        ])
      )

      # Select
      result = connection.select_all("SELECT * FROM ruby_llm_agents_tenant_budgets")
      expect(result.to_a.length).to eq(1)

      # Unique constraint
      expect {
        connection.execute(
          ActiveRecord::Base.sanitize_sql_array([
            "INSERT INTO ruby_llm_agents_tenant_budgets
             (tenant_id, per_agent_daily, per_agent_monthly, created_at, updated_at)
             VALUES (?, ?, ?, ?, ?)",
            "test_tenant", "{}", "{}", Time.current, Time.current
          ])
        )
      }.to raise_error(ActiveRecord::RecordNotUnique)
    end

  end

  describe "table existence across versions" do
    it "executions table exists in all versions" do
      %w[0.1.0 0.2.3 0.3.3 0.4.0].each do |version|
        reset_database!
        build_schema_for_version(version)
        expect(table_exists?(:ruby_llm_agents_executions)).to be(true),
          "Expected executions table to exist in version #{version}"
      end
    end

    it "tenant_budgets table only exists in 0.4.0" do
      %w[0.1.0 0.2.3 0.3.3].each do |version|
        reset_database!
        build_schema_for_version(version)
        expect(table_exists?(:ruby_llm_agents_tenant_budgets)).to be(false),
          "Expected tenant_budgets table NOT to exist in version #{version}"
      end

      reset_database!
      build_schema_for_version("0.4.0")
      expect(table_exists?(:ruby_llm_agents_tenant_budgets)).to be true
    end

  end

  describe "column count evolution" do
    it "column count increases with each version" do
      column_counts = {}

      %w[0.1.0 0.2.3 0.3.3 0.4.0].each do |version|
        reset_database!
        build_schema_for_version(version)
        column_counts[version] = column_names.length
      end

      expect(column_counts["0.2.3"]).to be > column_counts["0.1.0"]
      expect(column_counts["0.3.3"]).to be > column_counts["0.2.3"]
      expect(column_counts["0.4.0"]).to be > column_counts["0.3.3"]
    end
  end
end
