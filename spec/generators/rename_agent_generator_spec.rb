# frozen_string_literal: true

require "rails_helper"
require "generators/ruby_llm_agents/rename_agent_generator"

RSpec.describe RubyLlmAgents::RenameAgentGenerator, type: :generator do
  describe "migration generation" do
    before { run_generator ["CustomerSupportAgent", "SupportBot"] }

    it "creates a migration file" do
      migration_files = Dir[file("db/migrate/*_rename_customer_support_agent_to_support_bot.rb")]
      expect(migration_files).not_to be_empty
    end

    it "generates reversible up migration" do
      migration_files = Dir[file("db/migrate/*_rename_customer_support_agent_to_support_bot.rb")]
      content = File.read(migration_files.first)
      expect(content).to include("def up")
      expect(content).to include("SET agent_type = 'SupportBot'")
      expect(content).to include("WHERE agent_type = 'CustomerSupportAgent'")
    end

    it "generates reversible down migration" do
      migration_files = Dir[file("db/migrate/*_rename_customer_support_agent_to_support_bot.rb")]
      content = File.read(migration_files.first)
      expect(content).to include("def down")
      expect(content).to include("SET agent_type = 'CustomerSupportAgent'")
      expect(content).to include("WHERE agent_type = 'SupportBot'")
    end

    it "generates a proper class name" do
      migration_files = Dir[file("db/migrate/*_rename_customer_support_agent_to_support_bot.rb")]
      content = File.read(migration_files.first)
      expect(content).to include("class RenameCustomerSupportAgentToSupportBot")
    end
  end
end
