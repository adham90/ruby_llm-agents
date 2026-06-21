# frozen_string_literal: true

require "rails_helper"

# Linked tenants resolve their display name LIVE from the host model, so a
# renamed Account is reflected immediately instead of showing the snapshot
# taken when the Tenant row was created. The stored name column is kept in sync
# (best-effort) so the dashboard's SQL search/sort by name keeps working.
RSpec.describe "Linked tenant live name resolution", type: :model do
  before(:all) do
    ActiveRecord::Base.connection.execute(<<-SQL)
      CREATE TABLE IF NOT EXISTS live_name_test_accounts (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name VARCHAR(255),
        slug VARCHAR(255),
        created_at DATETIME,
        updated_at DATETIME
      )
    SQL

    unless Object.const_defined?(:LiveNameTestAccount)
      klass = Class.new(ActiveRecord::Base) do
        self.table_name = "live_name_test_accounts"
        include RubyLLM::Agents::LLMTenant

        llm_tenant id: :slug, name: :name, budget: true, limits: {daily_cost: 10}
      end
      def klass.name = "LiveNameTestAccount"
      Object.const_set(:LiveNameTestAccount, klass)
    end
  end

  after(:all) do
    Object.send(:remove_const, :LiveNameTestAccount) if Object.const_defined?(:LiveNameTestAccount)
    ActiveRecord::Base.connection.execute("DROP TABLE IF EXISTS live_name_test_accounts")
  end

  let(:account) { LiveNameTestAccount.create!(name: "Acme Corp", slug: "acme") }
  let(:tenant) { account.llm_tenant_record }

  describe "LLMTenant#llm_tenant_name" do
    it "resolves the configured name method live" do
      expect(account.llm_tenant_name).to eq("Acme Corp")
      account.update!(name: "Acme Renamed")
      expect(account.llm_tenant_name).to eq("Acme Renamed")
    end
  end

  describe "Tenant#display_name for a linked tenant" do
    it "reflects a renamed account immediately (the staleness bug)" do
      expect(tenant.display_name).to eq("Acme Corp")

      account.update!(name: "Acme Renamed")

      expect(tenant.reload.display_name).to eq("Acme Renamed")
    end

    it "falls back to the stored name when the live record name is blank" do
      # A bulk/raw rename to blank that bypasses callbacks: display falls back
      # to the last-synced stored copy rather than going blank.
      account.update_column(:name, "")
      expect(tenant.reload.display_name).to eq("Acme Corp")
    end
  end

  describe "stored-name sync (keeps SQL search/sort working)" do
    it "updates the stored name column when the account name changes" do
      expect(tenant.read_attribute(:name)).to eq("Acme Corp")

      account.update!(name: "Acme Renamed")

      expect(tenant.reload.read_attribute(:name)).to eq("Acme Renamed")
    end
  end

  describe "unlinked (string-id) tenant" do
    it "uses the stored name column" do
      t = RubyLLM::Agents::Tenant.for!("standalone", name: "Standalone Co")
      expect(t.display_name).to eq("Standalone Co")
    end

    it "falls back to tenant_id when no name is stored" do
      t = RubyLLM::Agents::Tenant.for!("noname")
      expect(t.display_name).to eq("noname")
    end
  end

  describe "tenants index eager-loads tenant_record (no N+1)", type: :request do
    include RubyLLM::Agents::Engine.routes.url_helpers

    def tenant_record_query_count(&block)
      count = 0
      sub = ActiveSupport::Notifications.subscribe("sql.active_record") do |*args|
        count += 1 if args.last[:sql].match?(/FROM\s+["`]?live_name_test_accounts/i)
      end
      block.call
      count
    ensure
      ActiveSupport::Notifications.unsubscribe(sub)
    end

    it "loads linked records in a constant number of queries regardless of row count" do
      LiveNameTestAccount.create!(name: "One", slug: "one")
      one = tenant_record_query_count { get tenants_path }
      expect(response).to have_http_status(:ok)

      3.times { |i| LiveNameTestAccount.create!(name: "Acct #{i}", slug: "acct-#{i}") }
      many = tenant_record_query_count { get tenants_path }
      expect(response).to have_http_status(:ok)

      # Preloaded => one batched SELECT for the polymorphic type, not one per row.
      expect(many).to eq(one)
    end
  end
end
