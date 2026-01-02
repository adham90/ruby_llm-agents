# frozen_string_literal: true

require "rails_helper"
require "generators/ruby_llm_agents/upgrade_generator"

RSpec.describe RubyLlmAgents::UpgradeGenerator, type: :generator do
  # The upgrade generator checks for existing columns in the database
  # We need to mock the column_exists? method to test different scenarios

  describe "when table does not exist" do
    before do
      allow(ActiveRecord::Base.connection).to receive(:table_exists?)
        .with(:ruby_llm_agents_executions)
        .and_return(false)

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
    end
  end

  describe "migration content" do
    before do
      allow(ActiveRecord::Base.connection).to receive(:table_exists?)
        .with(:ruby_llm_agents_executions)
        .and_return(false)

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
  end
end
