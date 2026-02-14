# frozen_string_literal: true

require "rails_helper"

RSpec.describe RubyLLM::Agents::Concerns::ImageOperationExecution do
  # Test class that includes the concern and exposes private methods
  let(:test_class) do
    Class.new do
      include RubyLLM::Agents::Concerns::ImageOperationExecution

      attr_accessor :options

      def self.name
        "TestImageOperation"
      end

      def self.model
        "dall-e-3"
      end

      def self.cache_enabled?
        true
      end

      def self.cache_ttl
        1.hour
      end

      def initialize(options = {})
        @options = options
        @tenant_id = nil
      end

      # Expose private methods for testing
      def test_resolve_tenant_context!
        resolve_tenant_context!
      end

      def test_check_budget!
        check_budget!
      end

      def test_cache_enabled?
        cache_enabled?
      end

      def test_cache_key
        cache_key
      end

      def test_check_cache(result_class)
        check_cache(result_class)
      end

      def test_write_cache(result)
        write_cache(result)
      end

      def test_execution_tracking_enabled?
        execution_tracking_enabled?
      end

      def test_record_execution(result)
        record_execution(result)
      end

      def test_record_failed_execution(error, started_at)
        record_failed_execution(error, started_at)
      end

      def test_budget_tracking_enabled?
        budget_tracking_enabled?
      end

      def test_resolve_model
        resolve_model
      end

      def get_tenant_id
        @tenant_id
      end

      # Required method implementations
      def execution_type
        "test_image_operation"
      end

      def cache_key_components
        ["test", "operation", "v1", Digest::SHA256.hexdigest("test")]
      end

      def build_metadata(_result)
        { test: true }
      end
    end
  end

  let(:test_instance) { test_class.new }

  before do
    RubyLLM::Agents.reset_configuration!
    RubyLLM::Agents.configure do |config|
      config.track_image_generation = true
      config.async_logging = false
    end
  end

  describe "#resolve_tenant_context!" do
    it "does nothing when no tenant in options" do
      instance = test_class.new({})
      instance.test_resolve_tenant_context!

      expect(instance.get_tenant_id).to be_nil
    end

    it "extracts tenant id from hash with :id key" do
      instance = test_class.new(tenant: { id: "tenant-abc" })
      instance.test_resolve_tenant_context!

      expect(instance.get_tenant_id).to eq("tenant-abc")
    end

    it "extracts tenant id when tenant is an integer" do
      instance = test_class.new(tenant: 123)
      instance.test_resolve_tenant_context!

      expect(instance.get_tenant_id).to eq(123)
    end

    it "extracts tenant id when tenant is a string" do
      instance = test_class.new(tenant: "tenant-xyz")
      instance.test_resolve_tenant_context!

      expect(instance.get_tenant_id).to eq("tenant-xyz")
    end

    it "extracts tenant id from object with llm_tenant_id method" do
      tenant_obj = double("Tenant", llm_tenant_id: "llm-tenant-123")
      allow(tenant_obj).to receive(:try).with(:llm_tenant_id).and_return("llm-tenant-123")
      allow(tenant_obj).to receive(:try).with(:id).and_return("other-id")

      instance = test_class.new(tenant: tenant_obj)
      instance.test_resolve_tenant_context!

      expect(instance.get_tenant_id).to eq("llm-tenant-123")
    end

    it "extracts tenant id from object with id method" do
      tenant_obj = double("Tenant")
      allow(tenant_obj).to receive(:try).with(:llm_tenant_id).and_return(nil)
      allow(tenant_obj).to receive(:try).with(:id).and_return("tenant-id")

      instance = test_class.new(tenant: tenant_obj)
      instance.test_resolve_tenant_context!

      expect(instance.get_tenant_id).to eq("tenant-id")
    end
  end

  describe "#check_budget!" do
    before do
      allow(RubyLLM::Agents::BudgetTracker).to receive(:check_budget!)
    end

    it "calls BudgetTracker.check_budget! with agent info" do
      instance = test_class.new(tenant: "tenant-123")
      instance.test_resolve_tenant_context!
      instance.test_check_budget!

      expect(RubyLLM::Agents::BudgetTracker).to have_received(:check_budget!).with(
        "TestImageOperation",
        tenant_id: "tenant-123"
      )
    end
  end

  describe "#execution_type" do
    context "when not implemented in subclass" do
      let(:bare_test_class) do
        Class.new do
          include RubyLLM::Agents::Concerns::ImageOperationExecution

          def test_execution_type
            execution_type
          end
        end
      end

      it "raises NotImplementedError" do
        expect {
          bare_test_class.new.test_execution_type
        }.to raise_error(NotImplementedError, /Subclasses must implement/)
      end
    end
  end

  describe "#cache_enabled?" do
    it "returns true when class cache is enabled and skip_cache is false" do
      instance = test_class.new(skip_cache: false)
      expect(instance.test_cache_enabled?).to be true
    end

    it "returns false when skip_cache option is true" do
      instance = test_class.new(skip_cache: true)
      expect(instance.test_cache_enabled?).to be false
    end
  end

  describe "#cache_key_components" do
    context "when not implemented in subclass" do
      let(:bare_test_class) do
        Class.new do
          include RubyLLM::Agents::Concerns::ImageOperationExecution

          def test_cache_key_components
            cache_key_components
          end
        end
      end

      it "raises NotImplementedError" do
        expect {
          bare_test_class.new.test_cache_key_components
        }.to raise_error(NotImplementedError, /Subclasses must implement/)
      end
    end
  end

  describe "#cache_key" do
    it "joins cache key components with colons" do
      expect(test_instance.test_cache_key).to start_with("ruby_llm_agents:")
      expect(test_instance.test_cache_key).to include("test:operation:v1:")
    end
  end

  describe "#check_cache" do
    let(:mock_result_class) do
      Class.new do
        def self.from_cache(data)
          new(data)
        end

        attr_reader :data

        def initialize(data)
          @data = data
        end
      end
    end

    context "when Rails.cache is available" do
      before do
        allow(Rails).to receive(:cache).and_return(ActiveSupport::Cache::MemoryStore.new)
      end

      it "returns nil when cache miss" do
        result = test_instance.test_check_cache(mock_result_class)
        expect(result).to be_nil
      end

      it "returns cached result when cache hit" do
        cache_key = test_instance.test_cache_key
        Rails.cache.write(cache_key, { cached: true })

        result = test_instance.test_check_cache(mock_result_class)
        expect(result).to be_a(mock_result_class)
        expect(result.data).to eq({ cached: true })
      end
    end
  end

  describe "#write_cache" do
    let(:mock_result) do
      double("Result", success?: true, to_cache: { data: "cached" })
    end

    context "when Rails.cache is available" do
      let(:memory_store) { ActiveSupport::Cache::MemoryStore.new }

      before do
        allow(Rails).to receive(:cache).and_return(memory_store)
      end

      it "writes successful result to cache" do
        test_instance.test_write_cache(mock_result)

        cached = memory_store.read(test_instance.test_cache_key)
        expect(cached).to eq({ data: "cached" })
      end

      it "does not write failed result to cache" do
        failed_result = double("Result", success?: false, to_cache: { data: "cached" })

        test_instance.test_write_cache(failed_result)

        cached = memory_store.read(test_instance.test_cache_key)
        expect(cached).to be_nil
      end
    end
  end

  describe "#execution_tracking_enabled?" do
    it "returns true when track_image_generation is enabled" do
      RubyLLM::Agents.configure do |config|
        config.track_image_generation = true
      end

      expect(test_instance.test_execution_tracking_enabled?).to be true
    end

    it "returns false when track_image_generation is disabled" do
      RubyLLM::Agents.configure do |config|
        config.track_image_generation = false
      end

      expect(test_instance.test_execution_tracking_enabled?).to be false
    end
  end

  describe "#record_execution" do
    let(:mock_result) do
      double("Result",
        model_id: "dall-e-3",
        total_cost: 0.04,
        duration_ms: 1500,
        started_at: 2.seconds.ago,
        completed_at: Time.current,
        count: 1)
    end

    before do
      RubyLLM::Agents.configure do |config|
        config.async_logging = false
      end
    end

    it "creates execution record with correct data" do
      instance = test_class.new(tenant: "tenant-123")
      instance.test_resolve_tenant_context!

      # Stub to avoid schema mismatch issues with execution_type
      allow(RubyLLM::Agents::Execution).to receive(:create!).and_call_original

      expect(RubyLLM::Agents::Execution).to receive(:create!) do |data|
        expect(data[:agent_type]).to eq("TestImageOperation")
        expect(data[:status]).to eq("success")
        expect(data[:total_cost]).to eq(0.04)
        expect(data[:tenant_id]).to eq("tenant-123")
        expect(data[:execution_type]).to eq("test_image_operation")
      end

      instance.test_record_execution(mock_result)
    end

    it "uses async logging when configured" do
      RubyLLM::Agents.configure do |config|
        config.async_logging = true
      end

      expect(RubyLLM::Agents::ExecutionLoggerJob).to receive(:perform_later).with(
        hash_including(
          agent_type: "TestImageOperation",
          status: "success"
        )
      )

      test_instance.test_record_execution(mock_result)
    end

    it "handles errors gracefully" do
      allow(RubyLLM::Agents::Execution).to receive(:create!).and_raise(StandardError.new("DB error"))

      expect {
        test_instance.test_record_execution(mock_result)
      }.not_to raise_error
    end
  end

  describe "#record_failed_execution" do
    let(:error) { StandardError.new("Test error") }
    let(:started_at) { 2.seconds.ago }

    before do
      RubyLLM::Agents.configure do |config|
        config.async_logging = false
      end
    end

    it "creates execution record with error status" do
      expect(RubyLLM::Agents::Execution).to receive(:create!) do |data|
        expect(data[:status]).to eq("error")
        expect(data[:error_class]).to eq("StandardError")
        expect(data[:error_message]).to include("Test error")
      end

      test_instance.test_record_failed_execution(error, started_at)
    end

    it "calculates duration_ms" do
      expect(RubyLLM::Agents::Execution).to receive(:create!) do |data|
        expect(data[:duration_ms]).to be > 0
      end

      test_instance.test_record_failed_execution(error, started_at)
    end

    it "truncates long error messages" do
      long_error = StandardError.new("x" * 2000)

      expect(RubyLLM::Agents::Execution).to receive(:create!) do |data|
        expect(data[:error_message].length).to be <= 1000
      end

      test_instance.test_record_failed_execution(long_error, started_at)
    end
  end

  describe "#budget_tracking_enabled?" do
    it "returns falsey when budgets not configured" do
      RubyLLM::Agents.reset_configuration!
      expect(test_instance.test_budget_tracking_enabled?).to be_falsey
    end

    it "returns truthy when budgets are configured with enforcement" do
      RubyLLM::Agents.configure do |config|
        config.budgets = { enforcement: :soft, global_daily: 10.0 }
      end

      expect(test_instance.test_budget_tracking_enabled?).to be_truthy
    end

    it "returns falsey when enforcement is :none" do
      RubyLLM::Agents.configure do |config|
        config.budgets = { enforcement: :none, global_daily: 10.0 }
      end

      expect(test_instance.test_budget_tracking_enabled?).to be_falsey
    end
  end

  describe "#resolve_model" do
    it "returns model from options if provided" do
      instance = test_class.new(model: "custom-model")
      expect(instance.test_resolve_model).to eq("custom-model")
    end

    it "returns class model if no option provided" do
      expect(test_instance.test_resolve_model).to eq("dall-e-3")
    end

    it "resolves model aliases" do
      RubyLLM::Agents.configure do |config|
        config.image_model_aliases = { "dall-e-3": "dall-e-3-hd" }
      end

      expect(test_instance.test_resolve_model).to eq("dall-e-3-hd")
    end

    it "returns original model when no alias exists" do
      RubyLLM::Agents.configure do |config|
        config.image_model_aliases = { other: "other-hd" }
      end

      expect(test_instance.test_resolve_model).to eq("dall-e-3")
    end
  end
end
