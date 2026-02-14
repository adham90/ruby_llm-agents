# frozen_string_literal: true

require "rails_helper"
require "generators/ruby_llm_agents/upgrade_generator"

RSpec.describe RubyLlmAgents::UpgradeGenerator, type: :generator do
  # The upgrade generator checks for existing columns/tables in the database
  # We mock these checks to test different upgrade scenarios

  before do
    allow(Rails).to receive(:root).and_return(Pathname.new(destination_root))
    allow(RubyLLM::Agents.configuration).to receive(:root_directory).and_return("llm")
    allow(RubyLLM::Agents.configuration).to receive(:root_namespace).and_return("Llm")

    # Default: tenant table exists, old table doesn't
    allow(ActiveRecord::Base.connection).to receive(:table_exists?)
      .with(:ruby_llm_agents_tenants)
      .and_return(true)
    allow(ActiveRecord::Base.connection).to receive(:table_exists?)
      .with(:ruby_llm_agents_tenant_budgets)
      .and_return(false)
  end

  describe "when executions table does not exist (fresh install needed)" do
    before do
      allow(ActiveRecord::Base.connection).to receive(:table_exists?)
        .with(:ruby_llm_agents_executions)
        .and_return(false)
      allow(ActiveRecord::Base.connection).to receive(:table_exists?)
        .with(:ruby_llm_agents_execution_details)
        .and_return(false)

      run_generator
    end

    it "creates the split migration" do
      expect(Dir[file("db/migrate/*_split_execution_details_from_executions.rb")]).not_to be_empty
    end
  end

  describe "when on pre-2.0 schema (detail columns on executions, no execution_details table)" do
    before do
      allow(ActiveRecord::Base.connection).to receive(:table_exists?)
        .with(:ruby_llm_agents_executions)
        .and_return(true)
      allow(ActiveRecord::Base.connection).to receive(:table_exists?)
        .with(:ruby_llm_agents_execution_details)
        .and_return(false)

      # Old schema has detail columns on executions
      allow(ActiveRecord::Base.connection).to receive(:column_exists?) do |table, column|
        next false unless table == :ruby_llm_agents_executions

        # All old columns exist including detail columns
        ![:agent_version].include?(column)
      end

      run_generator
    end

    it "creates the split migration" do
      expect(Dir[file("db/migrate/*_split_execution_details_from_executions.rb")]).not_to be_empty
    end
  end

  describe "when execution_details exists but old columns remain on executions" do
    before do
      allow(ActiveRecord::Base.connection).to receive(:table_exists?)
        .with(:ruby_llm_agents_executions)
        .and_return(true)
      allow(ActiveRecord::Base.connection).to receive(:table_exists?)
        .with(:ruby_llm_agents_execution_details)
        .and_return(true)

      # Simulates partial upgrade: execution_details exists but old columns still on executions
      allow(ActiveRecord::Base.connection).to receive(:column_exists?) do |table, column|
        next false unless table == :ruby_llm_agents_executions

        # Detail columns still present on executions (not yet cleaned up)
        %i[system_prompt user_prompt error_message response tool_calls
           attempts fallback_chain parameters routed_to
           classification_result cached_at cache_creation_tokens].include?(column)
      end

      run_generator
    end

    it "creates the split migration to clean up" do
      expect(Dir[file("db/migrate/*_split_execution_details_from_executions.rb")]).not_to be_empty
    end
  end

  describe "when deprecated columns remain on executions" do
    before do
      allow(ActiveRecord::Base.connection).to receive(:table_exists?)
        .with(:ruby_llm_agents_executions)
        .and_return(true)
      allow(ActiveRecord::Base.connection).to receive(:table_exists?)
        .with(:ruby_llm_agents_execution_details)
        .and_return(true)

      # Detail columns removed, but deprecated columns still present
      allow(ActiveRecord::Base.connection).to receive(:column_exists?) do |table, column|
        next false unless table == :ruby_llm_agents_executions

        %i[workflow_id workflow_type workflow_step agent_version span_id].include?(column)
      end

      run_generator
    end

    it "creates the split migration to remove deprecated columns" do
      expect(Dir[file("db/migrate/*_split_execution_details_from_executions.rb")]).not_to be_empty
    end
  end

  describe "when fully upgraded (clean 2.0 schema)" do
    before do
      allow(ActiveRecord::Base.connection).to receive(:table_exists?)
        .with(:ruby_llm_agents_executions)
        .and_return(true)
      allow(ActiveRecord::Base.connection).to receive(:table_exists?)
        .with(:ruby_llm_agents_execution_details)
        .and_return(true)

      # No detail, niche, or deprecated columns on executions
      allow(ActiveRecord::Base.connection).to receive(:column_exists?)
        .and_return(false)

      run_generator
    end

    it "creates no migrations" do
      migration_files = Dir[file("db/migrate/*.rb")]
      expect(migration_files).to be_empty
    end
  end

  describe "tenant_budgets to tenants rename" do
    context "when old tenant_budgets exists and new tenants does not" do
      before do
        allow(ActiveRecord::Base.connection).to receive(:table_exists?)
          .with(:ruby_llm_agents_executions)
          .and_return(true)
        allow(ActiveRecord::Base.connection).to receive(:table_exists?)
          .with(:ruby_llm_agents_execution_details)
          .and_return(true)
        allow(ActiveRecord::Base.connection).to receive(:table_exists?)
          .with(:ruby_llm_agents_tenant_budgets)
          .and_return(true)
        allow(ActiveRecord::Base.connection).to receive(:table_exists?)
          .with(:ruby_llm_agents_tenants)
          .and_return(false)
        allow(ActiveRecord::Base.connection).to receive(:column_exists?)
          .and_return(false)
        run_generator
      end

      it "creates rename migration" do
        expect(Dir[file("db/migrate/*_rename_tenant_budgets_to_tenants.rb")]).not_to be_empty
      end
    end

    context "when tenants table already exists" do
      before do
        allow(ActiveRecord::Base.connection).to receive(:table_exists?)
          .with(:ruby_llm_agents_executions)
          .and_return(true)
        allow(ActiveRecord::Base.connection).to receive(:table_exists?)
          .with(:ruby_llm_agents_execution_details)
          .and_return(true)
        allow(ActiveRecord::Base.connection).to receive(:table_exists?)
          .with(:ruby_llm_agents_tenants)
          .and_return(true)
        allow(ActiveRecord::Base.connection).to receive(:table_exists?)
          .with(:ruby_llm_agents_tenant_budgets)
          .and_return(false)
        allow(ActiveRecord::Base.connection).to receive(:column_exists?)
          .and_return(false)
        run_generator
      end

      it "skips rename migration" do
        expect(Dir[file("db/migrate/*_rename_tenant_budgets_to_tenants.rb")]).to be_empty
      end
    end

    context "when neither table exists" do
      before do
        allow(ActiveRecord::Base.connection).to receive(:table_exists?)
          .with(:ruby_llm_agents_executions)
          .and_return(true)
        allow(ActiveRecord::Base.connection).to receive(:table_exists?)
          .with(:ruby_llm_agents_execution_details)
          .and_return(true)
        allow(ActiveRecord::Base.connection).to receive(:table_exists?)
          .with(:ruby_llm_agents_tenants)
          .and_return(false)
        allow(ActiveRecord::Base.connection).to receive(:table_exists?)
          .with(:ruby_llm_agents_tenant_budgets)
          .and_return(false)
        allow(ActiveRecord::Base.connection).to receive(:column_exists?)
          .and_return(false)
        run_generator
      end

      it "skips rename migration" do
        expect(Dir[file("db/migrate/*_rename_tenant_budgets_to_tenants.rb")]).to be_empty
      end
    end
  end

  describe "split migration content" do
    before do
      allow(ActiveRecord::Base.connection).to receive(:table_exists?)
        .with(:ruby_llm_agents_executions)
        .and_return(true)
      allow(ActiveRecord::Base.connection).to receive(:table_exists?)
        .with(:ruby_llm_agents_execution_details)
        .and_return(false)
      allow(ActiveRecord::Base.connection).to receive(:column_exists?)
        .and_return(false)

      run_generator
    end

    it "creates execution_details table definition" do
      migration_file = Dir[file("db/migrate/*_split_execution_details_from_executions.rb")].first
      content = File.read(migration_file)
      expect(content).to include("ruby_llm_agents_execution_details")
      expect(content).to include("error_message")
      expect(content).to include("system_prompt")
      expect(content).to include("user_prompt")
      expect(content).to include("response")
      expect(content).to include("tool_calls")
      expect(content).to include("attempts")
      expect(content).to include("fallback_chain")
      expect(content).to include("parameters")
      expect(content).to include("routed_to")
      expect(content).to include("classification_result")
      expect(content).to include("cached_at")
      expect(content).to include("cache_creation_tokens")
    end

    it "handles idempotent operations" do
      migration_file = Dir[file("db/migrate/*_split_execution_details_from_executions.rb")].first
      content = File.read(migration_file)
      expect(content).to include("column_exists?")
      expect(content).to include("table_exists?")
    end
  end

  describe "generator runs safely" do
    before do
      allow(ActiveRecord::Base.connection).to receive(:table_exists?)
        .with(:ruby_llm_agents_executions)
        .and_return(true)
      allow(ActiveRecord::Base.connection).to receive(:table_exists?)
        .with(:ruby_llm_agents_execution_details)
        .and_return(true)
      allow(ActiveRecord::Base.connection).to receive(:column_exists?)
        .and_return(false)
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

    it "does not move agent files" do
      FileUtils.mkdir_p(file("app/agents"))
      File.write(file("app/agents/test_agent.rb"), "class TestAgent; end")
      run_generator
      expect(file_exists?("app/agents/test_agent.rb")).to be true
    end

    it "does not move tool files" do
      FileUtils.mkdir_p(file("app/tools"))
      File.write(file("app/tools/test_tool.rb"), "class TestTool; end")
      run_generator
      expect(file_exists?("app/tools/test_tool.rb")).to be true
    end

    it "can be run multiple times safely" do
      run_generator
      expect { run_generator }.not_to raise_error
    end

    it "does not create migrations when fully upgraded" do
      run_generator
      migration_files = Dir[file("db/migrate/*.rb")]
      expect(migration_files).to be_empty
    end
  end
end
