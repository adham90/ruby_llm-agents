# frozen_string_literal: true

require "spec_helper"

RSpec.describe RubyLLM::Agents::Tenant::Limitable do
  let(:tenant) { RubyLLM::Agents::Tenant.create!(tenant_id: "test_tenant_#{SecureRandom.hex(4)}") }

  after { tenant.destroy }

  describe "rate limiting" do
    describe "#rate_limited?" do
      it "returns false when no limits configured" do
        expect(tenant.rate_limited?).to be false
      end

      it "returns true when minute limit configured" do
        tenant.update!(rate_limit_per_minute: 60)
        expect(tenant.rate_limited?).to be true
      end

      it "returns true when hour limit configured" do
        tenant.update!(rate_limit_per_hour: 1000)
        expect(tenant.rate_limited?).to be true
      end
    end

    describe "#can_make_request?" do
      it "returns true when no limits configured" do
        expect(tenant.can_make_request?).to be true
      end

      context "with minute limit" do
        before { tenant.update!(rate_limit_per_minute: 5) }

        it "returns true when under limit" do
          expect(tenant.can_make_request?).to be true
        end

        it "returns false when at limit" do
          # Create 5 executions in the last minute
          5.times do
            RubyLLM::Agents::Execution.create!(
              agent_type: "TestAgent",
              model_id: "gpt-4o",
              started_at: Time.current,
              tenant_id: tenant.tenant_id
            )
          end

          expect(tenant.can_make_request?).to be false
        end
      end

      context "with hour limit" do
        before { tenant.update!(rate_limit_per_hour: 3) }

        it "returns true when under limit" do
          expect(tenant.can_make_request?).to be true
        end

        it "returns false when at limit" do
          # Create 3 executions in the last hour
          3.times do
            RubyLLM::Agents::Execution.create!(
              agent_type: "TestAgent",
              model_id: "gpt-4o",
              started_at: Time.current,
              tenant_id: tenant.tenant_id
            )
          end

          expect(tenant.can_make_request?).to be false
        end
      end
    end

    describe "#requests_this_minute" do
      it "returns 0 with no executions" do
        expect(tenant.requests_this_minute).to eq(0)
      end

      it "counts executions from last minute" do
        2.times do
          RubyLLM::Agents::Execution.create!(
            agent_type: "TestAgent",
            model_id: "gpt-4o",
            started_at: Time.current,
            tenant_id: tenant.tenant_id
          )
        end

        expect(tenant.requests_this_minute).to eq(2)
      end

      it "does not count old executions" do
        RubyLLM::Agents::Execution.create!(
          agent_type: "TestAgent",
          model_id: "gpt-4o",
          started_at: 2.minutes.ago,
          tenant_id: tenant.tenant_id,
          created_at: 2.minutes.ago
        )

        expect(tenant.requests_this_minute).to eq(0)
      end
    end

    describe "#requests_this_hour" do
      it "returns 0 with no executions" do
        expect(tenant.requests_this_hour).to eq(0)
      end

      it "counts executions from last hour" do
        3.times do
          RubyLLM::Agents::Execution.create!(
            agent_type: "TestAgent",
            model_id: "gpt-4o",
            started_at: Time.current,
            tenant_id: tenant.tenant_id
          )
        end

        expect(tenant.requests_this_hour).to eq(3)
      end
    end

    describe "#within_minute_limit?" do
      it "returns true when no limit" do
        expect(tenant.within_minute_limit?).to be true
      end

      it "returns true when under limit" do
        tenant.update!(rate_limit_per_minute: 10)
        expect(tenant.within_minute_limit?).to be true
      end
    end

    describe "#within_hour_limit?" do
      it "returns true when no limit" do
        expect(tenant.within_hour_limit?).to be true
      end

      it "returns true when under limit" do
        tenant.update!(rate_limit_per_hour: 100)
        expect(tenant.within_hour_limit?).to be true
      end
    end

    describe "#remaining_requests_this_minute" do
      it "returns nil when no limit" do
        expect(tenant.remaining_requests_this_minute).to be_nil
      end

      it "returns remaining count" do
        tenant.update!(rate_limit_per_minute: 10)
        expect(tenant.remaining_requests_this_minute).to eq(10)
      end

      it "returns 0 when at or over limit" do
        tenant.update!(rate_limit_per_minute: 1)
        RubyLLM::Agents::Execution.create!(
          agent_type: "TestAgent",
          model_id: "gpt-4o",
          started_at: Time.current,
          tenant_id: tenant.tenant_id
        )

        expect(tenant.remaining_requests_this_minute).to eq(0)
      end
    end

    describe "#remaining_requests_this_hour" do
      it "returns nil when no limit" do
        expect(tenant.remaining_requests_this_hour).to be_nil
      end

      it "returns remaining count" do
        tenant.update!(rate_limit_per_hour: 100)
        expect(tenant.remaining_requests_this_hour).to eq(100)
      end
    end
  end

  describe "feature flags" do
    describe "#feature_enabled?" do
      it "returns false for unset features" do
        expect(tenant.feature_enabled?(:streaming)).to be false
      end

      it "returns true for enabled features" do
        tenant.update!(feature_flags: { "streaming" => true })
        expect(tenant.feature_enabled?(:streaming)).to be true
      end

      it "returns false for explicitly disabled features" do
        tenant.update!(feature_flags: { "streaming" => false })
        expect(tenant.feature_enabled?(:streaming)).to be false
      end

      it "handles string keys" do
        tenant.update!(feature_flags: { "caching" => true })
        expect(tenant.feature_enabled?("caching")).to be true
      end
    end

    describe "#enable_feature!" do
      it "enables a feature" do
        tenant.enable_feature!(:streaming)
        expect(tenant.feature_enabled?(:streaming)).to be true
      end

      it "persists the change" do
        tenant.enable_feature!(:tools)
        tenant.reload
        expect(tenant.feature_enabled?(:tools)).to be true
      end

      it "preserves other features" do
        tenant.update!(feature_flags: { "other" => true })
        tenant.enable_feature!(:new_feature)

        expect(tenant.feature_enabled?(:other)).to be true
        expect(tenant.feature_enabled?(:new_feature)).to be true
      end
    end

    describe "#disable_feature!" do
      it "disables a feature" do
        tenant.enable_feature!(:streaming)
        tenant.disable_feature!(:streaming)

        expect(tenant.feature_enabled?(:streaming)).to be false
      end

      it "persists the change" do
        tenant.enable_feature!(:caching)
        tenant.disable_feature!(:caching)
        tenant.reload

        expect(tenant.feature_enabled?(:caching)).to be false
      end
    end

    describe "#set_feature!" do
      it "can enable a feature" do
        tenant.set_feature!(:streaming, true)
        expect(tenant.feature_enabled?(:streaming)).to be true
      end

      it "can disable a feature" do
        tenant.set_feature!(:streaming, false)
        expect(tenant.feature_enabled?(:streaming)).to be false
      end
    end

    describe "#enabled_features" do
      it "returns empty array when no features" do
        expect(tenant.enabled_features).to eq([])
      end

      it "returns only enabled features" do
        tenant.update!(feature_flags: {
          "streaming" => true,
          "caching" => false,
          "tools" => true
        })

        expect(tenant.enabled_features).to contain_exactly("streaming", "tools")
      end
    end

    describe "#disabled_features" do
      it "returns empty array when no features" do
        expect(tenant.disabled_features).to eq([])
      end

      it "returns only disabled features" do
        tenant.update!(feature_flags: {
          "streaming" => true,
          "caching" => false,
          "debug" => false
        })

        expect(tenant.disabled_features).to contain_exactly("caching", "debug")
      end
    end
  end

  describe "model restrictions" do
    describe "#model_allowed?" do
      it "returns true when no restrictions" do
        expect(tenant.model_allowed?("gpt-4o")).to be true
      end

      it "returns false when model is blocked" do
        tenant.update!(blocked_models: ["gpt-3.5-turbo"])
        expect(tenant.model_allowed?("gpt-3.5-turbo")).to be false
      end

      it "returns true when model is in allowed list" do
        tenant.update!(allowed_models: ["gpt-4o", "claude-3-opus"])
        expect(tenant.model_allowed?("gpt-4o")).to be true
      end

      it "returns false when model is not in allowed list" do
        tenant.update!(allowed_models: ["gpt-4o"])
        expect(tenant.model_allowed?("gpt-3.5-turbo")).to be false
      end

      it "blocked takes precedence over allowed" do
        tenant.update!(
          allowed_models: ["gpt-4o"],
          blocked_models: ["gpt-4o"]
        )
        expect(tenant.model_allowed?("gpt-4o")).to be false
      end
    end

    describe "#model_blocked?" do
      it "returns false when no blocks" do
        expect(tenant.model_blocked?("gpt-4o")).to be false
      end

      it "returns true when model is blocked" do
        tenant.update!(blocked_models: ["gpt-3.5-turbo"])
        expect(tenant.model_blocked?("gpt-3.5-turbo")).to be true
      end
    end

    describe "#allow_model!" do
      it "adds model to allowed list" do
        tenant.allow_model!("gpt-4o")
        expect(tenant.allowed_models).to include("gpt-4o")
      end

      it "does not duplicate models" do
        tenant.allow_model!("gpt-4o")
        tenant.allow_model!("gpt-4o")
        expect(tenant.allowed_models.count("gpt-4o")).to eq(1)
      end

      it "removes model from blocked list" do
        tenant.update!(blocked_models: ["gpt-4o"])
        tenant.allow_model!("gpt-4o")

        expect(tenant.allowed_models).to include("gpt-4o")
        expect(tenant.blocked_models).not_to include("gpt-4o")
      end

      it "persists the change" do
        tenant.allow_model!("gpt-4o")
        tenant.reload
        expect(tenant.allowed_models).to include("gpt-4o")
      end
    end

    describe "#disallow_model!" do
      it "removes model from allowed list" do
        tenant.update!(allowed_models: ["gpt-4o", "gpt-3.5"])
        tenant.disallow_model!("gpt-4o")

        expect(tenant.allowed_models).not_to include("gpt-4o")
        expect(tenant.allowed_models).to include("gpt-3.5")
      end
    end

    describe "#block_model!" do
      it "adds model to blocked list" do
        tenant.block_model!("gpt-3.5-turbo")
        expect(tenant.blocked_models).to include("gpt-3.5-turbo")
      end

      it "does not duplicate models" do
        tenant.block_model!("gpt-3.5-turbo")
        tenant.block_model!("gpt-3.5-turbo")
        expect(tenant.blocked_models.count("gpt-3.5-turbo")).to eq(1)
      end

      it "removes model from allowed list" do
        tenant.update!(allowed_models: ["gpt-3.5-turbo"])
        tenant.block_model!("gpt-3.5-turbo")

        expect(tenant.blocked_models).to include("gpt-3.5-turbo")
        expect(tenant.allowed_models).not_to include("gpt-3.5-turbo")
      end

      it "persists the change" do
        tenant.block_model!("gpt-3.5-turbo")
        tenant.reload
        expect(tenant.blocked_models).to include("gpt-3.5-turbo")
      end
    end

    describe "#unblock_model!" do
      it "removes model from blocked list" do
        tenant.update!(blocked_models: ["gpt-3.5-turbo", "gpt-4"])
        tenant.unblock_model!("gpt-3.5-turbo")

        expect(tenant.blocked_models).not_to include("gpt-3.5-turbo")
        expect(tenant.blocked_models).to include("gpt-4")
      end
    end

    describe "#explicitly_allowed_models" do
      it "returns a copy of allowed models" do
        tenant.update!(allowed_models: ["gpt-4o"])
        models = tenant.explicitly_allowed_models

        expect(models).to eq(["gpt-4o"])
        # Ensure it's a copy
        models << "other"
        expect(tenant.allowed_models).not_to include("other")
      end
    end

    describe "#explicitly_blocked_models" do
      it "returns a copy of blocked models" do
        tenant.update!(blocked_models: ["gpt-3.5"])
        models = tenant.explicitly_blocked_models

        expect(models).to eq(["gpt-3.5"])
        # Ensure it's a copy
        models << "other"
        expect(tenant.blocked_models).not_to include("other")
      end
    end

    describe "#has_model_restrictions?" do
      it "returns false when no restrictions" do
        expect(tenant.has_model_restrictions?).to be false
      end

      it "returns true when allowed models set" do
        tenant.update!(allowed_models: ["gpt-4o"])
        expect(tenant.has_model_restrictions?).to be true
      end

      it "returns true when blocked models set" do
        tenant.update!(blocked_models: ["gpt-3.5"])
        expect(tenant.has_model_restrictions?).to be true
      end
    end
  end
end
