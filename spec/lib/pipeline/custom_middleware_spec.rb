# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Custom Middleware Support" do
  # Real middleware classes — no mocks
  let(:tracking_middleware_a) do
    Class.new(RubyLLM::Agents::Pipeline::Middleware::Base) do
      def self.name
        "TrackingMiddlewareA"
      end

      def call(context)
        context[:order] ||= []
        context[:order] << :middleware_a
        @app.call(context)
      end
    end
  end

  let(:tracking_middleware_b) do
    Class.new(RubyLLM::Agents::Pipeline::Middleware::Base) do
      def self.name
        "TrackingMiddlewareB"
      end

      def call(context)
        context[:order] ||= []
        context[:order] << :middleware_b
        @app.call(context)
      end
    end
  end

  let(:tracking_middleware_c) do
    Class.new(RubyLLM::Agents::Pipeline::Middleware::Base) do
      def self.name
        "TrackingMiddlewareC"
      end

      def call(context)
        context[:order] ||= []
        context[:order] << :middleware_c
        @app.call(context)
      end
    end
  end

  let(:agent_class) do
    Class.new(RubyLLM::Agents::BaseAgent) do
      def self.name
        "CustomMiddlewareTestAgent"
      end

      model "gpt-4o"
      param :query, required: true

      def user_prompt
        query
      end
    end
  end

  before do
    RubyLLM::Agents.reset_configuration!
    RubyLLM::Agents.configure do |c|
      c.track_executions = false
      c.async_logging = false
    end
  end

  after do
    RubyLLM::Agents.reset_configuration!
  end

  # ─── Step 1: Configuration ─────────────────────────────────────────────

  describe "Global configuration" do
    it "starts with an empty middleware stack" do
      expect(RubyLLM::Agents.configuration.middleware_stack).to eq([])
    end

    it "registers middleware via use_middleware" do
      RubyLLM::Agents.configure do |c|
        c.use_middleware tracking_middleware_a
      end

      stack = RubyLLM::Agents.configuration.middleware_stack
      expect(stack.length).to eq(1)
      expect(stack.first[:klass]).to eq(tracking_middleware_a)
    end

    it "registers middleware with before: positioning" do
      RubyLLM::Agents.configure do |c|
        c.use_middleware tracking_middleware_a, before: RubyLLM::Agents::Pipeline::Middleware::Cache
      end

      entry = RubyLLM::Agents.configuration.middleware_stack.first
      expect(entry[:before]).to eq(RubyLLM::Agents::Pipeline::Middleware::Cache)
      expect(entry[:after]).to be_nil
    end

    it "registers middleware with after: positioning" do
      RubyLLM::Agents.configure do |c|
        c.use_middleware tracking_middleware_a, after: RubyLLM::Agents::Pipeline::Middleware::Tenant
      end

      entry = RubyLLM::Agents.configuration.middleware_stack.first
      expect(entry[:after]).to eq(RubyLLM::Agents::Pipeline::Middleware::Tenant)
      expect(entry[:before]).to be_nil
    end

    it "registers multiple middleware in order" do
      RubyLLM::Agents.configure do |c|
        c.use_middleware tracking_middleware_a
        c.use_middleware tracking_middleware_b
      end

      stack = RubyLLM::Agents.configuration.middleware_stack
      expect(stack.length).to eq(2)
      expect(stack.map { |e| e[:klass] }).to eq([tracking_middleware_a, tracking_middleware_b])
    end

    it "clears middleware with clear_middleware!" do
      RubyLLM::Agents.configure do |c|
        c.use_middleware tracking_middleware_a
      end

      RubyLLM::Agents.configuration.clear_middleware!
      expect(RubyLLM::Agents.configuration.middleware_stack).to eq([])
    end

    it "resets middleware on reset_configuration!" do
      RubyLLM::Agents.configure do |c|
        c.use_middleware tracking_middleware_a
      end

      RubyLLM::Agents.reset_configuration!
      expect(RubyLLM::Agents.configuration.middleware_stack).to eq([])
    end

    it "rejects classes that do not inherit from Middleware::Base" do
      expect {
        RubyLLM::Agents.configure do |c|
          c.use_middleware String
        end
      }.to raise_error(ArgumentError, /must inherit from/)
    end

    it "rejects non-class arguments" do
      expect {
        RubyLLM::Agents.configure do |c|
          c.use_middleware "not_a_class"
        end
      }.to raise_error(ArgumentError)
    end
  end

  # ─── Step 2: Per-Agent DSL ─────────────────────────────────────────────

  describe "Per-agent use_middleware DSL" do
    it "registers middleware on an agent class" do
      agent = Class.new(RubyLLM::Agents::BaseAgent) do
        def self.name
          "PerAgentMiddlewareTest"
        end

        model "gpt-4o"
        param :query, required: true
        use_middleware(Class.new(RubyLLM::Agents::Pipeline::Middleware::Base) {
          def self.name
            "InlineMiddleware"
          end

          def call(context)
            @app.call(context)
          end
        })

        def user_prompt
          query
        end
      end

      expect(agent.agent_middleware.length).to eq(1)
      expect(agent.agent_middleware.first[:klass].name).to eq("InlineMiddleware")
    end

    it "supports before: positioning" do
      mw = tracking_middleware_a
      agent = Class.new(RubyLLM::Agents::BaseAgent) do
        def self.name
          "BeforePositionTest"
        end

        model "gpt-4o"
        use_middleware mw, before: RubyLLM::Agents::Pipeline::Middleware::Instrumentation

        def user_prompt
          "test"
        end
      end

      entry = agent.agent_middleware.first
      expect(entry[:before]).to eq(RubyLLM::Agents::Pipeline::Middleware::Instrumentation)
    end

    it "supports after: positioning" do
      mw = tracking_middleware_a
      agent = Class.new(RubyLLM::Agents::BaseAgent) do
        def self.name
          "AfterPositionTest"
        end

        model "gpt-4o"
        use_middleware mw, after: RubyLLM::Agents::Pipeline::Middleware::Tenant

        def user_prompt
          "test"
        end
      end

      entry = agent.agent_middleware.first
      expect(entry[:after]).to eq(RubyLLM::Agents::Pipeline::Middleware::Tenant)
    end

    it "inherits middleware from superclass" do
      mw = tracking_middleware_a
      parent = Class.new(RubyLLM::Agents::BaseAgent) do
        def self.name
          "ParentAgent"
        end

        model "gpt-4o"
        use_middleware mw
      end

      child = Class.new(parent) do
        def self.name
          "ChildAgent"
        end
      end

      expect(child.agent_middleware.length).to eq(1)
      expect(child.agent_middleware.first[:klass]).to eq(mw)
    end

    it "returns empty array when no middleware is configured" do
      agent = Class.new(RubyLLM::Agents::BaseAgent) do
        def self.name
          "NoMiddlewareAgent"
        end

        model "gpt-4o"
      end

      expect(agent.agent_middleware).to eq([])
    end
  end

  # ─── Step 3: Builder integration ───────────────────────────────────────

  describe "Builder integration" do
    let(:core) do
      ->(ctx) {
        ctx[:order] ||= []
        ctx[:order] << :core
        ctx.output = RubyLLM::Agents::Result.new(content: "done")
        ctx
      }
    end

    def build_context(agent_klass)
      RubyLLM::Agents::Pipeline::Context.new(
        input: "test input",
        agent_class: agent_klass
      )
    end

    it "includes global middleware in the builder stack" do
      RubyLLM::Agents.configure do |c|
        c.use_middleware tracking_middleware_a
      end

      builder = RubyLLM::Agents::Pipeline::Builder.for(agent_class)
      expect(builder.to_a).to include(tracking_middleware_a)
    end

    it "includes per-agent middleware in the builder stack" do
      mw = tracking_middleware_a
      agent = Class.new(RubyLLM::Agents::BaseAgent) do
        def self.name
          "BuilderPerAgentTest"
        end

        model "gpt-4o"
        use_middleware mw

        def user_prompt
          "test"
        end
      end

      builder = RubyLLM::Agents::Pipeline::Builder.for(agent)
      expect(builder.to_a).to include(mw)
    end

    it "applies global middleware before per-agent middleware" do
      mw_global = tracking_middleware_a
      mw_agent = tracking_middleware_b

      RubyLLM::Agents.configure do |c|
        c.use_middleware mw_global
      end

      agent = Class.new(RubyLLM::Agents::BaseAgent) do
        def self.name
          "OrderTestAgent"
        end

        model "gpt-4o"
        use_middleware mw_agent

        def user_prompt
          "test"
        end
      end

      builder = RubyLLM::Agents::Pipeline::Builder.for(agent)
      stack = builder.to_a
      global_idx = stack.index(mw_global)
      agent_idx = stack.index(mw_agent)

      expect(global_idx).to be < agent_idx
    end

    it "respects before: positioning for global middleware" do
      RubyLLM::Agents.configure do |c|
        c.use_middleware tracking_middleware_a, before: RubyLLM::Agents::Pipeline::Middleware::Instrumentation
      end

      builder = RubyLLM::Agents::Pipeline::Builder.for(agent_class)
      stack = builder.to_a
      custom_idx = stack.index(tracking_middleware_a)
      instr_idx = stack.index(RubyLLM::Agents::Pipeline::Middleware::Instrumentation)

      expect(custom_idx).to be < instr_idx
    end

    it "respects after: positioning for global middleware" do
      RubyLLM::Agents.configure do |c|
        c.use_middleware tracking_middleware_a, after: RubyLLM::Agents::Pipeline::Middleware::Tenant
      end

      builder = RubyLLM::Agents::Pipeline::Builder.for(agent_class)
      stack = builder.to_a
      custom_idx = stack.index(tracking_middleware_a)
      tenant_idx = stack.index(RubyLLM::Agents::Pipeline::Middleware::Tenant)

      expect(custom_idx).to eq(tenant_idx + 1)
    end

    it "executes custom middleware in the correct pipeline order" do
      RubyLLM::Agents.configure do |c|
        c.use_middleware tracking_middleware_a
      end

      builder = RubyLLM::Agents::Pipeline::Builder.for(agent_class)
      pipeline = builder.build(core)
      context = build_context(agent_class)

      pipeline.call(context)

      expect(context[:order]).to include(:middleware_a)
      expect(context[:order].last).to eq(:core)
    end

    it "executes global then per-agent middleware then core" do
      mw_global = tracking_middleware_a
      mw_agent = tracking_middleware_b

      RubyLLM::Agents.configure do |c|
        c.use_middleware mw_global
      end

      agent = Class.new(RubyLLM::Agents::BaseAgent) do
        def self.name
          "FullPipelineTestAgent"
        end

        model "gpt-4o"
        use_middleware mw_agent

        def user_prompt
          "test"
        end
      end

      builder = RubyLLM::Agents::Pipeline::Builder.for(agent)
      pipeline = builder.build(core)
      context = build_context(agent)

      pipeline.call(context)

      order = context[:order]
      a_idx = order.index(:middleware_a)
      b_idx = order.index(:middleware_b)
      core_idx = order.index(:core)

      expect(a_idx).to be < b_idx
      expect(b_idx).to be < core_idx
    end

    it "does not affect agents without custom middleware" do
      builder = RubyLLM::Agents::Pipeline::Builder.for(agent_class)
      stack = builder.to_a

      expect(stack).to include(RubyLLM::Agents::Pipeline::Middleware::Tenant)
      expect(stack).to include(RubyLLM::Agents::Pipeline::Middleware::Instrumentation)
      expect(stack).not_to include(tracking_middleware_a)
    end
  end
end
