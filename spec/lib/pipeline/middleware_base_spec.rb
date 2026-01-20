# frozen_string_literal: true

require "rails_helper"

RSpec.describe RubyLLM::Agents::Pipeline::Middleware::Base do
  # Mock agent class for testing
  let(:agent_class) do
    Class.new do
      def self.name
        "TestAgent"
      end

      def self.model
        "test-model"
      end

      def self.retries
        3
      end

      def self.cache_enabled?
        true
      end

      def self.cache_ttl
        1.hour
      end
    end
  end

  # Mock app (next handler in chain)
  let(:app) do
    ->(ctx) { ctx.output = "processed"; ctx }
  end

  # Simple test middleware that calls through
  let(:test_middleware_class) do
    Class.new(described_class) do
      def call(context)
        context[:before] = true
        result = @app.call(context)
        context[:after] = true
        result
      end
    end
  end

  describe "#initialize" do
    it "stores app and agent_class" do
      middleware = test_middleware_class.new(app, agent_class)

      # Access via instance_variable since these are stored internally
      expect(middleware.instance_variable_get(:@app)).to eq(app)
      expect(middleware.instance_variable_get(:@agent_class)).to eq(agent_class)
    end
  end

  describe "#call" do
    it "raises NotImplementedError on base class" do
      middleware = described_class.new(app, agent_class)
      context = RubyLLM::Agents::Pipeline::Context.new(
        input: "test",
        agent_class: agent_class
      )

      expect { middleware.call(context) }.to raise_error(NotImplementedError)
    end

    it "allows subclasses to implement call" do
      middleware = test_middleware_class.new(app, agent_class)
      context = RubyLLM::Agents::Pipeline::Context.new(
        input: "test",
        agent_class: agent_class
      )

      result = middleware.call(context)

      expect(result[:before]).to be true
      expect(result[:after]).to be true
      expect(result.output).to eq("processed")
    end
  end

  describe "#config" do
    let(:config_test_class) do
      Class.new(described_class) do
        def call(context)
          context[:model] = config(:model)
          context[:retries] = config(:retries)
          context[:missing] = config(:nonexistent, "default_value")
          context
        end
      end
    end

    it "reads configuration from agent class" do
      middleware = config_test_class.new(app, agent_class)
      context = RubyLLM::Agents::Pipeline::Context.new(
        input: "test",
        agent_class: agent_class
      )

      result = middleware.call(context)

      expect(result[:model]).to eq("test-model")
      expect(result[:retries]).to eq(3)
    end

    it "returns default when method not found" do
      middleware = config_test_class.new(app, agent_class)
      context = RubyLLM::Agents::Pipeline::Context.new(
        input: "test",
        agent_class: agent_class
      )

      result = middleware.call(context)

      expect(result[:missing]).to eq("default_value")
    end

    it "returns default when agent_class is nil" do
      middleware = config_test_class.new(app, nil)
      context = RubyLLM::Agents::Pipeline::Context.new(
        input: "test",
        agent_class: agent_class
      )

      result = middleware.call(context)

      expect(result[:model]).to be_nil
      expect(result[:missing]).to eq("default_value")
    end
  end

  describe "#enabled?" do
    let(:enabled_test_class) do
      Class.new(described_class) do
        def call(context)
          context[:cache_enabled] = enabled?(:cache_enabled?)
          context[:unknown_enabled] = enabled?(:unknown_feature?)
          context
        end
      end
    end

    it "returns true for enabled features" do
      middleware = enabled_test_class.new(app, agent_class)
      context = RubyLLM::Agents::Pipeline::Context.new(
        input: "test",
        agent_class: agent_class
      )

      result = middleware.call(context)

      expect(result[:cache_enabled]).to be true
    end

    it "returns false for unknown features" do
      middleware = enabled_test_class.new(app, agent_class)
      context = RubyLLM::Agents::Pipeline::Context.new(
        input: "test",
        agent_class: agent_class
      )

      result = middleware.call(context)

      expect(result[:unknown_enabled]).to be false
    end
  end

  describe "middleware chaining" do
    let(:first_middleware_class) do
      Class.new(described_class) do
        def call(context)
          context[:order] ||= []
          context[:order] << :first_before
          result = @app.call(context)
          context[:order] << :first_after
          result
        end
      end
    end

    let(:second_middleware_class) do
      Class.new(described_class) do
        def call(context)
          context[:order] ||= []
          context[:order] << :second_before
          result = @app.call(context)
          context[:order] << :second_after
          result
        end
      end
    end

    it "chains middleware in correct order" do
      core = ->(ctx) { ctx[:order] << :core; ctx }
      second = second_middleware_class.new(core, agent_class)
      first = first_middleware_class.new(second, agent_class)

      context = RubyLLM::Agents::Pipeline::Context.new(
        input: "test",
        agent_class: agent_class
      )

      first.call(context)

      expect(context[:order]).to eq([
                                      :first_before,
                                      :second_before,
                                      :core,
                                      :second_after,
                                      :first_after
                                    ])
    end
  end

  describe "error handling" do
    let(:error_handling_middleware_class) do
      Class.new(described_class) do
        def call(context)
          @app.call(context)
        rescue StandardError => e
          context.error = e
          context
        end
      end
    end

    it "allows middleware to catch errors" do
      failing_app = ->(_ctx) { raise "Something went wrong" }
      middleware = error_handling_middleware_class.new(failing_app, agent_class)

      context = RubyLLM::Agents::Pipeline::Context.new(
        input: "test",
        agent_class: agent_class
      )

      result = middleware.call(context)

      expect(result.error).to be_a(RuntimeError)
      expect(result.error.message).to eq("Something went wrong")
    end

    it "allows errors to propagate" do
      failing_app = ->(_ctx) { raise "Boom" }
      middleware = test_middleware_class.new(failing_app, agent_class)

      context = RubyLLM::Agents::Pipeline::Context.new(
        input: "test",
        agent_class: agent_class
      )

      expect { middleware.call(context) }.to raise_error(RuntimeError, "Boom")
    end
  end

  describe "short-circuiting" do
    let(:short_circuit_middleware_class) do
      Class.new(described_class) do
        def call(context)
          if context.input == "skip"
            context.output = "skipped"
            context.cached = true
            return context
          end
          @app.call(context)
        end
      end
    end

    it "allows middleware to short-circuit the chain" do
      core_called = false
      core = lambda do |ctx|
        core_called = true
        ctx.output = "from_core"
        ctx
      end

      middleware = short_circuit_middleware_class.new(core, agent_class)
      context = RubyLLM::Agents::Pipeline::Context.new(
        input: "skip",
        agent_class: agent_class
      )

      result = middleware.call(context)

      expect(core_called).to be false
      expect(result.output).to eq("skipped")
      expect(result.cached?).to be true
    end

    it "continues chain when not short-circuiting" do
      core = ->(ctx) { ctx.output = "from_core"; ctx }
      middleware = short_circuit_middleware_class.new(core, agent_class)

      context = RubyLLM::Agents::Pipeline::Context.new(
        input: "proceed",
        agent_class: agent_class
      )

      result = middleware.call(context)

      expect(result.output).to eq("from_core")
      expect(result.cached?).to be false
    end
  end
end
