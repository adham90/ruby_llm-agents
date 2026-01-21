# frozen_string_literal: true

require "rails_helper"

RSpec.describe RubyLLM::Agents::Pipeline::Middleware::Instrumentation do
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

  let(:app) { double("app") }
  let(:middleware) { described_class.new(app, agent_class) }
  let(:config) { double("config") }

  def build_context(options = {})
    RubyLLM::Agents::Pipeline::Context.new(
      input: "test",
      agent_class: agent_class,
      **options
    )
  end

  before do
    allow(RubyLLM::Agents).to receive(:configuration).and_return(config)
    allow(config).to receive(:track_embeddings).and_return(true)
    allow(config).to receive(:track_executions).and_return(true)
    allow(config).to receive(:track_moderation).and_return(true)
    allow(config).to receive(:track_image_generation).and_return(true)
    allow(config).to receive(:track_audio).and_return(true)
    allow(config).to receive(:async_logging).and_return(false)
  end

  describe "#call" do
    it "sets started_at timestamp" do
      context = build_context
      allow(app).to receive(:call) { |ctx| ctx.output = "result"; ctx }
      allow(config).to receive(:track_embeddings).and_return(false)

      result = middleware.call(context)

      expect(result.started_at).to be_a(Time)
    end

    it "sets completed_at timestamp on success" do
      context = build_context
      allow(app).to receive(:call) { |ctx| ctx.output = "result"; ctx }
      allow(config).to receive(:track_embeddings).and_return(false)

      result = middleware.call(context)

      expect(result.completed_at).to be_a(Time)
      expect(result.completed_at).to be >= result.started_at
    end

    it "sets completed_at timestamp on failure" do
      context = build_context
      allow(app).to receive(:call).and_raise(StandardError, "Test error")
      allow(config).to receive(:track_embeddings).and_return(false)

      expect { middleware.call(context) }.to raise_error(StandardError)

      expect(context.completed_at).to be_a(Time)
    end

    it "re-raises errors from the execution" do
      context = build_context
      allow(app).to receive(:call).and_raise(StandardError, "Test error")
      allow(config).to receive(:track_embeddings).and_return(false)

      expect { middleware.call(context) }.to raise_error(StandardError, "Test error")
    end

    it "records the error on the context" do
      context = build_context
      error = StandardError.new("Test error")
      allow(app).to receive(:call).and_raise(error)
      allow(config).to receive(:track_embeddings).and_return(false)

      expect { middleware.call(context) }.to raise_error(StandardError)

      expect(context.error).to eq(error)
    end

    context "when tracking is enabled" do
      before do
        allow(config).to receive(:track_embeddings).and_return(true)
        allow(config).to receive(:multi_tenancy_enabled?).and_return(false)
        # Mock the Execution model
        stub_const("RubyLLM::Agents::Execution", Class.new)
      end

      it "records successful execution" do
        context = build_context
        context.input_tokens = 100
        context.output_tokens = 50
        context.total_cost = 0.001

        allow(app).to receive(:call) do |ctx|
          ctx.output = "result"
          ctx
        end

        expect(RubyLLM::Agents::Execution).to receive(:create!).with(
          hash_including(
            agent_type: "TestAgent",
            model_id: "test-model",
            status: "success"
          )
        )

        middleware.call(context)
      end

      it "records failed execution" do
        context = build_context
        error = StandardError.new("Execution failed")

        allow(app).to receive(:call).and_raise(error)

        expect(RubyLLM::Agents::Execution).to receive(:create!).with(
          hash_including(
            status: "error",
            error_class: "StandardError",
            error_message: "Execution failed"
          )
        )

        expect { middleware.call(context) }.to raise_error(StandardError)
      end

      it "truncates long error messages" do
        context = build_context
        long_message = "x" * 2000
        error = StandardError.new(long_message)

        allow(app).to receive(:call).and_raise(error)

        expect(RubyLLM::Agents::Execution).to receive(:create!).with(
          hash_including(
            error_message: a_string_matching(/\Ax{1,1000}/)
          )
        )

        expect { middleware.call(context) }.to raise_error(StandardError)
      end

      it "includes token usage in execution record" do
        context = build_context
        context.input_tokens = 500
        context.output_tokens = 200
        context.total_cost = 0.0035

        allow(app).to receive(:call) { |ctx| ctx.output = "result"; ctx }

        expect(RubyLLM::Agents::Execution).to receive(:create!).with(
          hash_including(
            input_tokens: 500,
            output_tokens: 200,
            total_cost: 0.0035
          )
        )

        middleware.call(context)
      end
    end

    context "when tracking is disabled" do
      before do
        allow(config).to receive(:track_embeddings).and_return(false)
        allow(config).to receive(:track_executions).and_return(false)
      end

      it "does not create execution records" do
        context = build_context

        allow(app).to receive(:call) { |ctx| ctx.output = "result"; ctx }

        # Should not call create! if tracking is disabled
        if defined?(RubyLLM::Agents::Execution)
          expect(RubyLLM::Agents::Execution).not_to receive(:create!)
        end

        middleware.call(context)
      end
    end

    context "when result is cached" do
      before do
        allow(config).to receive(:track_embeddings).and_return(true)
        allow(config).to receive(:respond_to?).with(:track_cache_hits).and_return(true)
        allow(config).to receive(:track_cache_hits).and_return(false)
        allow(config).to receive(:multi_tenancy_enabled?).and_return(false)
        stub_const("RubyLLM::Agents::Execution", Class.new)
      end

      it "does not record cache hits when track_cache_hits is false" do
        context = build_context
        context.cached = true

        allow(app).to receive(:call) { |ctx| ctx.output = "cached_result"; ctx }

        expect(RubyLLM::Agents::Execution).not_to receive(:create!)

        middleware.call(context)
      end

      it "records cache hits when track_cache_hits is true" do
        allow(config).to receive(:track_cache_hits).and_return(true)

        context = build_context
        context.cached = true

        allow(app).to receive(:call) { |ctx| ctx.output = "cached_result"; ctx }

        expect(RubyLLM::Agents::Execution).to receive(:create!).with(
          hash_including(cache_hit: true)
        )

        middleware.call(context)
      end
    end

    context "async logging" do
      before do
        allow(config).to receive(:track_embeddings).and_return(true)
        allow(config).to receive(:multi_tenancy_enabled?).and_return(false)
        stub_const("RubyLLM::Agents::Execution", Class.new)
      end

      it "uses async logging when enabled and ExecutionLoggerJob is defined" do
        allow(config).to receive(:async_logging).and_return(true)

        # Stub the ExecutionLoggerJob to be defined
        job_class = Class.new do
          def self.perform_later(data)
            # No-op for test
          end
        end
        stub_const("RubyLLM::Agents::Infrastructure::ExecutionLoggerJob", job_class)

        # Re-evaluate the middleware's async_logging? check
        # by allowing it to see the stubbed constant
        allow(middleware).to receive(:async_logging?).and_return(true)

        context = build_context
        context.input_tokens = 100
        context.output_tokens = 50

        allow(app).to receive(:call) do |ctx|
          ctx.output = "result"
          ctx
        end

        expect(RubyLLM::Agents::Infrastructure::ExecutionLoggerJob).to receive(:perform_later).with(
          hash_including(
            agent_type: "TestAgent",
            status: "success"
          )
        )

        middleware.call(context)
      end

      it "falls back to sync when async_logging is disabled" do
        allow(config).to receive(:async_logging).and_return(false)

        context = build_context
        context.input_tokens = 100
        context.output_tokens = 50

        allow(app).to receive(:call) do |ctx|
          ctx.output = "result"
          ctx
        end

        expect(RubyLLM::Agents::Execution).to receive(:create!).with(
          hash_including(
            agent_type: "TestAgent",
            status: "success"
          )
        )

        middleware.call(context)
      end

      it "falls back to sync when ExecutionLoggerJob is not defined" do
        allow(config).to receive(:async_logging).and_return(true)
        # Don't stub ExecutionLoggerJob - it should be undefined
        # The middleware checks defined?(ExecutionLoggerJob)

        context = build_context
        context.input_tokens = 100
        context.output_tokens = 50

        allow(app).to receive(:call) do |ctx|
          ctx.output = "result"
          ctx
        end

        # With async_logging true but no job defined, should fall back to sync
        # The actual middleware checks defined?(ExecutionLoggerJob) which will be false
        expect(RubyLLM::Agents::Execution).to receive(:create!).with(
          hash_including(
            agent_type: "TestAgent",
            status: "success"
          )
        )

        middleware.call(context)
      end
    end
  end

  describe "tracking per agent type" do
    let(:config) { double("config") }

    before do
      allow(RubyLLM::Agents).to receive(:configuration).and_return(config)
      allow(config).to receive(:async_logging).and_return(false)
      allow(config).to receive(:track_embeddings).and_return(true)
      allow(config).to receive(:track_executions).and_return(true)
      allow(config).to receive(:track_moderation).and_return(true)
      allow(config).to receive(:track_image_generation).and_return(true)
      allow(config).to receive(:track_audio).and_return(true)
    end

    it "checks track_embeddings for embedding agents" do
      agent_class = Class.new do
        def self.name; "EmbedAgent"; end
        def self.agent_type; :embedding; end
        def self.model; "embed-model"; end
      end

      middleware = described_class.new(app, agent_class)
      context = RubyLLM::Agents::Pipeline::Context.new(input: "test", agent_class: agent_class)

      expect(config).to receive(:track_embeddings).and_return(false)
      allow(app).to receive(:call) { |ctx| ctx.output = "result"; ctx }

      middleware.call(context)
    end

    it "checks track_moderation for moderation agents" do
      agent_class = Class.new do
        def self.name; "ModAgent"; end
        def self.agent_type; :moderation; end
        def self.model; "mod-model"; end
      end

      middleware = described_class.new(app, agent_class)
      context = RubyLLM::Agents::Pipeline::Context.new(input: "test", agent_class: agent_class)

      expect(config).to receive(:track_moderation).and_return(false)
      allow(app).to receive(:call) { |ctx| ctx.output = "result"; ctx }

      middleware.call(context)
    end

    it "checks track_image_generation for image agents" do
      agent_class = Class.new do
        def self.name; "ImageAgent"; end
        def self.agent_type; :image; end
        def self.model; "dalle-3"; end
      end

      middleware = described_class.new(app, agent_class)
      context = RubyLLM::Agents::Pipeline::Context.new(input: "test", agent_class: agent_class)

      expect(config).to receive(:track_image_generation).and_return(false)
      allow(app).to receive(:call) { |ctx| ctx.output = "result"; ctx }

      middleware.call(context)
    end

    it "checks track_audio for audio agents" do
      agent_class = Class.new do
        def self.name; "AudioAgent"; end
        def self.agent_type; :audio; end
        def self.model; "whisper-1"; end
      end

      middleware = described_class.new(app, agent_class)
      context = RubyLLM::Agents::Pipeline::Context.new(input: "test", agent_class: agent_class)

      expect(config).to receive(:track_audio).and_return(false)
      allow(app).to receive(:call) { |ctx| ctx.output = "result"; ctx }

      middleware.call(context)
    end

    it "checks track_executions for conversation agents" do
      agent_class = Class.new do
        def self.name; "ChatAgent"; end
        def self.agent_type; :conversation; end
        def self.model; "gpt-4o"; end
      end

      middleware = described_class.new(app, agent_class)
      context = RubyLLM::Agents::Pipeline::Context.new(input: "test", agent_class: agent_class)

      expect(config).to receive(:track_executions).and_return(false)
      allow(app).to receive(:call) { |ctx| ctx.output = "result"; ctx }

      middleware.call(context)
    end
  end
end
