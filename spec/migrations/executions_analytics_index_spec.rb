# frozen_string_literal: true

require "rails_helper"

# Runs the real upgrade migration template that adds the covering index behind
# the dashboard's aggregate queries.
RSpec.describe "AddExecutionsAnalyticsIndex migration", type: :migration do
  self.use_transactional_tests = false if respond_to?(:use_transactional_tests=)

  before(:all) do
    template_path = File.expand_path(
      "../../lib/generators/ruby_llm_agents/templates/add_executions_analytics_index_migration.rb.tt",
      __dir__
    )
    migration_version = "[#{ActiveRecord::VERSION::STRING.to_f}]"
    rendered = ERB.new(File.read(template_path)).result(binding)

    Object.send(:remove_const, :AddExecutionsAnalyticsIndex) if defined?(AddExecutionsAnalyticsIndex)
    eval(rendered, TOPLEVEL_BINDING, template_path) # rubocop:disable Security/Eval
  end

  let(:connection) { ActiveRecord::Base.connection }
  let(:table) { :ruby_llm_agents_executions }
  let(:index_name) { "idx_executions_analytics" }
  let(:postgres) { connection.adapter_name.downcase.include?("postg") }

  def run_migration(direction)
    migration = AddExecutionsAnalyticsIndex.new
    migration.verbose = false
    migration.public_send(direction)
  end

  def analytics_index
    connection.indexes(table).find { |index| index.name == index_name }
  end

  before do
    ActiveRecord::Schema.verbose = false
    load File.expand_path("../dummy/db/schema.rb", __dir__)
    connection.remove_index(table, name: index_name)
  end

  it "adds the index on an existing installation" do
    expect(analytics_index).to be_nil

    run_migration(:up)

    expect(analytics_index).to be_present
    expect(Array(analytics_index.columns).first).to eq("created_at")
  end

  it "covers the columns the dashboard aggregates" do
    run_migration(:up)

    definition = if postgres
      connection.select_value("SELECT indexdef FROM pg_indexes WHERE indexname = '#{index_name}'")
    else
      Array(analytics_index.columns).join(", ")
    end

    expect(definition).to include("INCLUDE") if postgres
    %w[agent_type model_id chosen_model_id status error_class tenant_id parent_execution_id
      total_cost total_tokens input_tokens output_tokens duration_ms cache_hit streaming].each do |column|
      expect(definition).to include(column)
    end
  end

  it "leaves the index valid on PostgreSQL" do
    skip "PostgreSQL only" unless postgres

    run_migration(:up)

    valid = connection.select_value(<<~SQL)
      SELECT indisvalid FROM pg_index
      JOIN pg_class ON pg_class.oid = pg_index.indexrelid WHERE pg_class.relname = '#{index_name}'
    SQL
    expect(valid).to be(true)
  end

  it "only covers columns the installation actually has" do
    connection.remove_column(table, :chosen_model_id)

    run_migration(:up)

    expect(analytics_index).to be_present
    expect(Array(analytics_index.columns).join).not_to include("chosen_model_id")
  end

  it "can be run again after an interrupted build" do
    run_migration(:up)

    expect { run_migration(:up) }.not_to raise_error
    expect(connection.indexes(table).count { |index| index.name == index_name }).to eq(1)
  end

  it "keeps the dashboard queries working with real data" do
    run_migration(:up)
    RubyLLM::Agents::Execution.reset_column_information
    create(:execution, agent_type: "SearchAgent")

    expect(RubyLLM::Agents::Execution.last_n_days(7).breakdown.totals[:total]).to eq(1)
  end

  it "removes the index on rollback" do
    run_migration(:up)

    run_migration(:down)

    expect(analytics_index).to be_nil
  end
end
