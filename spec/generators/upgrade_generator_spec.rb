# frozen_string_literal: true

require "rails_helper"
require "generators/ruby_llm_agents/upgrade_generator"

RSpec.describe RubyLlmAgents::UpgradeGenerator, type: :generator do
  # The upgrade generator checks for existing columns in the database
  # We need to mock the column_exists? method to test different scenarios

  # Stub Rails.root for file migration tests
  before do
    allow(Rails).to receive(:root).and_return(Pathname.new(destination_root))
    # Stub configuration to use "llm" as root_directory for migration tests
    allow(RubyLLM::Agents.configuration).to receive(:root_directory).and_return("llm")
    allow(RubyLLM::Agents.configuration).to receive(:root_namespace).and_return("Llm")

    # Default tenant table checks to avoid migration generation for most tests
    # (tests that need tenant migration behavior should override these)
    allow(ActiveRecord::Base.connection).to receive(:table_exists?)
      .with(:ruby_llm_agents_tenants)
      .and_return(true)  # New table "exists" by default
    allow(ActiveRecord::Base.connection).to receive(:table_exists?)
      .with(:ruby_llm_agents_tenant_budgets)
      .and_return(false)  # Old table doesn't exist
  end

  describe "when table does not exist" do
    before do
      # Default all tables to not exist
      allow(ActiveRecord::Base.connection).to receive(:table_exists?).and_return(false)

      run_generator
    end

    it "creates all upgrade migrations" do
      # When table doesn't exist, column_exists? returns false, so all migrations are created
      expect(Dir[file("db/migrate/*_add_prompts_to_ruby_llm_agents_executions.rb")]).not_to be_empty
      expect(Dir[file("db/migrate/*_add_attempts_to_ruby_llm_agents_executions.rb")]).not_to be_empty
      expect(Dir[file("db/migrate/*_add_streaming_to_ruby_llm_agents_executions.rb")]).not_to be_empty
      expect(Dir[file("db/migrate/*_add_tracing_to_ruby_llm_agents_executions.rb")]).not_to be_empty
      expect(Dir[file("db/migrate/*_add_routing_to_ruby_llm_agents_executions.rb")]).not_to be_empty
      expect(Dir[file("db/migrate/*_add_finish_reason_to_ruby_llm_agents_executions.rb")]).not_to be_empty
      expect(Dir[file("db/migrate/*_add_caching_to_ruby_llm_agents_executions.rb")]).not_to be_empty
      expect(Dir[file("db/migrate/*_add_tool_calls_to_ruby_llm_agents_executions.rb")]).not_to be_empty
      expect(Dir[file("db/migrate/*_add_execution_type_to_ruby_llm_agents_executions.rb")]).not_to be_empty
    end
  end

  describe "when all columns already exist" do
    before do
      allow(ActiveRecord::Base.connection).to receive(:table_exists?)
        .with(:ruby_llm_agents_executions)
        .and_return(true)

      # Mock all columns as existing
      allow(ActiveRecord::Base.connection).to receive(:column_exists?).and_return(true)

      run_generator
    end

    it "creates no migration files" do
      migration_files = Dir[file("db/migrate/*.rb")]
      expect(migration_files).to be_empty
    end
  end

  describe "when only some columns exist" do
    before do
      allow(ActiveRecord::Base.connection).to receive(:table_exists?)
        .with(:ruby_llm_agents_executions)
        .and_return(true)

      # Mock specific columns as existing/missing
      allow(ActiveRecord::Base.connection).to receive(:column_exists?) do |table, column|
        # Simulate: prompts and attempts exist, but streaming and others don't
        existing_columns = [:system_prompt, :attempts]
        existing_columns.include?(column)
      end

      run_generator
    end

    it "skips migrations for existing columns" do
      expect(Dir[file("db/migrate/*_add_prompts_to_ruby_llm_agents_executions.rb")]).to be_empty
      expect(Dir[file("db/migrate/*_add_attempts_to_ruby_llm_agents_executions.rb")]).to be_empty
    end

    it "creates migrations for missing columns" do
      expect(Dir[file("db/migrate/*_add_streaming_to_ruby_llm_agents_executions.rb")]).not_to be_empty
      expect(Dir[file("db/migrate/*_add_tracing_to_ruby_llm_agents_executions.rb")]).not_to be_empty
      expect(Dir[file("db/migrate/*_add_routing_to_ruby_llm_agents_executions.rb")]).not_to be_empty
      expect(Dir[file("db/migrate/*_add_finish_reason_to_ruby_llm_agents_executions.rb")]).not_to be_empty
      expect(Dir[file("db/migrate/*_add_caching_to_ruby_llm_agents_executions.rb")]).not_to be_empty
      expect(Dir[file("db/migrate/*_add_tool_calls_to_ruby_llm_agents_executions.rb")]).not_to be_empty
      expect(Dir[file("db/migrate/*_add_execution_type_to_ruby_llm_agents_executions.rb")]).not_to be_empty
    end
  end

  describe "migration content" do
    before do
      # Default all tables to not exist
      allow(ActiveRecord::Base.connection).to receive(:table_exists?).and_return(false)

      run_generator
    end

    it "add_prompts migration adds system_prompt and user_prompt columns" do
      migration_file = Dir[file("db/migrate/*_add_prompts_to_ruby_llm_agents_executions.rb")].first
      content = File.read(migration_file)
      expect(content).to include("system_prompt")
      expect(content).to include("user_prompt")
    end

    it "add_attempts migration adds attempts column" do
      migration_file = Dir[file("db/migrate/*_add_attempts_to_ruby_llm_agents_executions.rb")].first
      content = File.read(migration_file)
      expect(content).to include("attempts")
    end

    it "add_streaming migration adds streaming column" do
      migration_file = Dir[file("db/migrate/*_add_streaming_to_ruby_llm_agents_executions.rb")].first
      content = File.read(migration_file)
      expect(content).to include("streaming")
    end

    it "add_tracing migration adds trace_id column" do
      migration_file = Dir[file("db/migrate/*_add_tracing_to_ruby_llm_agents_executions.rb")].first
      content = File.read(migration_file)
      expect(content).to include("trace_id")
    end

    it "add_routing migration adds fallback_reason column" do
      migration_file = Dir[file("db/migrate/*_add_routing_to_ruby_llm_agents_executions.rb")].first
      content = File.read(migration_file)
      expect(content).to include("fallback_reason")
    end

    it "add_finish_reason migration adds finish_reason column" do
      migration_file = Dir[file("db/migrate/*_add_finish_reason_to_ruby_llm_agents_executions.rb")].first
      content = File.read(migration_file)
      expect(content).to include("finish_reason")
    end

    it "add_caching migration adds cache_hit column" do
      migration_file = Dir[file("db/migrate/*_add_caching_to_ruby_llm_agents_executions.rb")].first
      content = File.read(migration_file)
      expect(content).to include("cache_hit")
    end

    it "add_tool_calls migration adds tool_calls column" do
      migration_file = Dir[file("db/migrate/*_add_tool_calls_to_ruby_llm_agents_executions.rb")].first
      content = File.read(migration_file)
      expect(content).to include("tool_calls")
    end

    it "add_execution_type migration adds execution_type column" do
      migration_file = Dir[file("db/migrate/*_add_execution_type_to_ruby_llm_agents_executions.rb")].first
      content = File.read(migration_file)
      expect(content).to include("execution_type")
    end
  end

  # ============================================
  # Agent and Tool Migration Tests
  # ============================================
  # NOTE: File migration (moving agents/tools to app/llm/) has been removed
  # from the upgrade generator as part of the database schema refactor.
  # The upgrade generator now only handles database migration generation.

  describe "generator runs without file migration" do
    before do
      allow(ActiveRecord::Base.connection).to receive(:table_exists?)
        .with(:ruby_llm_agents_executions)
        .and_return(true)
      allow(ActiveRecord::Base.connection).to receive(:column_exists?).and_return(true)
    end

    it "runs without error when app/agents exists" do
      FileUtils.mkdir_p(file("app/agents"))
      File.write(file("app/agents/test_agent.rb"), "class TestAgent; end")
      expect { run_generator }.not_to raise_error
    end

    it "runs without error when app/tools exists" do
      FileUtils.mkdir_p(file("app/tools"))
      File.write(file("app/tools/test_tool.rb"), "class TestTool; end")
      expect { run_generator }.not_to raise_error
    end

    it "does not move agent files (file migration removed)" do
      FileUtils.mkdir_p(file("app/agents"))
      File.write(file("app/agents/test_agent.rb"), "class TestAgent; end")
      run_generator
      # Agent files stay where they are - migration is no longer part of upgrade generator
      expect(file_exists?("app/agents/test_agent.rb")).to be true
    end

    it "does not move tool files (file migration removed)" do
      FileUtils.mkdir_p(file("app/tools"))
      File.write(file("app/tools/test_tool.rb"), "class TestTool; end")
      run_generator
      expect(file_exists?("app/tools/test_tool.rb")).to be true
    end

    it "can be run multiple times safely" do
      run_generator
      expect { run_generator }.not_to raise_error
    end

    it "does not create migrations when all columns exist" do
      run_generator
      migration_files = Dir[file("db/migrate/*.rb")]
      expect(migration_files).to be_empty
    end
  end
end
