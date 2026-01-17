# frozen_string_literal: true

require "rails_helper"
require "generators/ruby_llm_agents/multi_tenancy_generator"

RSpec.describe RubyLlmAgents::MultiTenancyGenerator, type: :generator do
  # Helper to capture stdout
  def capture_stdout
    original_stdout = $stdout
    $stdout = StringIO.new
    yield
    $stdout.string
  ensure
    $stdout = original_stdout
  end
  describe "when tables do not exist" do
    before do
      allow(ActiveRecord::Base.connection).to receive(:table_exists?)
        .with(:ruby_llm_agents_tenant_budgets)
        .and_return(false)
      allow(ActiveRecord::Base.connection).to receive(:table_exists?)
        .with(:ruby_llm_agents_executions)
        .and_return(true)
      allow(ActiveRecord::Base.connection).to receive(:column_exists?)
        .with(:ruby_llm_agents_executions, :tenant_id)
        .and_return(false)

      run_generator
    end

    it "creates the tenant_budgets migration file" do
      migration_files = Dir[file("db/migrate/*_create_ruby_llm_agents_tenant_budgets.rb")]
      expect(migration_files).not_to be_empty
    end

    it "creates the add_tenant_id migration file" do
      migration_files = Dir[file("db/migrate/*_add_tenant_id_to_ruby_llm_agents_executions.rb")]
      expect(migration_files).not_to be_empty
    end
  end

  describe "when tenant_budgets table already exists" do
    before do
      allow(ActiveRecord::Base.connection).to receive(:table_exists?)
        .with(:ruby_llm_agents_tenant_budgets)
        .and_return(true)
      allow(ActiveRecord::Base.connection).to receive(:table_exists?)
        .with(:ruby_llm_agents_executions)
        .and_return(true)
      allow(ActiveRecord::Base.connection).to receive(:column_exists?)
        .with(:ruby_llm_agents_executions, :tenant_id)
        .and_return(false)

      run_generator
    end

    it "skips creating the tenant_budgets migration" do
      migration_files = Dir[file("db/migrate/*_create_ruby_llm_agents_tenant_budgets.rb")]
      expect(migration_files).to be_empty
    end

    it "still creates the add_tenant_id migration" do
      migration_files = Dir[file("db/migrate/*_add_tenant_id_to_ruby_llm_agents_executions.rb")]
      expect(migration_files).not_to be_empty
    end
  end

  describe "when tenant_id column already exists" do
    before do
      allow(ActiveRecord::Base.connection).to receive(:table_exists?)
        .with(:ruby_llm_agents_tenant_budgets)
        .and_return(false)
      allow(ActiveRecord::Base.connection).to receive(:table_exists?)
        .with(:ruby_llm_agents_executions)
        .and_return(true)
      allow(ActiveRecord::Base.connection).to receive(:column_exists?)
        .with(:ruby_llm_agents_executions, :tenant_id)
        .and_return(true)

      run_generator
    end

    it "still creates the tenant_budgets migration" do
      migration_files = Dir[file("db/migrate/*_create_ruby_llm_agents_tenant_budgets.rb")]
      expect(migration_files).not_to be_empty
    end

    it "skips creating the add_tenant_id migration" do
      migration_files = Dir[file("db/migrate/*_add_tenant_id_to_ruby_llm_agents_executions.rb")]
      expect(migration_files).to be_empty
    end
  end

  describe "when both already exist" do
    before do
      allow(ActiveRecord::Base.connection).to receive(:table_exists?)
        .with(:ruby_llm_agents_tenant_budgets)
        .and_return(true)
      allow(ActiveRecord::Base.connection).to receive(:table_exists?)
        .with(:ruby_llm_agents_executions)
        .and_return(true)
      allow(ActiveRecord::Base.connection).to receive(:column_exists?)
        .with(:ruby_llm_agents_executions, :tenant_id)
        .and_return(true)

      run_generator
    end

    it "skips creating both migrations" do
      budget_files = Dir[file("db/migrate/*_create_ruby_llm_agents_tenant_budgets.rb")]
      tenant_id_files = Dir[file("db/migrate/*_add_tenant_id_to_ruby_llm_agents_executions.rb")]

      expect(budget_files).to be_empty
      expect(tenant_id_files).to be_empty
    end
  end

  describe "tenant_budgets migration content" do
    before do
      allow(ActiveRecord::Base.connection).to receive(:table_exists?)
        .with(:ruby_llm_agents_tenant_budgets)
        .and_return(false)
      allow(ActiveRecord::Base.connection).to receive(:table_exists?)
        .with(:ruby_llm_agents_executions)
        .and_return(true)
      allow(ActiveRecord::Base.connection).to receive(:column_exists?)
        .with(:ruby_llm_agents_executions, :tenant_id)
        .and_return(true) # Skip the other migration

      run_generator
    end

    it "creates tenant_budgets table" do
      migration_files = Dir[file("db/migrate/*_create_ruby_llm_agents_tenant_budgets.rb")]
      content = File.read(migration_files.first)

      expect(content).to include("create_table :ruby_llm_agents_tenant_budgets")
    end

    it "includes tenant_id column" do
      migration_files = Dir[file("db/migrate/*_create_ruby_llm_agents_tenant_budgets.rb")]
      content = File.read(migration_files.first)

      expect(content).to include("tenant_id")
    end

    it "includes budget limit columns" do
      migration_files = Dir[file("db/migrate/*_create_ruby_llm_agents_tenant_budgets.rb")]
      content = File.read(migration_files.first)

      expect(content).to include("daily_limit")
      expect(content).to include("monthly_limit")
    end

    it "includes enforcement column" do
      migration_files = Dir[file("db/migrate/*_create_ruby_llm_agents_tenant_budgets.rb")]
      content = File.read(migration_files.first)

      expect(content).to include("enforcement")
    end
  end

  describe "add_tenant_id migration content" do
    before do
      allow(ActiveRecord::Base.connection).to receive(:table_exists?)
        .with(:ruby_llm_agents_tenant_budgets)
        .and_return(true) # Skip the other migration
      allow(ActiveRecord::Base.connection).to receive(:table_exists?)
        .with(:ruby_llm_agents_executions)
        .and_return(true)
      allow(ActiveRecord::Base.connection).to receive(:column_exists?)
        .with(:ruby_llm_agents_executions, :tenant_id)
        .and_return(false)

      run_generator
    end

    it "adds tenant_id to executions table" do
      migration_files = Dir[file("db/migrate/*_add_tenant_id_to_ruby_llm_agents_executions.rb")]
      content = File.read(migration_files.first)

      expect(content).to include("add_column :ruby_llm_agents_executions, :tenant_id")
    end

    it "adds index on tenant_id" do
      migration_files = Dir[file("db/migrate/*_add_tenant_id_to_ruby_llm_agents_executions.rb")]
      content = File.read(migration_files.first)

      expect(content).to include("add_index")
      expect(content).to include("tenant_id")
    end
  end

  describe "post-install message" do
    it "displays setup instructions" do
      allow(ActiveRecord::Base.connection).to receive(:table_exists?)
        .with(:ruby_llm_agents_tenant_budgets)
        .and_return(false)
      allow(ActiveRecord::Base.connection).to receive(:table_exists?)
        .with(:ruby_llm_agents_executions)
        .and_return(true)
      allow(ActiveRecord::Base.connection).to receive(:column_exists?)
        .with(:ruby_llm_agents_executions, :tenant_id)
        .and_return(false)

      output = capture_stdout { run_generator }

      expect(output).to include("Multi-tenancy migrations created!")
      expect(output).to include("rails db:migrate")
      expect(output).to include("multi_tenancy_enabled = true")
      expect(output).to include("tenant_resolver")
      expect(output).to include("TenantBudget.create!")
    end
  end
end
