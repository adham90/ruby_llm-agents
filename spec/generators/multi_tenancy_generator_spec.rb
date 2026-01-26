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

  describe "when tables do not exist (fresh install)" do
    before do
      allow(ActiveRecord::Base.connection).to receive(:table_exists?)
        .with(:ruby_llm_agents_tenants)
        .and_return(false)
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

    it "creates the tenants migration file" do
      migration_files = Dir[file("db/migrate/*_create_ruby_llm_agents_tenants.rb")]
      expect(migration_files).not_to be_empty
    end

    it "creates the add_tenant_id migration file" do
      migration_files = Dir[file("db/migrate/*_add_tenant_id_to_ruby_llm_agents_executions.rb")]
      expect(migration_files).not_to be_empty
    end
  end

  describe "when tenants table already exists" do
    before do
      allow(ActiveRecord::Base.connection).to receive(:table_exists?)
        .with(:ruby_llm_agents_tenants)
        .and_return(true)
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

    it "skips creating the tenants migration" do
      migration_files = Dir[file("db/migrate/*_create_ruby_llm_agents_tenants.rb")]
      expect(migration_files).to be_empty
    end

    it "still creates the add_tenant_id migration" do
      migration_files = Dir[file("db/migrate/*_add_tenant_id_to_ruby_llm_agents_executions.rb")]
      expect(migration_files).not_to be_empty
    end
  end

  describe "when old tenant_budgets table exists (upgrade path)" do
    before do
      allow(ActiveRecord::Base.connection).to receive(:table_exists?)
        .with(:ruby_llm_agents_tenants)
        .and_return(false)
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

    it "creates a rename migration instead of fresh install" do
      rename_files = Dir[file("db/migrate/*_rename_tenant_budgets_to_tenants.rb")]
      expect(rename_files).not_to be_empty
    end

    it "does not create fresh install migration" do
      fresh_files = Dir[file("db/migrate/*_create_ruby_llm_agents_tenants.rb")]
      expect(fresh_files).to be_empty
    end
  end

  describe "when tenant_id column already exists" do
    before do
      allow(ActiveRecord::Base.connection).to receive(:table_exists?)
        .with(:ruby_llm_agents_tenants)
        .and_return(false)
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

    it "still creates the tenants migration" do
      migration_files = Dir[file("db/migrate/*_create_ruby_llm_agents_tenants.rb")]
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
        .with(:ruby_llm_agents_tenants)
        .and_return(true)
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

    it "skips creating both migrations" do
      tenant_files = Dir[file("db/migrate/*_create_ruby_llm_agents_tenants.rb")]
      tenant_id_files = Dir[file("db/migrate/*_add_tenant_id_to_ruby_llm_agents_executions.rb")]

      expect(tenant_files).to be_empty
      expect(tenant_id_files).to be_empty
    end
  end

  describe "tenants migration content" do
    before do
      allow(ActiveRecord::Base.connection).to receive(:table_exists?)
        .with(:ruby_llm_agents_tenants)
        .and_return(false)
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

    it "creates tenants table" do
      migration_files = Dir[file("db/migrate/*_create_ruby_llm_agents_tenants.rb")]
      content = File.read(migration_files.first)

      expect(content).to include("create_table :ruby_llm_agents_tenants")
    end

    it "includes tenant_id column" do
      migration_files = Dir[file("db/migrate/*_create_ruby_llm_agents_tenants.rb")]
      content = File.read(migration_files.first)

      expect(content).to include("tenant_id")
    end

    it "includes budget limit columns" do
      migration_files = Dir[file("db/migrate/*_create_ruby_llm_agents_tenants.rb")]
      content = File.read(migration_files.first)

      expect(content).to include("daily_limit")
      expect(content).to include("monthly_limit")
    end

    it "includes enforcement column" do
      migration_files = Dir[file("db/migrate/*_create_ruby_llm_agents_tenants.rb")]
      content = File.read(migration_files.first)

      expect(content).to include("enforcement")
    end

    it "includes active column" do
      migration_files = Dir[file("db/migrate/*_create_ruby_llm_agents_tenants.rb")]
      content = File.read(migration_files.first)

      expect(content).to include("active")
    end

    it "includes metadata column" do
      migration_files = Dir[file("db/migrate/*_create_ruby_llm_agents_tenants.rb")]
      content = File.read(migration_files.first)

      expect(content).to include("metadata")
    end
  end

  describe "add_tenant_id migration content" do
    before do
      allow(ActiveRecord::Base.connection).to receive(:table_exists?)
        .with(:ruby_llm_agents_tenants)
        .and_return(true) # Skip the other migration
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
        .with(:ruby_llm_agents_tenants)
        .and_return(false)
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
      expect(output).to include("llm_tenant")
      expect(output).to include("Tenant.for")
    end
  end
end
