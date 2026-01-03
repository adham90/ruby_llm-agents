# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Execution tenant scopes" do
  # Skip if tenant_id column doesn't exist
  before(:all) do
    unless RubyLLM::Agents::Execution.column_names.include?("tenant_id")
      skip "tenant_id column not available - run multi-tenancy migration first"
    end
  end

  before do
    RubyLLM::Agents.reset_configuration!
  end

  let!(:tenant_1_execution) do
    RubyLLM::Agents::Execution.create!(
      agent_type: "TestAgent",
      model_id: "gpt-4o",
      started_at: Time.current,
      status: "success",
      tenant_id: "tenant_1"
    )
  end

  let!(:tenant_2_execution) do
    RubyLLM::Agents::Execution.create!(
      agent_type: "TestAgent",
      model_id: "gpt-4o",
      started_at: Time.current,
      status: "success",
      tenant_id: "tenant_2"
    )
  end

  let!(:no_tenant_execution) do
    RubyLLM::Agents::Execution.create!(
      agent_type: "TestAgent",
      model_id: "gpt-4o",
      started_at: Time.current,
      status: "success",
      tenant_id: nil
    )
  end

  describe ".by_tenant" do
    it "filters to specific tenant" do
      result = RubyLLM::Agents::Execution.by_tenant("tenant_1")

      expect(result).to include(tenant_1_execution)
      expect(result).not_to include(tenant_2_execution)
      expect(result).not_to include(no_tenant_execution)
    end
  end

  describe ".with_tenant" do
    it "returns executions with tenant_id set" do
      result = RubyLLM::Agents::Execution.with_tenant

      expect(result).to include(tenant_1_execution)
      expect(result).to include(tenant_2_execution)
      expect(result).not_to include(no_tenant_execution)
    end
  end

  describe ".without_tenant" do
    it "returns executions without tenant_id" do
      result = RubyLLM::Agents::Execution.without_tenant

      expect(result).not_to include(tenant_1_execution)
      expect(result).not_to include(tenant_2_execution)
      expect(result).to include(no_tenant_execution)
    end
  end

  describe ".for_current_tenant" do
    context "when multi-tenancy is disabled" do
      before do
        RubyLLM::Agents.configure do |config|
          config.multi_tenancy_enabled = false
        end
      end

      it "returns all executions" do
        result = RubyLLM::Agents::Execution.for_current_tenant

        expect(result).to include(tenant_1_execution)
        expect(result).to include(tenant_2_execution)
        expect(result).to include(no_tenant_execution)
      end
    end

    context "when multi-tenancy is enabled" do
      before do
        RubyLLM::Agents.configure do |config|
          config.multi_tenancy_enabled = true
          config.tenant_resolver = -> { "tenant_1" }
        end
      end

      it "filters to current tenant" do
        result = RubyLLM::Agents::Execution.for_current_tenant

        expect(result).to include(tenant_1_execution)
        expect(result).not_to include(tenant_2_execution)
        expect(result).not_to include(no_tenant_execution)
      end

      it "returns all when resolver returns nil" do
        RubyLLM::Agents.configure do |config|
          config.multi_tenancy_enabled = true
          config.tenant_resolver = -> { nil }
        end

        result = RubyLLM::Agents::Execution.for_current_tenant

        expect(result).to include(tenant_1_execution)
        expect(result).to include(tenant_2_execution)
        expect(result).to include(no_tenant_execution)
      end
    end
  end

  describe "scope chaining" do
    it "can chain tenant scope with other scopes" do
      RubyLLM::Agents::Execution.create!(
        agent_type: "OtherAgent",
        model_id: "gpt-4o",
        started_at: Time.current,
        status: "error",
        tenant_id: "tenant_1"
      )

      result = RubyLLM::Agents::Execution
        .by_tenant("tenant_1")
        .by_agent("TestAgent")

      expect(result).to include(tenant_1_execution)
      expect(result.count).to eq(1)
    end
  end
end
