# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Cache AS::Notifications" do
  let(:agent_class) do
    Class.new do
      def self.name
        "CacheTestAgent"
      end

      def self.agent_type
        :conversation
      end

      def self.model
        "gpt-4o-mini"
      end

      def self.cache_enabled?
        true
      end

      def self.cache_ttl
        3600
      end
    end
  end

  let(:cache_store) { ActiveSupport::Cache::MemoryStore.new }

  before do
    RubyLLM::Agents.reset_configuration!
    RubyLLM::Agents.configure do |c|
      c.cache_store = cache_store
    end
  end

  after do
    RubyLLM::Agents.reset_configuration!
  end

  def build_context(**overrides)
    RubyLLM::Agents::Pipeline::Context.new(
      input: "test input",
      agent_class: agent_class,
      **overrides
    )
  end

  def build_cache_middleware(app_lambda)
    RubyLLM::Agents::Pipeline::Middleware::Cache.new(app_lambda, agent_class)
  end

  def collect_events(event_name)
    events = []
    sub = ActiveSupport::Notifications.subscribe(event_name) do |*args|
      events << ActiveSupport::Notifications::Event.new(*args)
    end
    yield
    events
  ensure
    ActiveSupport::Notifications.unsubscribe(sub)
  end

  describe "cache.hit event" do
    it "emits ruby_llm_agents.cache.hit on cache hit" do
      # Pre-populate cache by running once
      app = ->(ctx) {
        ctx.output = RubyLLM::Agents::Result.new(content: "cached value")
        ctx
      }
      middleware = build_cache_middleware(app)
      middleware.call(build_context)

      # Second call should hit cache
      events = collect_events("ruby_llm_agents.cache.hit") do
        middleware.call(build_context)
      end

      expect(events.length).to eq(1)
      payload = events.first.payload
      expect(payload[:agent_type]).to eq("CacheTestAgent")
      expect(payload[:cache_key]).to be_a(String)
      expect(payload[:cache_key]).to include("CacheTestAgent")
    end
  end

  describe "cache.miss event" do
    it "emits ruby_llm_agents.cache.miss on cache miss" do
      app = ->(ctx) {
        ctx.output = RubyLLM::Agents::Result.new(content: "fresh value")
        ctx
      }
      middleware = build_cache_middleware(app)

      events = collect_events("ruby_llm_agents.cache.miss") do
        middleware.call(build_context)
      end

      expect(events.length).to eq(1)
      payload = events.first.payload
      expect(payload[:agent_type]).to eq("CacheTestAgent")
      expect(payload[:cache_key]).to be_a(String)
    end
  end

  describe "cache.write event" do
    it "emits ruby_llm_agents.cache.write after writing to cache" do
      app = ->(ctx) {
        ctx.output = RubyLLM::Agents::Result.new(content: "new value")
        ctx
      }
      middleware = build_cache_middleware(app)

      events = collect_events("ruby_llm_agents.cache.write") do
        middleware.call(build_context)
      end

      expect(events.length).to eq(1)
      payload = events.first.payload
      expect(payload[:agent_type]).to eq("CacheTestAgent")
      expect(payload[:cache_key]).to be_a(String)
    end

    it "does not emit cache.write when execution fails" do
      app = ->(ctx) {
        ctx.error = StandardError.new("fail")
        ctx
      }
      middleware = build_cache_middleware(app)

      events = collect_events("ruby_llm_agents.cache.write") do
        middleware.call(build_context)
      end

      expect(events).to be_empty
    end
  end

  describe "event flow" do
    it "emits miss then write on first call, hit on second call" do
      app = ->(ctx) {
        ctx.output = RubyLLM::Agents::Result.new(content: "result")
        ctx
      }
      middleware = build_cache_middleware(app)

      all_events = []
      subs = %w[
        ruby_llm_agents.cache.miss
        ruby_llm_agents.cache.write
        ruby_llm_agents.cache.hit
      ].map do |event_name|
        ActiveSupport::Notifications.subscribe(event_name) do |*args|
          all_events << ActiveSupport::Notifications::Event.new(*args)
        end
      end

      # First call: miss + write
      middleware.call(build_context)
      expect(all_events.map(&:name)).to eq(%w[
        ruby_llm_agents.cache.miss
        ruby_llm_agents.cache.write
      ])

      all_events.clear

      # Second call: hit (no miss, no write)
      middleware.call(build_context)
      expect(all_events.map(&:name)).to eq(%w[ruby_llm_agents.cache.hit])

      subs.each { |s| ActiveSupport::Notifications.unsubscribe(s) }
    end
  end

  describe "when caching is disabled" do
    let(:non_cached_agent_class) do
      Class.new do
        def self.name
          "NonCachedAgent"
        end

        def self.agent_type
          :conversation
        end

        def self.model
          "gpt-4o-mini"
        end

        def self.cache_enabled?
          false
        end
      end
    end

    it "does not emit any cache events" do
      app = ->(ctx) {
        ctx.output = RubyLLM::Agents::Result.new(content: "result")
        ctx
      }
      middleware = RubyLLM::Agents::Pipeline::Middleware::Cache.new(app, non_cached_agent_class)

      all_events = []
      sub = ActiveSupport::Notifications.subscribe(/ruby_llm_agents\.cache\./) do |*args|
        all_events << ActiveSupport::Notifications::Event.new(*args)
      end

      middleware.call(build_context)

      ActiveSupport::Notifications.unsubscribe(sub)
      expect(all_events).to be_empty
    end
  end
end
