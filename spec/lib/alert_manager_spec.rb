# frozen_string_literal: true

require "rails_helper"

RSpec.describe RubyLLM::Agents::AlertManager do
  before do
    RubyLLM::Agents.reset_configuration!
  end

  describe ".notify" do
    let(:event) { :budget_soft_cap }
    let(:payload) { { amount: 100, limit: 50 } }

    context "when on_alert is not configured" do
      it "does not raise an error" do
        expect { described_class.notify(event, payload) }.not_to raise_error
      end

      it "still emits ActiveSupport::Notification" do
        received_events = []
        ActiveSupport::Notifications.subscribe("ruby_llm_agents.alert.#{event}") do |_name, _start, _finish, _id, payload|
          received_events << payload
        end

        described_class.notify(event, payload)

        expect(received_events.length).to eq(1)
        expect(received_events[0][:amount]).to eq(100)
      ensure
        ActiveSupport::Notifications.unsubscribe("ruby_llm_agents.alert.#{event}")
      end
    end

    context "when on_alert is configured" do
      let(:received_events) { [] }

      before do
        events_array = received_events
        RubyLLM::Agents.configure do |config|
          config.on_alert = ->(event, payload) { events_array << [event, payload] }
        end
      end

      it "calls on_alert with event and payload" do
        described_class.notify(event, payload)

        expect(received_events.length).to eq(1)
        expect(received_events[0][0]).to eq(:budget_soft_cap)
        expect(received_events[0][1][:amount]).to eq(100)
      end

      it "includes event in payload" do
        described_class.notify(event, payload)

        expect(received_events[0][1][:event]).to eq(:budget_soft_cap)
      end

      it "includes timestamp in payload" do
        freeze_time = Time.current
        allow(Time).to receive(:current).and_return(freeze_time)

        described_class.notify(event, payload)

        expect(received_events[0][1][:timestamp]).to eq(freeze_time)
      end

      it "includes tenant_id in payload when multi-tenancy enabled" do
        RubyLLM::Agents.configure do |config|
          config.multi_tenancy_enabled = true
          config.tenant_resolver = -> { "tenant-123" }
          config.on_alert = ->(event, payload) { received_events << [event, payload] }
        end

        described_class.notify(event, payload)

        expect(received_events[0][1][:tenant_id]).to eq("tenant-123")
      end
    end

    context "ActiveSupport::Notifications" do
      it "emits notification with correct event name" do
        received_names = []
        ActiveSupport::Notifications.subscribe(/^ruby_llm_agents\.alert\./) do |name, _start, _finish, _id, _payload|
          received_names << name
        end

        described_class.notify(:breaker_open, { model: "gpt-4o" })

        expect(received_names).to include("ruby_llm_agents.alert.breaker_open")
      ensure
        ActiveSupport::Notifications.unsubscribe(/^ruby_llm_agents\.alert\./)
      end

      it "includes full payload in notification" do
        received_payloads = []
        ActiveSupport::Notifications.subscribe("ruby_llm_agents.alert.#{event}") do |_name, _start, _finish, _id, payload|
          received_payloads << payload
        end

        described_class.notify(event, payload)

        expect(received_payloads[0][:amount]).to eq(100)
        expect(received_payloads[0][:limit]).to eq(50)
        expect(received_payloads[0][:event]).to eq(:budget_soft_cap)
      ensure
        ActiveSupport::Notifications.unsubscribe("ruby_llm_agents.alert.#{event}")
      end
    end

    context "dashboard cache" do
      let(:cache) { ActiveSupport::Cache::MemoryStore.new }

      before do
        RubyLLM::Agents.configure do |config|
          config.cache_store = cache
        end
      end

      it "stores alert in cache for dashboard display" do
        described_class.notify(event, payload)

        cached_alerts = cache.read("ruby_llm_agents:alerts:recent")
        expect(cached_alerts).to be_an(Array)
        expect(cached_alerts.length).to eq(1)
        expect(cached_alerts[0][:type]).to eq(:budget_soft_cap)
      end

      it "includes formatted message in cached alert" do
        described_class.notify(:budget_soft_cap, { total_cost: 75.5, limit: 50.0 })

        cached_alerts = cache.read("ruby_llm_agents:alerts:recent")
        expect(cached_alerts[0][:message]).to include("$75.5")
        expect(cached_alerts[0][:message]).to include("$50.0")
      end

      it "prepends new alerts to the list" do
        described_class.notify(:budget_soft_cap, { amount: 1 })
        described_class.notify(:breaker_open, { agent_type: "TestAgent" })

        cached_alerts = cache.read("ruby_llm_agents:alerts:recent")
        expect(cached_alerts[0][:type]).to eq(:breaker_open)
        expect(cached_alerts[1][:type]).to eq(:budget_soft_cap)
      end

      it "limits cached alerts to 50" do
        55.times { |i| described_class.notify(:budget_soft_cap, { amount: i }) }

        cached_alerts = cache.read("ruby_llm_agents:alerts:recent")
        expect(cached_alerts.length).to eq(50)
      end
    end

    context "error handling" do
      it "logs errors from on_alert handler but does not raise" do
        RubyLLM::Agents.configure do |config|
          config.on_alert = ->(_event, _payload) { raise StandardError, "Handler error" }
        end

        expect(Rails.logger).to receive(:warn).with(/Handler failed/)
        expect { described_class.notify(event, payload) }.not_to raise_error
      end

      it "continues processing after handler error" do
        received_events = []
        ActiveSupport::Notifications.subscribe("ruby_llm_agents.alert.#{event}") do |_name, _start, _finish, _id, payload|
          received_events << payload
        end

        RubyLLM::Agents.configure do |config|
          config.on_alert = ->(_event, _payload) { raise StandardError, "Handler error" }
        end

        allow(Rails.logger).to receive(:warn)
        described_class.notify(event, payload)

        # AS::N should still be emitted even if handler fails
        expect(received_events.length).to eq(1)
      ensure
        ActiveSupport::Notifications.unsubscribe("ruby_llm_agents.alert.#{event}")
      end
    end

    context "message formatting" do
      it "formats budget_soft_cap message" do
        cache = ActiveSupport::Cache::MemoryStore.new
        RubyLLM::Agents.configure { |c| c.cache_store = cache }

        described_class.notify(:budget_soft_cap, { total_cost: 75.0, limit: 50.0 })

        cached = cache.read("ruby_llm_agents:alerts:recent")
        expect(cached[0][:message]).to eq("Budget soft cap reached: $75.0 / $50.0")
      end

      it "formats budget_hard_cap message" do
        cache = ActiveSupport::Cache::MemoryStore.new
        RubyLLM::Agents.configure { |c| c.cache_store = cache }

        described_class.notify(:budget_hard_cap, { total_cost: 110.0, limit: 100.0 })

        cached = cache.read("ruby_llm_agents:alerts:recent")
        expect(cached[0][:message]).to eq("Budget hard cap exceeded: $110.0 / $100.0")
      end

      it "formats breaker_open message" do
        cache = ActiveSupport::Cache::MemoryStore.new
        RubyLLM::Agents.configure { |c| c.cache_store = cache }

        described_class.notify(:breaker_open, { agent_type: "ContentAgent" })

        cached = cache.read("ruby_llm_agents:alerts:recent")
        expect(cached[0][:message]).to eq("Circuit breaker opened for ContentAgent")
      end

      it "formats breaker_closed message" do
        cache = ActiveSupport::Cache::MemoryStore.new
        RubyLLM::Agents.configure { |c| c.cache_store = cache }

        described_class.notify(:breaker_closed, { agent_type: "ContentAgent" })

        cached = cache.read("ruby_llm_agents:alerts:recent")
        expect(cached[0][:message]).to eq("Circuit breaker closed for ContentAgent")
      end

      it "formats agent_anomaly message" do
        cache = ActiveSupport::Cache::MemoryStore.new
        RubyLLM::Agents.configure { |c| c.cache_store = cache }

        described_class.notify(:agent_anomaly, { threshold_type: :cost })

        cached = cache.read("ruby_llm_agents:alerts:recent")
        expect(cached[0][:message]).to eq("Anomaly detected: cost threshold exceeded")
      end

      it "humanizes unknown event types" do
        cache = ActiveSupport::Cache::MemoryStore.new
        RubyLLM::Agents.configure { |c| c.cache_store = cache }

        described_class.notify(:custom_event, {})

        cached = cache.read("ruby_llm_agents:alerts:recent")
        expect(cached[0][:message]).to eq("Custom event")
      end
    end
  end
end
