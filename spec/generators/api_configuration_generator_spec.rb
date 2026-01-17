# frozen_string_literal: true

require "rails_helper"
require "generators/ruby_llm_agents/api_configuration_generator"

RSpec.describe RubyLlmAgents::ApiConfigurationGenerator, type: :generator do
  # Helper to capture stdout
  def capture_stdout
    original_stdout = $stdout
    $stdout = StringIO.new
    yield
    $stdout.string
  ensure
    $stdout = original_stdout
  end
  describe "when table does not exist" do
    before do
      allow(ActiveRecord::Base.connection).to receive(:table_exists?)
        .with(:ruby_llm_agents_api_configurations)
        .and_return(false)

      run_generator
    end

    it "creates the migration file" do
      migration_files = Dir[file("db/migrate/*_create_ruby_llm_agents_api_configurations.rb")]
      expect(migration_files).not_to be_empty
    end
  end

  describe "when table already exists" do
    before do
      allow(ActiveRecord::Base.connection).to receive(:table_exists?)
        .with(:ruby_llm_agents_api_configurations)
        .and_return(true)

      run_generator
    end

    it "skips creating the migration file" do
      migration_files = Dir[file("db/migrate/*_create_ruby_llm_agents_api_configurations.rb")]
      expect(migration_files).to be_empty
    end
  end

  describe "migration content" do
    before do
      allow(ActiveRecord::Base.connection).to receive(:table_exists?)
        .with(:ruby_llm_agents_api_configurations)
        .and_return(false)

      run_generator
    end

    it "creates api_configurations table" do
      migration_files = Dir[file("db/migrate/*_create_ruby_llm_agents_api_configurations.rb")]
      content = File.read(migration_files.first)

      expect(content).to include("create_table :ruby_llm_agents_api_configurations")
    end

    it "includes scope_type and scope_id columns" do
      migration_files = Dir[file("db/migrate/*_create_ruby_llm_agents_api_configurations.rb")]
      content = File.read(migration_files.first)

      expect(content).to include("scope_type")
      expect(content).to include("scope_id")
    end

    it "includes API key columns" do
      migration_files = Dir[file("db/migrate/*_create_ruby_llm_agents_api_configurations.rb")]
      content = File.read(migration_files.first)

      expect(content).to include("openai_api_key")
      expect(content).to include("anthropic_api_key")
    end

    it "includes inherit_global_defaults column" do
      migration_files = Dir[file("db/migrate/*_create_ruby_llm_agents_api_configurations.rb")]
      content = File.read(migration_files.first)

      expect(content).to include("inherit_global_defaults")
    end

    it "includes unique index on scope_type and scope_id" do
      migration_files = Dir[file("db/migrate/*_create_ruby_llm_agents_api_configurations.rb")]
      content = File.read(migration_files.first)

      expect(content).to include("add_index")
      expect(content).to include("scope_type")
      expect(content).to include("scope_id")
    end
  end

  describe "post-install message" do
    it "displays setup instructions" do
      allow(ActiveRecord::Base.connection).to receive(:table_exists?)
        .with(:ruby_llm_agents_api_configurations)
        .and_return(false)

      output = capture_stdout { run_generator }

      expect(output).to include("API Configuration migration created!")
      expect(output).to include("bin/rails db:encryption:init")
      expect(output).to include("rails db:migrate")
      expect(output).to include("/agents/api_configuration")
    end
  end
end
