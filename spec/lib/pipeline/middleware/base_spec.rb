# frozen_string_literal: true

require "rails_helper"

RSpec.describe RubyLLM::Agents::Pipeline::Middleware::Base do
  let(:agent_class) do
    Class.new do
      def self.name
        "TestAgent"
      end

      def self.cache_enabled?
        true
      end

      def self.some_config_value
        "configured_value"
      end
    end
  end

  let(:app) { double("app") }
  let(:middleware) { described_class.new(app, agent_class) }

  before do
    RubyLLM::Agents.reset_configuration!
  end

  after do
    RubyLLM::Agents.reset_configuration!
  end

  describe "#initialize" do
    it "sets the app and agent_class" do
      expect(middleware.instance_variable_get(:@app)).to eq(app)
      expect(middleware.instance_variable_get(:@agent_class)).to eq(agent_class)
    end
  end

  describe "#call" do
    it "raises NotImplementedError" do
      context = double("context")

      expect {
        middleware.call(context)
      }.to raise_error(NotImplementedError, /must implement #call/)
    end
  end

  describe "#config" do
    let(:test_middleware) do
      Class.new(described_class) do
        def test_config(method, default = nil)
          config(method, default)
        end
      end
    end

    let(:middleware_instance) { test_middleware.new(app, agent_class) }

    it "returns value from agent class DSL method" do
      result = middleware_instance.test_config(:some_config_value)
      expect(result).to eq("configured_value")
    end

    it "returns default when method does not exist" do
      result = middleware_instance.test_config(:nonexistent_method, "default")
      expect(result).to eq("default")
    end

    it "returns nil when method does not exist and no default" do
      result = middleware_instance.test_config(:nonexistent_method)
      expect(result).to be_nil
    end

    it "returns default when agent_class is nil" do
      middleware_without_agent = test_middleware.new(app, nil)
      result = middleware_without_agent.test_config(:some_config_value, "fallback")
      expect(result).to eq("fallback")
    end
  end

  describe "#enabled?" do
    let(:test_middleware) do
      Class.new(described_class) do
        def test_enabled?(method)
          enabled?(method)
        end
      end
    end

    let(:middleware_instance) { test_middleware.new(app, agent_class) }

    context "when method returns true" do
      let(:agent_class) do
        Class.new do
          def self.name
            "EnabledAgent"
          end

          def self.feature_enabled?
            true
          end
        end
      end

      it "returns true" do
        expect(middleware_instance.test_enabled?(:feature_enabled?)).to be true
      end
    end

    context "when method returns false" do
      let(:agent_class) do
        Class.new do
          def self.name
            "DisabledAgent"
          end

          def self.feature_enabled?
            false
          end
        end
      end

      it "returns false" do
        expect(middleware_instance.test_enabled?(:feature_enabled?)).to be false
      end
    end

    context "when method does not exist" do
      it "returns false" do
        expect(middleware_instance.test_enabled?(:nonexistent_method)).to be false
      end
    end
  end

  describe "#global_config" do
    let(:test_middleware) do
      Class.new(described_class) do
        def test_global_config
          global_config
        end
      end
    end

    it "returns the RubyLLM::Agents configuration" do
      middleware_instance = test_middleware.new(app, agent_class)
      expect(middleware_instance.test_global_config).to eq(RubyLLM::Agents.configuration)
    end
  end

  describe "#debug" do
    let(:test_middleware) do
      Class.new(described_class) do
        def test_debug(message)
          debug(message)
        end
      end
    end

    let(:middleware_instance) { test_middleware.new(app, agent_class) }

    context "when Rails.logger is available" do
      let(:logger) { instance_double(Logger) }

      before do
        stub_const("Rails", double(logger: logger))
      end

      it "logs a debug message" do
        expect(logger).to receive(:debug).with("[RubyLLM::Agents::Pipeline] Test message")
        middleware_instance.test_debug("Test message")
      end
    end

    context "when Rails is not defined" do
      before do
        hide_const("Rails")
      end

      it "does not raise an error" do
        expect { middleware_instance.test_debug("Test message") }.not_to raise_error
      end
    end
  end

  describe "#error" do
    let(:test_middleware) do
      Class.new(described_class) do
        def test_error(message)
          error(message)
        end
      end
    end

    let(:middleware_instance) { test_middleware.new(app, agent_class) }

    context "when Rails.logger is available" do
      let(:logger) { instance_double(Logger) }

      before do
        stub_const("Rails", double(logger: logger))
      end

      it "logs an error message" do
        expect(logger).to receive(:error).with("[RubyLLM::Agents::Pipeline] Error message")
        middleware_instance.test_error("Error message")
      end
    end

    context "when Rails is not defined" do
      before do
        hide_const("Rails")
      end

      it "does not raise an error" do
        expect { middleware_instance.test_error("Error message") }.not_to raise_error
      end
    end
  end

  describe "LOG_TAG constant" do
    it "is defined" do
      expect(described_class::LOG_TAG).to eq("[RubyLLM::Agents::Pipeline]")
    end
  end

  describe "#log_prefix" do
    let(:test_middleware) do
      Class.new(described_class) do
        def test_log_prefix(context = nil)
          log_prefix(context)
        end
      end
    end

    let(:middleware_instance) { test_middleware.new(app, agent_class) }

    it "returns LOG_TAG when context is nil" do
      expect(middleware_instance.test_log_prefix).to eq("[RubyLLM::Agents::Pipeline]")
    end

    it "includes agent class name when context has agent_class" do
      context = RubyLLM::Agents::Pipeline::Context.new(
        input: "test",
        agent_class: agent_class
      )

      prefix = middleware_instance.test_log_prefix(context)
      expect(prefix).to include("TestAgent")
    end

    it "includes execution_id when set on context" do
      context = RubyLLM::Agents::Pipeline::Context.new(
        input: "test",
        agent_class: agent_class
      )
      context.execution_id = 42

      prefix = middleware_instance.test_log_prefix(context)
      expect(prefix).to include("exec=42")
    end

    it "includes tenant_id when set on context" do
      context = RubyLLM::Agents::Pipeline::Context.new(
        input: "test",
        agent_class: agent_class
      )
      context.tenant_id = "tenant-abc"

      prefix = middleware_instance.test_log_prefix(context)
      expect(prefix).to include("tenant=tenant-abc")
    end

    it "includes all parts when all are present" do
      context = RubyLLM::Agents::Pipeline::Context.new(
        input: "test",
        agent_class: agent_class
      )
      context.execution_id = 99
      context.tenant_id = "t-1"

      prefix = middleware_instance.test_log_prefix(context)
      expect(prefix).to eq("[RubyLLM::Agents::Pipeline] TestAgent exec=99 tenant=t-1")
    end
  end

  describe "subclass implementation" do
    let(:custom_middleware) do
      Class.new(described_class) do
        def call(context)
          context.output = "processed by middleware"
          @app.call(context)
        end
      end
    end

    it "can extend base functionality" do
      context = RubyLLM::Agents::Pipeline::Context.new(
        input: "test",
        agent_class: agent_class
      )
      allow(app).to receive(:call) { |ctx| ctx }

      middleware_instance = custom_middleware.new(app, agent_class)
      middleware_instance.call(context)

      expect(context.output).to eq("processed by middleware")
      expect(app).to have_received(:call).with(context)
    end
  end
end
