# frozen_string_literal: true

require "fileutils"

# Helper module for version upgrade migration tests
#
# Provides utilities for:
# - Building schemas for specific gem versions
# - Applying migrations incrementally
# - Verifying data integrity after upgrades
#
# @example
#   describe "upgrade from 0.1.0 to 0.4.0" do
#     include MigrationHelpers
#
#     before do
#       build_schema_for_version("0.1.0")
#       seed_test_data_for_version("0.1.0")
#     end
#
#     it "preserves data" do
#       apply_migrations_to_version("0.4.0")
#       expect_data_integrity
#     end
#   end
module MigrationHelpers
  extend ActiveSupport::Concern

  # Version-to-migration mapping
  # Each version includes migrations up to and including that version
  VERSION_MIGRATIONS = {
    "0.1.0" => [:v0_1_0_base],
    "0.2.3" => [:v0_1_0_base, :v0_2_3_streaming_tracing_caching],
    "0.3.3" => [:v0_1_0_base, :v0_2_3_streaming_tracing_caching, :v0_3_3_tool_calls],
    "0.4.0" => [
      :v0_1_0_base,
      :v0_2_3_streaming_tracing_caching,
      :v0_3_3_tool_calls,
      :v0_4_0_reliability,
      :v0_4_0_tenant_budgets,
      :v0_4_0_tenant_id,
      :v0_4_0_messages_summary,
      :v0_4_0_tenant_name,
      :v0_4_0_token_limits,
      :v0_4_0_api_configurations
    ]
  }.freeze

  # Ordered list of all migrations for incremental application
  MIGRATION_ORDER = [
    :v0_1_0_base,
    :v0_2_3_streaming_tracing_caching,
    :v0_3_3_tool_calls,
    :v0_4_0_reliability,
    :v0_4_0_tenant_budgets,
    :v0_4_0_tenant_id,
    :v0_4_0_messages_summary,
    :v0_4_0_tenant_name,
    :v0_4_0_token_limits,
    :v0_4_0_api_configurations
  ].freeze

  # Version-to-starting migration mapping
  VERSION_START_INDEX = {
    "0.1.0" => 0,
    "0.2.3" => 2,
    "0.3.3" => 3,
    "0.4.0" => 10
  }.freeze

  included do
    before(:each) do
      reset_database!
    end

    after(:each) do
      reset_database!
    end
  end

  # Reset the database to a clean state
  def reset_database!
    connection = ActiveRecord::Base.connection

    # Drop all tables
    connection.tables.each do |table|
      connection.drop_table(table, force: :cascade, if_exists: true)
    end

    # Clear schema_migrations if it exists
    connection.execute("DELETE FROM schema_migrations") if connection.table_exists?("schema_migrations")
  rescue StandardError
    # Ignore errors during cleanup
  end

  # Build schema for a specific gem version
  #
  # @param version [String] The gem version (e.g., "0.1.0", "0.4.0")
  def build_schema_for_version(version)
    raise ArgumentError, "Unknown version: #{version}" unless VERSION_MIGRATIONS.key?(version)

    migrations = VERSION_MIGRATIONS[version]
    migrations.each do |migration|
      apply_migration(migration)
    end
  end

  # Apply migrations from one version to another
  #
  # @param from_version [String] Starting version
  # @param to_version [String] Target version
  def apply_migrations_from_to(from_version, to_version)
    from_index = VERSION_START_INDEX[from_version]
    to_index = VERSION_START_INDEX[to_version]

    raise ArgumentError, "Unknown from_version: #{from_version}" unless from_index
    raise ArgumentError, "Unknown to_version: #{to_version}" unless to_index
    raise ArgumentError, "Cannot downgrade from #{from_version} to #{to_version}" if from_index > to_index

    # Apply migrations from from_index to to_index
    MIGRATION_ORDER[from_index...to_index].each do |migration|
      apply_migration(migration)
    end
  end

  # Apply a specific migration
  #
  # @param migration_name [Symbol] The migration to apply
  def apply_migration(migration_name)
    SchemaBuilder.public_send(migration_name)
  end

  # Rollback a specific migration
  #
  # @param migration_name [Symbol] The migration to rollback
  def rollback_migration(migration_name)
    rollback_method = "#{migration_name}_down"
    if SchemaBuilder.respond_to?(rollback_method)
      SchemaBuilder.public_send(rollback_method)
    else
      raise NotImplementedError, "Rollback not implemented for #{migration_name}"
    end
  end

  # Check if a column exists in the executions table
  #
  # @param column_name [String, Symbol] The column name
  # @return [Boolean]
  def column_exists?(column_name, table_name = :ruby_llm_agents_executions)
    ActiveRecord::Base.connection.column_exists?(table_name, column_name)
  end

  # Check if a table exists
  #
  # @param table_name [String, Symbol] The table name
  # @return [Boolean]
  def table_exists?(table_name)
    ActiveRecord::Base.connection.table_exists?(table_name)
  end

  # Check if an index exists
  #
  # @param table_name [String, Symbol] The table name
  # @param column_names [Array<Symbol>, Symbol] The column name(s)
  # @return [Boolean]
  def index_exists?(table_name, column_names)
    ActiveRecord::Base.connection.index_exists?(table_name, column_names)
  end

  # Get column type for a column
  #
  # @param column_name [String, Symbol] The column name
  # @param table_name [String, Symbol] The table name
  # @return [Symbol, nil]
  def column_type(column_name, table_name = :ruby_llm_agents_executions)
    column = ActiveRecord::Base.connection.columns(table_name).find { |c| c.name == column_name.to_s }
    column&.type
  end

  # Get all column names for a table
  #
  # @param table_name [String, Symbol] The table name
  # @return [Array<String>]
  def column_names(table_name = :ruby_llm_agents_executions)
    ActiveRecord::Base.connection.columns(table_name).map(&:name)
  end

  # Verify data integrity after migration
  #
  # @param original_records [Array<Hash>] Original records before migration
  # @param table_name [String, Symbol] The table name
  # @return [Boolean]
  def verify_data_integrity(original_records, table_name = :ruby_llm_agents_executions)
    connection = ActiveRecord::Base.connection

    original_records.each do |original|
      record = connection.select_one(
        "SELECT * FROM #{table_name} WHERE id = ?",
        "Data Integrity Check",
        [[nil, original[:id]]]
      )

      return false unless record

      # Check that all original values are preserved
      original.each do |key, value|
        next if key == :id
        next unless column_exists?(key, table_name)

        db_value = record[key.to_s]

        # Handle JSON comparison
        if value.is_a?(Hash) || value.is_a?(Array)
          db_value = JSON.parse(db_value) if db_value.is_a?(String)
          return false unless db_value == value
        else
          return false unless db_value == value
        end
      end
    end

    true
  end

  # Count records in a table
  #
  # @param table_name [String, Symbol] The table name
  # @return [Integer]
  def record_count(table_name = :ruby_llm_agents_executions)
    ActiveRecord::Base.connection.select_value("SELECT COUNT(*) FROM #{table_name}").to_i
  end

  # Get all records from a table
  #
  # @param table_name [String, Symbol] The table name
  # @return [Array<Hash>]
  def all_records(table_name = :ruby_llm_agents_executions)
    ActiveRecord::Base.connection.select_all("SELECT * FROM #{table_name}").to_a
  end

  # Check if foreign key exists
  #
  # @param from_table [String, Symbol] The table with the foreign key
  # @param to_table [String, Symbol] The referenced table
  # @return [Boolean]
  def foreign_key_exists?(from_table, to_table)
    ActiveRecord::Base.connection.foreign_keys(from_table).any? do |fk|
      fk.to_table == to_table.to_s
    end
  end

  # Get default value for a column
  #
  # @param column_name [String, Symbol] The column name
  # @param table_name [String, Symbol] The table name
  # @return [Object, nil]
  def column_default(column_name, table_name = :ruby_llm_agents_executions)
    column = ActiveRecord::Base.connection.columns(table_name).find { |c| c.name == column_name.to_s }
    column&.default
  end

  # Check if column is nullable
  #
  # @param column_name [String, Symbol] The column name
  # @param table_name [String, Symbol] The table name
  # @return [Boolean]
  def column_nullable?(column_name, table_name = :ruby_llm_agents_executions)
    column = ActiveRecord::Base.connection.columns(table_name).find { |c| c.name == column_name.to_s }
    column&.null
  end
end

RSpec.configure do |config|
  config.include MigrationHelpers, type: :migration
end
