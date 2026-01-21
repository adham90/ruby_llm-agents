# frozen_string_literal: true

require "rails_helper"

RSpec.describe RubyLLM::Agents::Budget::Forecaster do
  include ActiveSupport::Testing::TimeHelpers

  let(:cache_store) { ActiveSupport::Cache::MemoryStore.new }

  before do
    RubyLLM::Agents.reset_configuration!
    RubyLLM::Agents.configure do |c|
      c.cache_store = cache_store
    end
  end

  after do
    cache_store.clear
    travel_back
  end

  describe ".calculate_forecast" do
    let(:budget_config) do
      {
        enabled: true,
        global_daily: 100.0,
        global_monthly: 1000.0
      }
    end

    context "when budgets are disabled" do
      it "returns nil" do
        disabled_config = budget_config.merge(enabled: false)

        result = described_class.calculate_forecast(tenant_id: nil, budget_config: disabled_config)

        expect(result).to be_nil
      end
    end

    context "when no budget limits are configured" do
      it "returns nil" do
        no_limits_config = {
          enabled: true,
          global_daily: nil,
          global_monthly: nil
        }

        result = described_class.calculate_forecast(tenant_id: nil, budget_config: no_limits_config)

        expect(result).to be_nil
      end
    end

    context "with daily budget configured" do
      let(:daily_only_config) do
        {
          enabled: true,
          global_daily: 100.0,
          global_monthly: nil
        }
      end

      it "includes daily forecast" do
        # Record some spend
        RubyLLM::Agents::Budget::SpendRecorder.increment_spend(:global, :daily, 10.0, tenant_id: nil)

        result = described_class.calculate_forecast(tenant_id: nil, budget_config: daily_only_config)

        expect(result).to have_key(:daily)
        expect(result[:daily][:current]).to eq(10.0)
        expect(result[:daily][:limit]).to eq(100.0)
        expect(result[:daily]).to have_key(:projected)
        expect(result[:daily]).to have_key(:on_track)
        expect(result[:daily]).to have_key(:hours_remaining)
        expect(result[:daily]).to have_key(:rate_per_hour)
      end

      it "calculates rate based on hours elapsed" do
        # Travel to noon to make math predictable
        travel_to Time.zone.now.beginning_of_day + 12.hours do
          cache_store.clear # Clear cache after time travel
          RubyLLM::Agents::Budget::SpendRecorder.increment_spend(:global, :daily, 12.0, tenant_id: nil)

          result = described_class.calculate_forecast(tenant_id: nil, budget_config: daily_only_config)

          # At noon, rate should be 12/12 = 1.0 per hour
          expect(result[:daily][:rate_per_hour]).to be_within(0.01).of(1.0)
          # Projected for 24 hours should be ~24.0
          expect(result[:daily][:projected]).to be_within(0.1).of(24.0)
          expect(result[:daily][:on_track]).to be true
        end
      end

      it "determines if on track correctly" do
        travel_to Time.zone.now.beginning_of_day + 12.hours do
          cache_store.clear # Clear cache after time travel
          # At noon, spending 60 would project to 120 (over budget)
          RubyLLM::Agents::Budget::SpendRecorder.increment_spend(:global, :daily, 60.0, tenant_id: nil)

          result = described_class.calculate_forecast(tenant_id: nil, budget_config: daily_only_config)

          expect(result[:daily][:projected]).to be_within(0.1).of(120.0)
          expect(result[:daily][:on_track]).to be false
        end
      end
    end

    context "with monthly budget configured" do
      let(:monthly_only_config) do
        {
          enabled: true,
          global_daily: nil,
          global_monthly: 1000.0
        }
      end

      it "includes monthly forecast" do
        RubyLLM::Agents::Budget::SpendRecorder.increment_spend(:global, :monthly, 100.0, tenant_id: nil)

        result = described_class.calculate_forecast(tenant_id: nil, budget_config: monthly_only_config)

        expect(result).to have_key(:monthly)
        expect(result[:monthly][:current]).to eq(100.0)
        expect(result[:monthly][:limit]).to eq(1000.0)
        expect(result[:monthly]).to have_key(:projected)
        expect(result[:monthly]).to have_key(:on_track)
        expect(result[:monthly]).to have_key(:days_remaining)
        expect(result[:monthly]).to have_key(:rate_per_day)
      end

      it "calculates days remaining correctly" do
        travel_to Time.zone.local(2024, 1, 15, 12, 0, 0) do
          cache_store.clear # Clear cache after time travel
          RubyLLM::Agents::Budget::SpendRecorder.increment_spend(:global, :monthly, 100.0, tenant_id: nil)

          result = described_class.calculate_forecast(tenant_id: nil, budget_config: monthly_only_config)

          # January has 31 days, on the 15th there are 16 days remaining
          expect(result[:monthly][:days_remaining]).to eq(16)
        end
      end
    end

    context "with both daily and monthly configured" do
      it "includes both forecasts" do
        RubyLLM::Agents::Budget::SpendRecorder.increment_spend(:global, :daily, 10.0, tenant_id: nil)
        RubyLLM::Agents::Budget::SpendRecorder.increment_spend(:global, :monthly, 100.0, tenant_id: nil)

        result = described_class.calculate_forecast(tenant_id: nil, budget_config: budget_config)

        expect(result).to have_key(:daily)
        expect(result).to have_key(:monthly)
      end
    end

    context "with tenant-specific tracking" do
      it "calculates forecast for specific tenant" do
        RubyLLM::Agents::Budget::SpendRecorder.increment_spend(:global, :daily, 10.0, tenant_id: "org_123")
        RubyLLM::Agents::Budget::SpendRecorder.increment_spend(:global, :daily, 20.0, tenant_id: "org_456")

        result_123 = described_class.calculate_forecast(tenant_id: "org_123", budget_config: budget_config)
        result_456 = described_class.calculate_forecast(tenant_id: "org_456", budget_config: budget_config)

        expect(result_123[:daily][:current]).to eq(10.0)
        expect(result_456[:daily][:current]).to eq(20.0)
      end
    end

    context "edge cases" do
      it "handles zero spend gracefully" do
        result = described_class.calculate_forecast(tenant_id: nil, budget_config: budget_config)

        expect(result[:daily][:current]).to eq(0.0)
        expect(result[:daily][:projected]).to eq(0.0)
        expect(result[:daily][:on_track]).to be true
      end

      it "handles midnight (start of day) gracefully" do
        travel_to Time.zone.now.beginning_of_day + 1.second do
          cache_store.clear # Clear cache after time travel
          RubyLLM::Agents::Budget::SpendRecorder.increment_spend(:global, :daily, 5.0, tenant_id: nil)

          # Should not divide by zero (uses max of 1 hour)
          result = described_class.calculate_forecast(tenant_id: nil, budget_config: budget_config)

          expect(result[:daily]).to be_present
          expect(result[:daily][:projected]).to be_a(Numeric)
        end
      end

      it "handles first day of month gracefully" do
        travel_to Time.zone.local(2024, 1, 1, 12, 0, 0) do
          cache_store.clear # Clear cache after time travel
          RubyLLM::Agents::Budget::SpendRecorder.increment_spend(:global, :monthly, 50.0, tenant_id: nil)

          # Should not divide by zero (uses max of 1 day)
          result = described_class.calculate_forecast(tenant_id: nil, budget_config: budget_config)

          expect(result[:monthly]).to be_present
          expect(result[:monthly][:projected]).to be_a(Numeric)
        end
      end
    end
  end
end
