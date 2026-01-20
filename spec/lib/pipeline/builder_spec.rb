# frozen_string_literal: true

require "rails_helper"

RSpec.describe RubyLLM::Agents::Pipeline::Builder do
  # Mock middleware classes
  let(:middleware_a) do
    Class.new(RubyLLM::Agents::Pipeline::Middleware::Base) do
      def self.name
        "MiddlewareA"
      end

      def call(context)
        context[:order] ||= []
        context[:order] << :a
        @app.call(context)
      end
    end
  end

  let(:middleware_b) do
    Class.new(RubyLLM::Agents::Pipeline::Middleware::Base) do
      def self.name
        "MiddlewareB"
      end

      def call(context)
        context[:order] ||= []
        context[:order] << :b
        @app.call(context)
      end
    end
  end

  let(:middleware_c) do
    Class.new(RubyLLM::Agents::Pipeline::Middleware::Base) do
      def self.name
        "MiddlewareC"
      end

      def call(context)
        context[:order] ||= []
        context[:order] << :c
        @app.call(context)
      end
    end
  end

  # Mock agent class
  let(:agent_class) do
    Class.new do
      def self.name
        "TestAgent"
      end

      def self.agent_type
        :embedding
      end

      def self.model
        "test-model"
      end
    end
  end

  # Core executor
  let(:core) do
    ->(ctx) { ctx[:order] ||= []; ctx[:order] << :core; ctx.output = "done"; ctx }
  end

  describe "#initialize" do
    it "creates an empty builder" do
      builder = described_class.new(agent_class)

      expect(builder.agent_class).to eq(agent_class)
      expect(builder.stack).to be_empty
    end
  end

  describe "#use" do
    it "adds middleware to the stack" do
      builder = described_class.new(agent_class)
        .use(middleware_a)
        .use(middleware_b)

      expect(builder.stack).to eq([middleware_a, middleware_b])
    end

    it "returns self for chaining" do
      builder = described_class.new(agent_class)

      expect(builder.use(middleware_a)).to eq(builder)
    end
  end

  describe "#insert_before" do
    it "inserts middleware before existing middleware" do
      builder = described_class.new(agent_class)
        .use(middleware_a)
        .use(middleware_c)
        .insert_before(middleware_c, middleware_b)

      expect(builder.stack).to eq([middleware_a, middleware_b, middleware_c])
    end

    it "raises error if existing middleware not found" do
      builder = described_class.new(agent_class)
        .use(middleware_a)

      expect {
        builder.insert_before(middleware_c, middleware_b)
      }.to raise_error(ArgumentError, /not found/)
    end
  end

  describe "#insert_after" do
    it "inserts middleware after existing middleware" do
      builder = described_class.new(agent_class)
        .use(middleware_a)
        .use(middleware_c)
        .insert_after(middleware_a, middleware_b)

      expect(builder.stack).to eq([middleware_a, middleware_b, middleware_c])
    end

    it "raises error if existing middleware not found" do
      builder = described_class.new(agent_class)
        .use(middleware_a)

      expect {
        builder.insert_after(middleware_c, middleware_b)
      }.to raise_error(ArgumentError, /not found/)
    end
  end

  describe "#delete" do
    it "removes middleware from the stack" do
      builder = described_class.new(agent_class)
        .use(middleware_a)
        .use(middleware_b)
        .use(middleware_c)
        .delete(middleware_b)

      expect(builder.stack).to eq([middleware_a, middleware_c])
    end

    it "returns self for chaining" do
      builder = described_class.new(agent_class)
        .use(middleware_a)

      expect(builder.delete(middleware_a)).to eq(builder)
    end
  end

  describe "#build" do
    it "wraps core with middleware in correct order" do
      builder = described_class.new(agent_class)
        .use(middleware_a)
        .use(middleware_b)
        .use(middleware_c)

      pipeline = builder.build(core)
      context = RubyLLM::Agents::Pipeline::Context.new(
        input: "test",
        agent_class: agent_class
      )

      pipeline.call(context)

      # First middleware in stack should be outermost
      expect(context[:order]).to eq([:a, :b, :c, :core])
    end

    it "works with empty stack" do
      builder = described_class.new(agent_class)
      pipeline = builder.build(core)

      context = RubyLLM::Agents::Pipeline::Context.new(
        input: "test",
        agent_class: agent_class
      )

      pipeline.call(context)

      expect(context[:order]).to eq([:core])
      expect(context.output).to eq("done")
    end
  end

  describe "#include?" do
    it "returns true if middleware is in stack" do
      builder = described_class.new(agent_class)
        .use(middleware_a)

      expect(builder.include?(middleware_a)).to be true
    end

    it "returns false if middleware is not in stack" do
      builder = described_class.new(agent_class)
        .use(middleware_a)

      expect(builder.include?(middleware_b)).to be false
    end
  end

  describe "#to_a" do
    it "returns a copy of the stack" do
      builder = described_class.new(agent_class)
        .use(middleware_a)
        .use(middleware_b)

      array = builder.to_a

      expect(array).to eq([middleware_a, middleware_b])
      expect(array).not_to be(builder.stack)
    end
  end

  describe ".for" do
    context "with minimal agent" do
      let(:minimal_agent) do
        Class.new do
          def self.name
            "MinimalAgent"
          end
        end
      end

      it "always includes Tenant middleware" do
        # Allow Middleware classes to be available
        stub_const("RubyLLM::Agents::Pipeline::Middleware::Tenant",
                   Class.new(RubyLLM::Agents::Pipeline::Middleware::Base) do
                     def call(context)
                       @app.call(context)
                     end
                   end)
        stub_const("RubyLLM::Agents::Pipeline::Middleware::Instrumentation",
                   Class.new(RubyLLM::Agents::Pipeline::Middleware::Base) do
                     def call(context)
                       @app.call(context)
                     end
                   end)

        builder = described_class.for(minimal_agent)

        expect(builder.include?(RubyLLM::Agents::Pipeline::Middleware::Tenant)).to be true
        expect(builder.include?(RubyLLM::Agents::Pipeline::Middleware::Instrumentation)).to be true
      end
    end

    context "with caching enabled" do
      let(:cached_agent) do
        Class.new do
          def self.name
            "CachedAgent"
          end

          def self.cache_enabled?
            true
          end
        end
      end

      it "includes Cache middleware" do
        stub_const("RubyLLM::Agents::Pipeline::Middleware::Tenant",
                   Class.new(RubyLLM::Agents::Pipeline::Middleware::Base) do
                     def call(context)
                       @app.call(context)
                     end
                   end)
        stub_const("RubyLLM::Agents::Pipeline::Middleware::Cache",
                   Class.new(RubyLLM::Agents::Pipeline::Middleware::Base) do
                     def call(context)
                       @app.call(context)
                     end
                   end)
        stub_const("RubyLLM::Agents::Pipeline::Middleware::Instrumentation",
                   Class.new(RubyLLM::Agents::Pipeline::Middleware::Base) do
                     def call(context)
                       @app.call(context)
                     end
                   end)

        builder = described_class.for(cached_agent)

        expect(builder.include?(RubyLLM::Agents::Pipeline::Middleware::Cache)).to be true
      end
    end

    context "with reliability enabled" do
      let(:reliable_agent) do
        Class.new do
          def self.name
            "ReliableAgent"
          end

          def self.retries
            3
          end

          def self.fallback_models
            ["gpt-3.5-turbo"]
          end
        end
      end

      it "includes Reliability middleware when retries > 0" do
        stub_const("RubyLLM::Agents::Pipeline::Middleware::Tenant",
                   Class.new(RubyLLM::Agents::Pipeline::Middleware::Base) do
                     def call(context)
                       @app.call(context)
                     end
                   end)
        stub_const("RubyLLM::Agents::Pipeline::Middleware::Instrumentation",
                   Class.new(RubyLLM::Agents::Pipeline::Middleware::Base) do
                     def call(context)
                       @app.call(context)
                     end
                   end)
        stub_const("RubyLLM::Agents::Pipeline::Middleware::Reliability",
                   Class.new(RubyLLM::Agents::Pipeline::Middleware::Base) do
                     def call(context)
                       @app.call(context)
                     end
                   end)

        builder = described_class.for(reliable_agent)

        expect(builder.include?(RubyLLM::Agents::Pipeline::Middleware::Reliability)).to be true
      end

      it "includes Reliability middleware when fallback_models present" do
        fallback_only_agent = Class.new do
          def self.name
            "FallbackAgent"
          end

          def self.retries
            0
          end

          def self.fallback_models
            ["gpt-3.5-turbo"]
          end
        end

        stub_const("RubyLLM::Agents::Pipeline::Middleware::Tenant",
                   Class.new(RubyLLM::Agents::Pipeline::Middleware::Base) do
                     def call(context)
                       @app.call(context)
                     end
                   end)
        stub_const("RubyLLM::Agents::Pipeline::Middleware::Instrumentation",
                   Class.new(RubyLLM::Agents::Pipeline::Middleware::Base) do
                     def call(context)
                       @app.call(context)
                     end
                   end)
        stub_const("RubyLLM::Agents::Pipeline::Middleware::Reliability",
                   Class.new(RubyLLM::Agents::Pipeline::Middleware::Base) do
                     def call(context)
                       @app.call(context)
                     end
                   end)

        builder = described_class.for(fallback_only_agent)

        expect(builder.include?(RubyLLM::Agents::Pipeline::Middleware::Reliability)).to be true
      end
    end
  end

  describe ".empty" do
    it "returns a builder with no middleware" do
      builder = described_class.empty(agent_class)

      expect(builder.stack).to be_empty
      expect(builder.agent_class).to eq(agent_class)
    end
  end
end
