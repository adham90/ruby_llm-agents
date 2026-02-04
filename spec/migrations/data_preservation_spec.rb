# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Data Preservation During Upgrades", type: :migration do
  describe "original column values preserved" do
    before do
      build_schema_for_version("0.1.0")
    end

    it "preserves agent_type values" do
      records = MigrationTestData.seed_v0_1_0_data(count: 5)
      original_values = records.map { |r| r[:agent_type] }

      apply_migrations_from_to("0.1.0", "0.4.0")

      current = all_records
      current_values = current.map { |r| r["agent_type"] }

      expect(current_values).to match_array(original_values)
    end

    it "preserves model_id values" do
      records = MigrationTestData.seed_v0_1_0_data(count: 5)
      original_values = records.map { |r| r[:model_id] }

      apply_migrations_from_to("0.1.0", "0.4.0")

      current = all_records
      current_values = current.map { |r| r["model_id"] }

      expect(current_values).to match_array(original_values)
    end

    it "preserves token counts" do
      records = MigrationTestData.seed_v0_1_0_data(count: 3)
      original_totals = records.map { |r| r[:total_tokens] }

      apply_migrations_from_to("0.1.0", "0.4.0")

      current = all_records
      current_totals = current.map { |r| r["total_tokens"] }

      expect(current_totals).to match_array(original_totals)
    end

    it "preserves cost values with precision" do
      records = MigrationTestData.seed_v0_1_0_data(count: 3)
      original_costs = records.map { |r| r[:total_cost].to_f.round(6) }

      apply_migrations_from_to("0.1.0", "0.4.0")

      current = all_records
      current_costs = current.map { |r| r["total_cost"].to_f.round(6) }

      expect(current_costs).to match_array(original_costs)
    end

    it "preserves timestamps" do
      records = MigrationTestData.seed_v0_1_0_data(count: 3)

      apply_migrations_from_to("0.1.0", "0.4.0")

      current = all_records

      records.each do |original|
        found = current.find { |r| r["id"] == original[:id] }
        expect(found).not_to be_nil

        # Compare timestamps (allowing for slight serialization differences)
        original_created = Time.zone.parse(original[:created_at].to_s)
        current_created = Time.zone.parse(found["created_at"].to_s)

        expect(current_created).to be_within(1.second).of(original_created)
      end
    end
  end

  describe "error records preserved" do
    before do
      build_schema_for_version("0.1.0")
    end

    it "preserves error_class values" do
      records = MigrationTestData.seed_v0_1_0_data(count: 5)
      error_records = records.select { |r| r[:error_class] }

      apply_migrations_from_to("0.1.0", "0.4.0")

      current = all_records.select { |r| r["error_class"] }

      expect(current.length).to eq(error_records.length)
    end

    it "preserves error_message content" do
      records = MigrationTestData.seed_v0_1_0_data(count: 5)
      original_messages = records.map { |r| r[:error_message] }.compact

      apply_migrations_from_to("0.1.0", "0.4.0")

      current = all_records
      current_messages = current.map { |r| r["error_message"] }.compact

      expect(current_messages).to match_array(original_messages)
    end

    it "preserves status values for error records" do
      records = MigrationTestData.seed_v0_1_0_data(count: 10)
      original_error_count = records.count { |r| r[:status] == "error" }

      apply_migrations_from_to("0.1.0", "0.4.0")

      current = all_records
      current_error_count = current.count { |r| r["status"] == "error" }

      expect(current_error_count).to eq(original_error_count)
    end
  end

  describe "execution hierarchy (parent/child) maintained" do
    before do
      build_schema_for_version("0.2.3")
    end

    it "preserves parent_execution_id references" do
      hierarchy = MigrationTestData.seed_execution_hierarchy
      root_id = hierarchy[:root][:id]
      child_parent_ids = hierarchy[:children].map { |c| c[:parent_execution_id] }

      apply_migrations_from_to("0.2.3", "0.4.0")

      current = all_records
      current_children = current.select { |r| r["parent_execution_id"] }

      current_parent_ids = current_children.map { |r| r["parent_execution_id"] }

      expect(current_parent_ids).to match_array(child_parent_ids)
      expect(current_parent_ids.uniq).to eq([root_id])
    end

    it "preserves root_execution_id references" do
      hierarchy = MigrationTestData.seed_execution_hierarchy
      root_id = hierarchy[:root][:id]

      apply_migrations_from_to("0.2.3", "0.4.0")

      current = all_records
      root_refs = current.map { |r| r["root_execution_id"] }.compact

      expect(root_refs.uniq).to eq([root_id])
    end

    it "preserves trace_id consistency within hierarchy" do
      hierarchy = MigrationTestData.seed_execution_hierarchy
      original_trace_id = hierarchy[:root][:trace_id]

      apply_migrations_from_to("0.2.3", "0.4.0")

      current = all_records
      trace_ids = current.map { |r| r["trace_id"] }.compact

      expect(trace_ids.uniq).to eq([original_trace_id])
    end

    it "maintains child count after upgrade" do
      hierarchy = MigrationTestData.seed_execution_hierarchy
      root_id = hierarchy[:root][:id]
      original_child_count = hierarchy[:children].length

      apply_migrations_from_to("0.2.3", "0.4.0")

      current = all_records
      current_child_count = current.count { |r| r["parent_execution_id"] == root_id }

      expect(current_child_count).to eq(original_child_count)
    end
  end

  describe "JSON fields (parameters, response, metadata) intact" do
    before do
      build_schema_for_version("0.1.0")
    end

    it "preserves parameters JSON structure" do
      records = MigrationTestData.seed_v0_1_0_data(count: 3)

      apply_migrations_from_to("0.1.0", "0.4.0")

      current = all_records

      records.each do |original|
        found = current.find { |r| r["id"] == original[:id] }
        expect(found).not_to be_nil

        original_params = JSON.parse(original[:parameters])
        current_params = found["parameters"]
        current_params = JSON.parse(current_params) if current_params.is_a?(String)

        expect(current_params).to eq(original_params)
      end
    end

    it "preserves response JSON structure" do
      records = MigrationTestData.seed_v0_1_0_data(count: 3)

      apply_migrations_from_to("0.1.0", "0.4.0")

      current = all_records

      records.each do |original|
        found = current.find { |r| r["id"] == original[:id] }
        expect(found).not_to be_nil

        original_response = JSON.parse(original[:response])
        current_response = found["response"]
        current_response = JSON.parse(current_response) if current_response.is_a?(String)

        expect(current_response).to eq(original_response)
      end
    end

    it "preserves metadata JSON structure" do
      records = MigrationTestData.seed_v0_1_0_data(count: 3)

      apply_migrations_from_to("0.1.0", "0.4.0")

      current = all_records

      records.each do |original|
        found = current.find { |r| r["id"] == original[:id] }
        expect(found).not_to be_nil

        original_metadata = JSON.parse(original[:metadata])
        current_metadata = found["metadata"]
        current_metadata = JSON.parse(current_metadata) if current_metadata.is_a?(String)

        expect(current_metadata).to eq(original_metadata)
      end
    end

    it "preserves nested JSON values" do
      build_schema_for_version("0.3.3")
      records = MigrationTestData.seed_v0_3_3_data(count: 3)

      apply_migrations_from_to("0.3.3", "0.4.0")

      current = all_records

      records.each do |original|
        found = current.find { |r| r["id"] == original[:id] }
        expect(found).not_to be_nil

        original_tool_calls = JSON.parse(original[:tool_calls])
        current_tool_calls = found["tool_calls"]
        current_tool_calls = JSON.parse(current_tool_calls) if current_tool_calls.is_a?(String)

        expect(current_tool_calls).to eq(original_tool_calls)
      end
    end
  end

  describe "large dataset migration performance" do
    before do
      build_schema_for_version("0.1.0")
    end

    it "migrates 100 records without data loss" do
      MigrationTestData.seed_large_dataset(count: 100)
      expect(record_count).to eq(100)

      apply_migrations_from_to("0.1.0", "0.4.0")

      expect(record_count).to eq(100)
    end

    it "migrates 500 records in reasonable time", performance: true do
      MigrationTestData.seed_large_dataset(count: 500)

      start_time = Time.current
      apply_migrations_from_to("0.1.0", "0.4.0")
      duration = Time.current - start_time

      expect(record_count).to eq(500)
      expect(duration).to be < 30.seconds
    end

    it "maintains data integrity across large dataset" do
      MigrationTestData.seed_large_dataset(count: 100)

      # Get sample of original records
      original = all_records.first(10)
      original_ids = original.map { |r| r["id"] }

      apply_migrations_from_to("0.1.0", "0.4.0")

      # Verify sample records still exist and have original data
      current = all_records
      sample = current.select { |r| original_ids.include?(r["id"]) }

      expect(sample.length).to eq(10)

      original.each do |orig|
        found = sample.find { |r| r["id"] == orig["id"] }
        expect(found["agent_type"]).to eq(orig["agent_type"])
        expect(found["model_id"]).to eq(orig["model_id"])
      end
    end
  end

  describe "tenant data preservation" do
    before do
      build_schema_for_version("0.4.0")
    end

    it "preserves tenant_budget records" do
      data = MigrationTestData.seed_v0_4_0_data(count: 3)
      original_budgets = data[:tenant_budgets]

      current = ActiveRecord::Base.connection.select_all(
        "SELECT * FROM ruby_llm_agents_tenant_budgets"
      ).to_a

      expect(current.length).to eq(original_budgets.length)

      original_budgets.each do |orig|
        found = current.find { |r| r["tenant_id"] == orig[:tenant_id] }
        expect(found).not_to be_nil
        expect(found["daily_limit"].to_f).to eq(orig[:daily_limit])
        expect(found["monthly_limit"].to_f).to eq(orig[:monthly_limit])
      end
    end

    it "preserves execution tenant_id associations" do
      data = MigrationTestData.seed_v0_4_0_data(count: 5)
      original_tenant_ids = data[:executions].map { |e| e[:tenant_id] }

      current = all_records
      current_tenant_ids = current.map { |r| r["tenant_id"] }

      expect(current_tenant_ids).to match_array(original_tenant_ids)
    end
  end
end
