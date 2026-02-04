# frozen_string_literal: true

# Test data seeding methods for migration tests
#
# Each method creates test data compatible with the schema
# that existed at that version. Uses raw SQL to avoid
# ActiveRecord model dependencies.
module MigrationTestData
  class << self
    # Seed basic execution data compatible with v0.1.0 schema
    #
    # @param count [Integer] Number of records to create
    # @return [Array<Hash>] The created records with their IDs
    def seed_v0_1_0_data(count: 3)
      connection = ActiveRecord::Base.connection
      records = []

      count.times do |i|
        now = Time.current
        started_at = now - rand(1..60).minutes

        record = {
          agent_type: "TestAgent#{i}",
          model_id: "gpt-4",
          model_provider: "openai",
          temperature: 0.7,
          started_at: started_at,
          completed_at: now,
          duration_ms: rand(100..5000),
          status: %w[success error].sample,
          input_tokens: rand(100..1000),
          output_tokens: rand(50..500),
          total_tokens: rand(150..1500),
          input_cost: rand(1..100) / 1000.0,
          output_cost: rand(1..100) / 1000.0,
          total_cost: rand(2..200) / 1000.0,
          parameters: { prompt: "Test prompt #{i}", max_tokens: 1000 }.to_json,
          response: { content: "Test response #{i}" }.to_json,
          metadata: { test_key: "test_value_#{i}" }.to_json,
          error_class: i.even? ? nil : "TestError",
          error_message: i.even? ? nil : "Test error message #{i}",
          created_at: now,
          updated_at: now
        }

        columns = record.keys.join(", ")
        placeholders = record.keys.map { "?" }.join(", ")

        connection.execute(
          ActiveRecord::Base.sanitize_sql_array([
            "INSERT INTO ruby_llm_agents_executions (#{columns}) VALUES (#{placeholders})",
            *record.values
          ])
        )

        record[:id] = connection.select_value("SELECT last_insert_rowid()")
        records << record
      end

      records
    end

    # Seed data with streaming/tracing/caching fields (v0.2.3)
    #
    # @param count [Integer] Number of records to create
    # @return [Array<Hash>] The created records with their IDs
    def seed_v0_2_3_data(count: 3)
      connection = ActiveRecord::Base.connection
      records = []

      count.times do |i|
        now = Time.current
        started_at = now - rand(1..60).minutes
        trace_id = SecureRandom.uuid

        record = {
          # v0.1.0 fields
          agent_type: "StreamingAgent#{i}",
          model_id: "claude-3-opus",
          model_provider: "anthropic",
          temperature: 0.5,
          started_at: started_at,
          completed_at: now,
          duration_ms: rand(100..5000),
          status: "success",
          input_tokens: rand(100..1000),
          output_tokens: rand(50..500),
          total_tokens: rand(150..1500),
          input_cost: rand(1..100) / 1000.0,
          output_cost: rand(1..100) / 1000.0,
          total_cost: rand(2..200) / 1000.0,
          parameters: { prompt: "Streaming test #{i}" }.to_json,
          response: { content: "Streaming response #{i}" }.to_json,
          metadata: { streaming: true }.to_json,
          error_class: nil,
          error_message: nil,

          # v0.2.3 fields
          streaming: true,
          time_to_first_token_ms: rand(50..500),
          finish_reason: "end_turn",
          request_id: SecureRandom.uuid,
          trace_id: trace_id,
          span_id: SecureRandom.hex(8),
          parent_execution_id: nil,
          root_execution_id: nil,
          fallback_reason: nil,
          retryable: true,
          rate_limited: false,
          cache_hit: i.even?,
          response_cache_key: i.even? ? "cache_key_#{i}" : nil,
          cached_at: i.even? ? now - 1.hour : nil,
          cached_tokens: i.even? ? rand(100..500) : 0,
          cache_creation_tokens: i.odd? ? rand(100..500) : 0,
          system_prompt: "You are a helpful assistant #{i}",
          user_prompt: "Help me with task #{i}",
          created_at: now,
          updated_at: now
        }

        columns = record.keys.join(", ")
        placeholders = record.keys.map { "?" }.join(", ")

        connection.execute(
          ActiveRecord::Base.sanitize_sql_array([
            "INSERT INTO ruby_llm_agents_executions (#{columns}) VALUES (#{placeholders})",
            *record.values
          ])
        )

        record[:id] = connection.select_value("SELECT last_insert_rowid()")
        records << record
      end

      records
    end

    # Seed data with tool calls fields (v0.3.3)
    #
    # @param count [Integer] Number of records to create
    # @return [Array<Hash>] The created records with their IDs
    def seed_v0_3_3_data(count: 3)
      connection = ActiveRecord::Base.connection
      records = []

      count.times do |i|
        now = Time.current
        started_at = now - rand(1..60).minutes

        tool_calls = [
          { name: "search", arguments: { query: "test #{i}" }, result: "found #{i} results" },
          { name: "calculate", arguments: { expression: "2+2" }, result: "4" }
        ]

        record = {
          # v0.1.0 fields
          agent_type: "ToolAgent#{i}",
          model_id: "gpt-4-turbo",
          model_provider: "openai",
          temperature: 0.0,
          started_at: started_at,
          completed_at: now,
          duration_ms: rand(100..5000),
          status: "success",
          input_tokens: rand(100..1000),
          output_tokens: rand(50..500),
          total_tokens: rand(150..1500),
          input_cost: rand(1..100) / 1000.0,
          output_cost: rand(1..100) / 1000.0,
          total_cost: rand(2..200) / 1000.0,
          parameters: { tools: %w[search calculate] }.to_json,
          response: { content: "Used tools #{i}" }.to_json,
          metadata: { has_tools: true }.to_json,
          error_class: nil,
          error_message: nil,

          # v0.2.3 fields
          streaming: false,
          time_to_first_token_ms: nil,
          finish_reason: "tool_use",
          request_id: SecureRandom.uuid,
          trace_id: SecureRandom.uuid,
          span_id: SecureRandom.hex(8),
          parent_execution_id: nil,
          root_execution_id: nil,
          fallback_reason: nil,
          retryable: true,
          rate_limited: false,
          cache_hit: false,
          response_cache_key: nil,
          cached_at: nil,
          cached_tokens: 0,
          cache_creation_tokens: 0,
          system_prompt: "You have access to tools",
          user_prompt: "Use tools to help me",

          # v0.3.3 fields
          tool_calls: tool_calls.to_json,
          tool_calls_count: tool_calls.length,
          workflow_id: "workflow_#{i}",
          workflow_type: "parallel",
          workflow_step: "step_#{i % 3}",
          routed_to: "SpecializedAgent#{i}",
          classification_result: { category: "technical", confidence: 0.95 }.to_json,
          created_at: now,
          updated_at: now
        }

        columns = record.keys.join(", ")
        placeholders = record.keys.map { "?" }.join(", ")

        connection.execute(
          ActiveRecord::Base.sanitize_sql_array([
            "INSERT INTO ruby_llm_agents_executions (#{columns}) VALUES (#{placeholders})",
            *record.values
          ])
        )

        record[:id] = connection.select_value("SELECT last_insert_rowid()")
        records << record
      end

      records
    end

    # Seed complete data with all v0.4.0 fields
    #
    # @param count [Integer] Number of records to create
    # @return [Hash] Created records grouped by table
    def seed_v0_4_0_data(count: 3)
      connection = ActiveRecord::Base.connection
      result = { executions: [], tenant_budgets: [] }

      # Create tenant budgets first
      tenant_ids = %w[tenant_1 tenant_2 tenant_3]
      tenant_ids.each_with_index do |tenant_id, i|
        now = Time.current
        budget = {
          tenant_id: tenant_id,
          name: "Tenant #{i + 1}",
          daily_limit: (i + 1) * 100.0,
          monthly_limit: (i + 1) * 1000.0,
          daily_token_limit: (i + 1) * 1_000_000,
          monthly_token_limit: (i + 1) * 10_000_000,
          per_agent_daily: { "TestAgent" => (i + 1) * 10.0 }.to_json,
          per_agent_monthly: { "TestAgent" => (i + 1) * 100.0 }.to_json,
          enforcement: %w[none soft hard][i],
          inherit_global_defaults: i != 2,
          created_at: now,
          updated_at: now
        }

        columns = budget.keys.join(", ")
        placeholders = budget.keys.map { "?" }.join(", ")

        connection.execute(
          ActiveRecord::Base.sanitize_sql_array([
            "INSERT INTO ruby_llm_agents_tenant_budgets (#{columns}) VALUES (#{placeholders})",
            *budget.values
          ])
        )

        budget[:id] = connection.select_value("SELECT last_insert_rowid()")
        result[:tenant_budgets] << budget
      end

      # Create executions with full v0.4.0 fields
      count.times do |i|
        now = Time.current
        started_at = now - rand(1..60).minutes
        tenant_id = tenant_ids[i % tenant_ids.length]

        attempts = [
          { model: "gpt-4", status: "success", duration_ms: rand(100..1000) }
        ]

        messages_summary = {
          first: { role: "user", content: "Hello..." },
          last: { role: "assistant", content: "Here is..." }
        }

        record = {
          # v0.1.0 fields
          agent_type: "FullAgent#{i}",
          model_id: "gpt-4",
          model_provider: "openai",
          temperature: 0.7,
          started_at: started_at,
          completed_at: now,
          duration_ms: rand(100..5000),
          status: "success",
          input_tokens: rand(100..1000),
          output_tokens: rand(50..500),
          total_tokens: rand(150..1500),
          input_cost: rand(1..100) / 1000.0,
          output_cost: rand(1..100) / 1000.0,
          total_cost: rand(2..200) / 1000.0,
          parameters: { test: true }.to_json,
          response: { content: "Response #{i}" }.to_json,
          metadata: { full_version: true }.to_json,
          error_class: nil,
          error_message: nil,

          # v0.2.3 fields
          streaming: true,
          time_to_first_token_ms: rand(50..200),
          finish_reason: "end_turn",
          request_id: SecureRandom.uuid,
          trace_id: SecureRandom.uuid,
          span_id: SecureRandom.hex(8),
          parent_execution_id: nil,
          root_execution_id: nil,
          fallback_reason: nil,
          retryable: true,
          rate_limited: false,
          cache_hit: false,
          response_cache_key: nil,
          cached_at: nil,
          cached_tokens: 0,
          cache_creation_tokens: 0,
          system_prompt: "System prompt #{i}",
          user_prompt: "User prompt #{i}",

          # v0.3.3 fields
          tool_calls: [].to_json,
          tool_calls_count: 0,
          workflow_id: nil,
          workflow_type: nil,
          workflow_step: nil,
          routed_to: nil,
          classification_result: nil,

          # v0.4.0 fields
          attempts: attempts.to_json,
          attempts_count: attempts.length,
          chosen_model_id: "gpt-4",
          fallback_chain: %w[gpt-4 gpt-3.5-turbo].to_json,
          tenant_id: tenant_id,
          messages_count: rand(1..10),
          messages_summary: messages_summary.to_json,
          created_at: now,
          updated_at: now
        }

        columns = record.keys.join(", ")
        placeholders = record.keys.map { "?" }.join(", ")

        connection.execute(
          ActiveRecord::Base.sanitize_sql_array([
            "INSERT INTO ruby_llm_agents_executions (#{columns}) VALUES (#{placeholders})",
            *record.values
          ])
        )

        record[:id] = connection.select_value("SELECT last_insert_rowid()")
        result[:executions] << record
      end

      result
    end

    # Seed execution hierarchy (parent/child relationships)
    # Requires v0.2.3+ schema for parent_execution_id
    #
    # @return [Hash] Root and child execution records
    def seed_execution_hierarchy
      connection = ActiveRecord::Base.connection
      now = Time.current
      started_at = now - 10.minutes
      trace_id = SecureRandom.uuid

      # Create root execution
      root = {
        agent_type: "RootAgent",
        model_id: "gpt-4",
        model_provider: "openai",
        temperature: 0.7,
        started_at: started_at,
        completed_at: now,
        duration_ms: 5000,
        status: "success",
        input_tokens: 500,
        output_tokens: 200,
        total_tokens: 700,
        input_cost: 0.01,
        output_cost: 0.005,
        total_cost: 0.015,
        parameters: {}.to_json,
        response: {}.to_json,
        metadata: { is_root: true }.to_json,
        streaming: false,
        trace_id: trace_id,
        span_id: SecureRandom.hex(8),
        parent_execution_id: nil,
        root_execution_id: nil,
        created_at: now,
        updated_at: now
      }

      columns = root.keys.join(", ")
      placeholders = root.keys.map { "?" }.join(", ")

      connection.execute(
        ActiveRecord::Base.sanitize_sql_array([
          "INSERT INTO ruby_llm_agents_executions (#{columns}) VALUES (#{placeholders})",
          *root.values
        ])
      )

      root[:id] = connection.select_value("SELECT last_insert_rowid()")

      # Update root_execution_id to point to itself
      connection.execute(
        ActiveRecord::Base.sanitize_sql_array([
          "UPDATE ruby_llm_agents_executions SET root_execution_id = ? WHERE id = ?",
          root[:id], root[:id]
        ])
      )
      root[:root_execution_id] = root[:id]

      # Create child executions
      children = []
      3.times do |i|
        child = {
          agent_type: "ChildAgent#{i}",
          model_id: "gpt-3.5-turbo",
          model_provider: "openai",
          temperature: 0.5,
          started_at: started_at + (i + 1).minutes,
          completed_at: now - (3 - i).minutes,
          duration_ms: rand(500..2000),
          status: "success",
          input_tokens: rand(100..300),
          output_tokens: rand(50..150),
          total_tokens: rand(150..450),
          input_cost: 0.001,
          output_cost: 0.0005,
          total_cost: 0.0015,
          parameters: {}.to_json,
          response: {}.to_json,
          metadata: { is_child: true, child_index: i }.to_json,
          streaming: false,
          trace_id: trace_id,
          span_id: SecureRandom.hex(8),
          parent_execution_id: root[:id],
          root_execution_id: root[:id],
          created_at: now,
          updated_at: now
        }

        columns = child.keys.join(", ")
        placeholders = child.keys.map { "?" }.join(", ")

        connection.execute(
          ActiveRecord::Base.sanitize_sql_array([
            "INSERT INTO ruby_llm_agents_executions (#{columns}) VALUES (#{placeholders})",
            *child.values
          ])
        )

        child[:id] = connection.select_value("SELECT last_insert_rowid()")
        children << child
      end

      { root: root, children: children }
    end

    # Seed large dataset for performance testing
    #
    # @param count [Integer] Number of records to create
    # @return [Integer] Number of records created
    def seed_large_dataset(count: 1000)
      connection = ActiveRecord::Base.connection

      count.times do |i|
        now = Time.current
        started_at = now - rand(1..1440).minutes

        values = [
          "BulkAgent",
          %w[gpt-4 gpt-3.5-turbo claude-3-opus].sample,
          %w[openai anthropic].sample,
          0.7,
          started_at,
          started_at + rand(1..60).seconds,
          rand(100..5000),
          %w[success error].sample,
          rand(100..1000),
          rand(50..500),
          rand(150..1500),
          rand(1..100) / 1000.0,
          rand(1..100) / 1000.0,
          rand(2..200) / 1000.0,
          { batch: i }.to_json,
          { result: i }.to_json,
          { bulk: true }.to_json,
          now,
          now
        ]

        connection.execute(
          ActiveRecord::Base.sanitize_sql_array([
            "INSERT INTO ruby_llm_agents_executions (
              agent_type, model_id, model_provider, temperature,
              started_at, completed_at, duration_ms, status,
              input_tokens, output_tokens, total_tokens,
              input_cost, output_cost, total_cost,
              parameters, response, metadata,
              created_at, updated_at
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
            *values
          ])
        )
      end

      count
    end
  end
end
