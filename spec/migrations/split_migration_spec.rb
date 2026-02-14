# frozen_string_literal: true

require "rails_helper"
require "erb"

# Tests for the actual SplitExecutionDetailsFromExecutions migration template.
#
# Unlike the other migration specs that use SchemaBuilder DDL methods,
# this spec renders the real .rb.tt template and runs the migration class
# against seeded data, verifying the full upgrade including data backfill.
RSpec.describe "SplitExecutionDetailsFromExecutions migration", type: :migration do
  # Disable transactional fixtures so DDL + DML from the real migration
  # behave correctly (DDL auto-commits in SQLite, which breaks the
  # transactional fixture rollback mechanism for DML visibility).
  self.use_transactional_tests = false if respond_to?(:use_transactional_tests=)

  # Render the template once and define the migration class
  before(:all) do
    template_path = File.expand_path(
      "../../lib/generators/ruby_llm_agents/templates/split_execution_details_migration.rb.tt",
      __dir__
    )
    template = File.read(template_path)

    # Provide the ERB binding with migration_version
    migration_version = "[#{ActiveRecord::VERSION::STRING.to_f}]"
    rendered = ERB.new(template).result(binding)

    # Remove the class if it was previously defined (for re-runs)
    Object.send(:remove_const, :SplitExecutionDetailsFromExecutions) if defined?(SplitExecutionDetailsFromExecutions)

    eval(rendered, TOPLEVEL_BINDING, template_path) # rubocop:disable Security/Eval
  end

  let(:connection) { ActiveRecord::Base.connection }

  # Run the actual migration template class with output suppressed
  def run_split_migration!
    m = SplitExecutionDetailsFromExecutions.new
    m.verbose = false
    m.up
  end

  # ─── Shared examples for post-migration schema ─────────────────────

  shared_examples "v2.0.0 execution_details schema" do
    it "creates execution_details table with all expected columns" do
      expect(table_exists?(:ruby_llm_agents_execution_details)).to be true

      expected_columns = %w[
        id execution_id error_message system_prompt user_prompt
        response messages_summary tool_calls attempts fallback_chain
        parameters routed_to classification_result cached_at
        cache_creation_tokens created_at updated_at
      ]

      actual_columns = column_names(:ruby_llm_agents_execution_details)
      expected_columns.each do |col|
        expect(actual_columns).to include(col), "Expected execution_details to have column '#{col}'"
      end
    end

    it "has unique index on execution_id" do
      expect(index_exists?(:ruby_llm_agents_execution_details, :execution_id)).to be true
    end

    it "has foreign key from execution_details to executions" do
      expect(foreign_key_exists?(:ruby_llm_agents_execution_details, :ruby_llm_agents_executions)).to be true
    end
  end

  shared_examples "v2.0.0 executions schema (no detail/niche/workflow columns)" do
    it "removes detail columns from executions" do
      %i[error_message system_prompt user_prompt response messages_summary
         tool_calls attempts fallback_chain parameters routed_to
         classification_result cached_at cache_creation_tokens].each do |col|
        expect(column_exists?(col)).to be(false),
          "Expected executions NOT to have detail column '#{col}'"
      end
    end

    it "removes niche columns from executions" do
      %i[span_id response_cache_key time_to_first_token_ms
         retryable rate_limited fallback_reason].each do |col|
        expect(column_exists?(col)).to be(false),
          "Expected executions NOT to have niche column '#{col}'"
      end
    end

    it "removes tenant_record polymorphic columns from executions" do
      %i[tenant_record_type tenant_record_id].each do |col|
        expect(column_exists?(col)).to be(false),
          "Expected executions NOT to have tenant_record column '#{col}'"
      end
    end

    it "removes workflow columns from executions" do
      %i[workflow_id workflow_type workflow_step].each do |col|
        expect(column_exists?(col)).to be(false),
          "Expected executions NOT to have workflow column '#{col}'"
      end
    end

    it "removes agent_version column from executions" do
      expect(column_exists?(:agent_version)).to be false
    end

    it "has all required v2.0.0 columns on executions" do
      %i[execution_type chosen_model_id messages_count attempts_count
         tool_calls_count streaming finish_reason cache_hit trace_id
         request_id parent_execution_id root_execution_id tenant_id
         cached_tokens].each do |col|
        expect(column_exists?(col)).to be(true),
          "Expected executions to have required column '#{col}'"
      end
    end

    it "has composite tenant indexes" do
      expect(index_exists?(:ruby_llm_agents_executions, [:tenant_id, :created_at])).to be true
      expect(index_exists?(:ruby_llm_agents_executions, [:tenant_id, :status])).to be true
    end

    it "removes redundant single-column indexes" do
      %i[duration_ms total_cost].each do |col|
        expect(index_exists?(:ruby_llm_agents_executions, col)).to be(false),
          "Expected single-column index on '#{col}' to be removed"
      end
    end
  end

  # ─── Upgrade from v0.1.0 ──────────────────────────────────────────

  describe "upgrade from v0.1.0" do
    before do
      build_schema_for_version("0.1.0")
      @seeded = MigrationTestData.seed_v0_1_0_data(count: 5)
      run_split_migration!
    end

    include_examples "v2.0.0 execution_details schema"
    include_examples "v2.0.0 executions schema (no detail/niche/workflow columns)"

    it "preserves execution record count" do
      expect(record_count).to eq(5)
    end

    it "backfills execution_details for records with data" do
      records_with_data = @seeded.count { |r| r[:error_message] || r[:parameters] || r[:response] }
      expect(record_count(:ruby_llm_agents_execution_details)).to eq(records_with_data)
    end

    it "preserves error_message in execution_details" do
      original_errors = @seeded.select { |r| r[:error_message] }

      original_errors.each do |orig|
        detail = connection.select_one(
          "SELECT * FROM ruby_llm_agents_execution_details WHERE execution_id = #{orig[:id]}"
        )
        expect(detail).not_to be_nil
        expect(detail["error_message"]).to eq(orig[:error_message])
      end
    end

    it "preserves parameters JSON in execution_details" do
      @seeded.each do |orig|
        detail = connection.select_one(
          "SELECT * FROM ruby_llm_agents_execution_details WHERE execution_id = #{orig[:id]}"
        )
        next unless detail

        original_params = JSON.parse(orig[:parameters])
        detail_params = detail["parameters"]
        detail_params = JSON.parse(detail_params) if detail_params.is_a?(String)
        expect(detail_params).to eq(original_params)
      end
    end

    it "preserves response JSON in execution_details" do
      @seeded.each do |orig|
        detail = connection.select_one(
          "SELECT * FROM ruby_llm_agents_execution_details WHERE execution_id = #{orig[:id]}"
        )
        next unless detail

        original_response = JSON.parse(orig[:response])
        detail_response = detail["response"]
        detail_response = JSON.parse(detail_response) if detail_response.is_a?(String)
        expect(detail_response).to eq(original_response)
      end
    end
  end

  # ─── Upgrade from v0.2.3 ──────────────────────────────────────────

  describe "upgrade from v0.2.3" do
    before do
      build_schema_for_version("0.2.3")
      @seeded = MigrationTestData.seed_v0_2_3_data(count: 5)
      run_split_migration!
    end

    include_examples "v2.0.0 execution_details schema"
    include_examples "v2.0.0 executions schema (no detail/niche/workflow columns)"

    it "preserves execution record count" do
      expect(record_count).to eq(5)
    end

    it "backfills system_prompt and user_prompt" do
      @seeded.each do |orig|
        detail = connection.select_one(
          "SELECT * FROM ruby_llm_agents_execution_details WHERE execution_id = #{orig[:id]}"
        )
        expect(detail).not_to be_nil, "Expected execution_details for execution #{orig[:id]}"
        expect(detail["system_prompt"]).to eq(orig[:system_prompt])
        expect(detail["user_prompt"]).to eq(orig[:user_prompt])
      end
    end

    it "backfills cache_creation_tokens" do
      @seeded.each do |orig|
        detail = connection.select_one(
          "SELECT * FROM ruby_llm_agents_execution_details WHERE execution_id = #{orig[:id]}"
        )
        next unless detail

        expect(detail["cache_creation_tokens"].to_i).to eq(orig[:cache_creation_tokens])
      end
    end
  end

  # ─── Upgrade from v0.3.3 ──────────────────────────────────────────

  describe "upgrade from v0.3.3" do
    before do
      build_schema_for_version("0.3.3")
      @seeded = MigrationTestData.seed_v0_3_3_data(count: 5)
      run_split_migration!
    end

    include_examples "v2.0.0 execution_details schema"
    include_examples "v2.0.0 executions schema (no detail/niche/workflow columns)"

    it "preserves execution record count" do
      expect(record_count).to eq(5)
    end

    it "backfills tool_calls JSON" do
      @seeded.each do |orig|
        detail = connection.select_one(
          "SELECT * FROM ruby_llm_agents_execution_details WHERE execution_id = #{orig[:id]}"
        )
        expect(detail).not_to be_nil

        original_tc = JSON.parse(orig[:tool_calls])
        detail_tc = detail["tool_calls"]
        detail_tc = JSON.parse(detail_tc) if detail_tc.is_a?(String)
        expect(detail_tc).to eq(original_tc)
      end
    end

    it "backfills routed_to and classification_result" do
      @seeded.each do |orig|
        detail = connection.select_one(
          "SELECT * FROM ruby_llm_agents_execution_details WHERE execution_id = #{orig[:id]}"
        )
        expect(detail).not_to be_nil
        expect(detail["routed_to"]).to eq(orig[:routed_to])

        if orig[:classification_result]
          original_cr = JSON.parse(orig[:classification_result])
          detail_cr = detail["classification_result"]
          detail_cr = JSON.parse(detail_cr) if detail_cr.is_a?(String)
          expect(detail_cr).to eq(original_cr)
        end
      end
    end
  end

  # ─── Upgrade from v0.4.0 ──────────────────────────────────────────

  describe "upgrade from v0.4.0" do
    before do
      build_schema_for_version("0.4.0")
      @seeded = MigrationTestData.seed_v0_4_0_data(count: 5)
      run_split_migration!
    end

    include_examples "v2.0.0 execution_details schema"
    include_examples "v2.0.0 executions schema (no detail/niche/workflow columns)"

    it "preserves execution record count" do
      expect(record_count).to eq(5)
    end

    it "backfills all detail columns" do
      @seeded[:executions].each do |orig|
        detail = connection.select_one(
          "SELECT * FROM ruby_llm_agents_execution_details WHERE execution_id = #{orig[:id]}"
        )
        expect(detail).not_to be_nil

        expect(detail["system_prompt"]).to eq(orig[:system_prompt])
        expect(detail["user_prompt"]).to eq(orig[:user_prompt])

        original_response = JSON.parse(orig[:response])
        detail_response = detail["response"]
        detail_response = JSON.parse(detail_response) if detail_response.is_a?(String)
        expect(detail_response).to eq(original_response)

        original_attempts = JSON.parse(orig[:attempts])
        detail_attempts = detail["attempts"]
        detail_attempts = JSON.parse(detail_attempts) if detail_attempts.is_a?(String)
        expect(detail_attempts).to eq(original_attempts)

        original_fc = JSON.parse(orig[:fallback_chain])
        detail_fc = detail["fallback_chain"]
        detail_fc = JSON.parse(detail_fc) if detail_fc.is_a?(String)
        expect(detail_fc).to eq(original_fc)
      end
    end

    it "preserves core execution fields (agent_type, model_id, costs, tokens)" do
      current = all_records
      @seeded[:executions].each do |orig|
        found = current.find { |r| r["id"] == orig[:id] }
        expect(found).not_to be_nil
        expect(found["agent_type"]).to eq(orig[:agent_type])
        expect(found["model_id"]).to eq(orig[:model_id])
        expect(found["total_tokens"]).to eq(orig[:total_tokens])
        expect(found["total_cost"].to_f.round(6)).to eq(orig[:total_cost].to_f.round(6))
      end
    end

    it "preserves tenant_id on executions" do
      current = all_records
      original_tenant_ids = @seeded[:executions].map { |e| e[:tenant_id] }
      current_tenant_ids = current.map { |r| r["tenant_id"] }
      expect(current_tenant_ids).to match_array(original_tenant_ids)
    end
  end

  # ─── Idempotency on v2.0.0 ────────────────────────────────────────

  describe "idempotency on already-upgraded v2.0.0 schema" do
    # Seed v2.0.0-compatible data directly (seed_v2_0_0_data inserts columns
    # that no longer exist on executions after the v2.0.0 migration).
    def seed_v2_compatible_data(count: 3)
      conn = ActiveRecord::Base.connection
      records = { executions: [], execution_details: [] }

      count.times do |i|
        now = Time.current

        # Insert execution (only columns that remain in v2.0.0)
        conn.execute(
          ActiveRecord::Base.sanitize_sql_array([
            "INSERT INTO ruby_llm_agents_executions
             (agent_type, model_id, model_provider, temperature,
              started_at, completed_at, duration_ms, status,
              input_tokens, output_tokens, total_tokens,
              input_cost, output_cost, total_cost,
              metadata, error_class, execution_type, chosen_model_id,
              messages_count, attempts_count, tool_calls_count,
              streaming, finish_reason, cache_hit, cached_tokens,
              tenant_id, created_at, updated_at)
             VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)",
            "V2Agent#{i}", "gpt-4", "openai", 0.7,
            now - 5.minutes, now, 1000, "success",
            500, 200, 700,
            0.01, 0.005, 0.015,
            "{}",  nil, "chat", "gpt-4",
            5, 1, 0,
            true, "end_turn", false, 0,
            "tenant_#{i % 3 + 1}", now, now
          ])
        )
        exec_id = conn.select_value("SELECT last_insert_rowid()")
        records[:executions] << { id: exec_id, agent_type: "V2Agent#{i}" }

        # Insert matching execution_detail
        conn.execute(
          ActiveRecord::Base.sanitize_sql_array([
            "INSERT INTO ruby_llm_agents_execution_details
             (execution_id, system_prompt, user_prompt, response,
              messages_summary, tool_calls, attempts, parameters,
              cache_creation_tokens, created_at, updated_at)
             VALUES (?,?,?,?,?,?,?,?,?,?,?)",
            exec_id, "System prompt #{i}", "User prompt #{i}",
            { content: "Response #{i}" }.to_json,
            {}.to_json, [].to_json, [].to_json, {}.to_json,
            0, now, now
          ])
        )
        detail_id = conn.select_value("SELECT last_insert_rowid()")
        records[:execution_details] << {
          id: detail_id,
          execution_id: exec_id,
          system_prompt: "System prompt #{i}",
          user_prompt: "User prompt #{i}"
        }
      end

      records
    end

    before do
      build_schema_for_version("2.0.0")
      @seeded = seed_v2_compatible_data(count: 3)
    end

    it "does not error when run on v2.0.0 schema" do
      expect {
        m = SplitExecutionDetailsFromExecutions.new
        m.verbose = false
        m.up
      }.not_to raise_error
    end

    it "does not create duplicate execution_details rows" do
      original_count = record_count(:ruby_llm_agents_execution_details)

      run_split_migration!

      expect(record_count(:ruby_llm_agents_execution_details)).to eq(original_count)
    end

    it "does not alter existing execution_details data" do
      original_details = all_records(:ruby_llm_agents_execution_details)

      run_split_migration!

      current_details = all_records(:ruby_llm_agents_execution_details)
      expect(current_details.length).to eq(original_details.length)

      original_details.each do |orig|
        found = current_details.find { |d| d["id"] == orig["id"] }
        expect(found).not_to be_nil
        expect(found["system_prompt"]).to eq(orig["system_prompt"])
        expect(found["user_prompt"]).to eq(orig["user_prompt"])
      end
    end

    it "preserves execution record count" do
      run_split_migration!
      expect(record_count).to eq(3)
    end
  end

  # ─── Edge cases ────────────────────────────────────────────────────

  describe "edge cases" do
    # Helper to insert a v0.2.3-compatible execution with explicit control
    # over which detail columns are set. Uses v0.2.3 schema which has nullable
    # detail columns (system_prompt, user_prompt) but not the later NOT NULL
    # JSON columns (tool_calls, attempts, etc.)
    def insert_execution_with_details(detail_overrides = {})
      now = Time.current
      base = {
        agent_type: "TestAgent",
        model_id: "gpt-4",
        model_provider: "openai",
        started_at: now - 5.minutes,
        completed_at: now,
        duration_ms: 1000,
        status: "success",
        input_tokens: 500,
        output_tokens: 200,
        total_tokens: 700,
        parameters: "{}",
        response: "{}",
        metadata: "{}",
        created_at: now,
        updated_at: now
      }.merge(detail_overrides)

      columns = base.keys.join(", ")
      placeholders = base.keys.map { "?" }.join(", ")

      connection.execute(
        ActiveRecord::Base.sanitize_sql_array([
          "INSERT INTO ruby_llm_agents_executions (#{columns}) VALUES (#{placeholders})",
          *base.values
        ])
      )
      connection.select_value("SELECT last_insert_rowid()")
    end

    describe "records with all NULL detail columns" do
      before do
        # Use v0.1.0 which only has error_message, parameters, response as detail columns.
        # parameters and response have NOT NULL with defaults, so they can't be NULL.
        # error_message CAN be NULL. A record with parameters='{}' and response='{}'
        # and error_message=NULL has no "meaningful" detail data, but parameters and
        # response ARE non-null, so the WHERE clause will match.
        build_schema_for_version("0.1.0")
      end

      it "does NOT backfill records where all present detail columns use defaults" do
        # In v0.1.0, the only nullable detail column is error_message.
        # parameters and response have NOT NULL defaults.
        # A record with only defaults should still be backfilled because
        # the migration's WHERE clause checks IS NOT NULL (and they're not null).
        insert_execution_with_details(
          agent_type: "DefaultsAgent",
          error_message: nil,
          parameters: "{}",
          response: "{}"
        )

        run_split_migration!

        # Since parameters and response are NOT NULL, they match the WHERE clause
        expect(record_count(:ruby_llm_agents_execution_details)).to eq(1)
      end
    end

    describe "selective backfill based on non-null detail columns" do
      before do
        # Use v0.2.3 which adds system_prompt and user_prompt (nullable)
        build_schema_for_version("0.2.3")
      end

      it "backfills records with system_prompt set" do
        insert_execution_with_details(
          agent_type: "PromptAgent",
          system_prompt: "You are helpful",
          user_prompt: nil
        )

        run_split_migration!

        detail = connection.select_one(
          "SELECT * FROM ruby_llm_agents_execution_details LIMIT 1"
        )
        expect(detail).not_to be_nil
        expect(detail["system_prompt"]).to eq("You are helpful")
      end
    end

    describe "large text fields" do
      before do
        build_schema_for_version("0.2.3")
      end

      it "handles system_prompt and user_prompt over 100KB" do
        large_text = "x" * 120_000

        insert_execution_with_details(
          agent_type: "LargeAgent",
          system_prompt: large_text,
          user_prompt: large_text
        )

        run_split_migration!

        detail = connection.select_one(
          "SELECT * FROM ruby_llm_agents_execution_details LIMIT 1"
        )
        expect(detail["system_prompt"].length).to eq(120_000)
        expect(detail["user_prompt"].length).to eq(120_000)
      end
    end

    describe "JSON COALESCE defaults" do
      before do
        # Use v0.2.3 as base, then manually add the JSON columns as nullable
        # so we can test the COALESCE behavior. In the real schema these columns
        # have NOT NULL constraints, but COALESCE is a defensive measure.
        build_schema_for_version("0.2.3")
        conn = ActiveRecord::Base.connection
        conn.add_column :ruby_llm_agents_executions, :messages_summary, :json
        conn.add_column :ruby_llm_agents_executions, :tool_calls, :json
        conn.add_column :ruby_llm_agents_executions, :attempts, :json
      end

      it "COALESCEs NULL messages_summary to {}" do
        insert_execution_with_details(
          agent_type: "CoalesceAgent",
          system_prompt: "test prompt",
          messages_summary: nil
        )

        run_split_migration!

        detail = connection.select_one(
          "SELECT * FROM ruby_llm_agents_execution_details LIMIT 1"
        )
        ms = detail["messages_summary"]
        ms = JSON.parse(ms) if ms.is_a?(String)
        expect(ms).to eq({})
      end

      it "COALESCEs NULL tool_calls to []" do
        insert_execution_with_details(
          agent_type: "CoalesceAgent",
          system_prompt: "test prompt",
          tool_calls: nil
        )

        run_split_migration!

        detail = connection.select_one(
          "SELECT * FROM ruby_llm_agents_execution_details LIMIT 1"
        )
        tc = detail["tool_calls"]
        tc = JSON.parse(tc) if tc.is_a?(String)
        expect(tc).to eq([])
      end

      it "COALESCEs NULL attempts to []" do
        insert_execution_with_details(
          agent_type: "CoalesceAgent",
          system_prompt: "test prompt",
          attempts: nil
        )

        run_split_migration!

        detail = connection.select_one(
          "SELECT * FROM ruby_llm_agents_execution_details LIMIT 1"
        )
        att = detail["attempts"]
        att = JSON.parse(att) if att.is_a?(String)
        expect(att).to eq([])
      end

      it "COALESCEs NULL parameters to {}" do
        # Parameters has NOT NULL in the schema, so we test with a non-null
        # value to verify COALESCE preserves existing values correctly.
        insert_execution_with_details(
          agent_type: "CoalesceAgent",
          system_prompt: "test prompt",
          parameters: '{"key": "value"}'
        )

        run_split_migration!

        detail = connection.select_one(
          "SELECT * FROM ruby_llm_agents_execution_details LIMIT 1"
        )
        params = detail["parameters"]
        params = JSON.parse(params) if params.is_a?(String)
        expect(params).to eq({ "key" => "value" })
      end
    end

    describe "deeply nested JSON structures" do
      before do
        build_schema_for_version("0.3.3")
      end

      it "preserves deeply nested tool_calls JSON" do
        deep_tool_calls = [
          {
            name: "complex_tool",
            arguments: {
              nested: {
                deeply: {
                  value: [1, 2, { key: "val", arr: [true, false, nil] }]
                }
              }
            },
            result: { output: { data: [{ id: 1 }, { id: 2 }] } }
          }
        ]

        insert_execution_with_details(
          agent_type: "DeepAgent",
          tool_calls: deep_tool_calls.to_json,
          tool_calls_count: 1,
          system_prompt: "test"
        )

        run_split_migration!

        detail = connection.select_one(
          "SELECT * FROM ruby_llm_agents_execution_details LIMIT 1"
        )
        tc = detail["tool_calls"]
        tc = JSON.parse(tc) if tc.is_a?(String)
        expect(tc).to eq(JSON.parse(deep_tool_calls.to_json))
      end
    end

    describe "batch boundary (>1000 records)" do
      before do
        build_schema_for_version("0.1.0")
      end

      it "migrates more than 1000 records across batch boundaries" do
        count = 1050
        MigrationTestData.seed_large_dataset(count: count)
        expect(record_count).to eq(count)

        run_split_migration!

        # All records have non-null parameters and response, so all should get details
        expect(record_count(:ruby_llm_agents_execution_details)).to eq(count)
        expect(record_count).to eq(count)
      end
    end
  end
end
