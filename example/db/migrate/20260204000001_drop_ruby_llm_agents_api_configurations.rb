# frozen_string_literal: true

class DropRubyLLMAgentsApiConfigurations < ActiveRecord::Migration[8.1]
  def up
    drop_table :ruby_llm_agents_api_configurations, if_exists: true
  end

  def down
    raise ActiveRecord::IrreversibleMigration, <<~MSG
      The api_configurations table has been removed.
      Configure API keys via environment variables and ruby_llm gem configuration.
    MSG
  end
end
