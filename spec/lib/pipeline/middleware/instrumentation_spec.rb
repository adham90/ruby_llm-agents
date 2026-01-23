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
      let(:mock_execution) do
        instance_double("RubyLLM::Agents::Execution",
                        id: 123,
                        status: "running",
                        class: RubyLLM::Agents::Execution)
      end

      before do
        allow(config).to receive(:track_embeddings).and_return(true)
        allow(config).to receive(:multi_tenancy_enabled?).and_return(false)
        # Mock the Execution model
        stub_const("RubyLLM::Agents::Execution", Class.new)
      end

      describe "running execution pattern" do
        it "creates a running record at the start" do
          context = build_context

          allow(app).to receive(:call) do |ctx|
            ctx.output = "result"
            ctx
          end

          # Expect create! to be called with status: "running" first
          expect(RubyLLM::Agents::Execution).to receive(:create!).with(
            hash_including(
              agent_type: "TestAgent",
              model_id: "test-model",
              status: "running"
            )
          ).and_return(mock_execution)

          # Then expect update! to be called with final status
          expect(mock_execution).to receive(:update!).with(
            hash_including(status: "success")
          )

          middleware.call(context)
        end

        it "stores execution_id on the context" do
          context = build_context

          allow(app).to receive(:call) do |ctx|
            ctx.output = "result"
            ctx
          end

          allow(RubyLLM::Agents::Execution).to receive(:create!).and_return(mock_execution)
          allow(mock_execution).to receive(:update!)

          middleware.call(context)

          expect(context.execution_id).to eq(123)
        end

        it "updates record on successful completion" do
          context = build_context
          context.input_tokens = 100
          context.output_tokens = 50
          context.total_cost = 0.001

          allow(app).to receive(:call) do |ctx|
            ctx.output = "result"
            ctx
          end

          allow(RubyLLM::Agents::Execution).to receive(:create!).and_return(mock_execution)

          expect(mock_execution).to receive(:update!).with(
            hash_including(
              status: "success",
              input_tokens: 100,
              output_tokens: 50,
              total_cost: 0.001
            )
          )

          middleware.call(context)
        end

        it "updates record on failure with error details" do
          context = build_context
          error = StandardError.new("Execution failed")

          allow(app).to receive(:call).and_raise(error)
          allow(RubyLLM::Agents::Execution).to receive(:create!).and_return(mock_execution)

          expect(mock_execution).to receive(:update!).with(
            hash_including(
              status: "error",
              error_class: "StandardError",
              error_message: "Execution failed"
            )
          )

          expect { middleware.call(context) }.to raise_error(StandardError)
        end

        it "marks timeout errors with timeout status" do
          context = build_context
          error = Timeout::Error.new("Request timed out")

          allow(app).to receive(:call).and_raise(error)
          allow(RubyLLM::Agents::Execution).to receive(:create!).and_return(mock_execution)

          expect(mock_execution).to receive(:update!).with(
            hash_including(status: "timeout")
          )

          expect { middleware.call(context) }.to raise_error(Timeout::Error)
        end

        it "proceeds even if initial creation fails" do
          context = build_context

          allow(app).to receive(:call) do |ctx|
            ctx.output = "result"
            ctx
          end

          # Simulate failure to create initial record
          allow(RubyLLM::Agents::Execution).to receive(:create!).and_raise(StandardError.new("DB error"))

          # Should not raise, execution should proceed
          result = middleware.call(context)
          expect(result.output).to eq("result")
          expect(context.execution_id).to be_nil
        end

        it "falls back to creating new record if running record is nil" do
          context = build_context
          context.input_tokens = 100

          allow(app).to receive(:call) do |ctx|
            ctx.output = "result"
            ctx
          end

          # First create! fails (returns nil through rescue)
          allow(RubyLLM::Agents::Execution).to receive(:create!)
            .and_raise(StandardError.new("DB error"))

          # The middleware should still work
          result = middleware.call(context)
          expect(result.output).to eq("result")
        end

        it "uses mark_execution_failed! if update fails" do
          context = build_context
          execution_class = class_double("RubyLLM::Agents::Execution")
          stub_const("RubyLLM::Agents::Execution", execution_class)

          running_execution = instance_double("RubyLLM::Agents::Execution",
                                              id: 456,
                                              status: "running",
                                              class: execution_class)

          allow(app).to receive(:call) do |ctx|
            ctx.output = "result"
            ctx
          end

          allow(execution_class).to receive(:create!).and_return(running_execution)

          # Simulate update! failing
          allow(running_execution).to receive(:update!).and_raise(StandardError.new("Update failed"))

          # Expect emergency update_all to be called
          expect(execution_class).to receive(:where).with(id: 456, status: "running").and_return(execution_class)
          expect(execution_class).to receive(:update_all).with(
            hash_including(status: "error")
          )

          middleware.call(context)
        end
      end

      it "truncates long error messages" do
        context = build_context
        long_message = "x" * 2000
        error = StandardError.new(long_message)

        allow(app).to receive(:call).and_raise(error)
        allow(RubyLLM::Agents::Execution).to receive(:create!).and_return(mock_execution)

        expect(mock_execution).to receive(:update!).with(
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
        allow(RubyLLM::Agents::Execution).to receive(:create!).and_return(mock_execution)

        expect(mock_execution).to receive(:update!).with(
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
      let(:mock_execution) do
        instance_double("RubyLLM::Agents::Execution",
                        id: 123,
                        status: "running",
                        class: RubyLLM::Agents::Execution)
      end

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
          hash_including(status: "running")
        ).and_return(mock_execution)

        expect(mock_execution).to receive(:update!).with(
          hash_including(cache_hit: true)
        )

        middleware.call(context)
      end
    end

    context "async logging" do
      let(:mock_execution) do
        instance_double("RubyLLM::Agents::Execution",
                        id: 123,
                        status: "running",
                        class: RubyLLM::Agents::Execution)
      end

      before do
        allow(config).to receive(:track_embeddings).and_return(true)
        allow(config).to receive(:multi_tenancy_enabled?).and_return(false)
        stub_const("RubyLLM::Agents::Execution", Class.new)
      end

      it "creates running record synchronously even when async_logging is enabled" do
        allow(config).to receive(:async_logging).and_return(true)

        context = build_context
        context.input_tokens = 100
        context.output_tokens = 50

        allow(app).to receive(:call) do |ctx|
          ctx.output = "result"
          ctx
        end

        # Running record is always created synchronously
        expect(RubyLLM::Agents::Execution).to receive(:create!).with(
          hash_including(
            agent_type: "TestAgent",
            status: "running"
          )
        ).and_return(mock_execution)

        # Update is also called (synchronously for now to ensure dashboard correctness)
        expect(mock_execution).to receive(:update!).with(
          hash_including(status: "success")
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
            status: "running"
          )
        ).and_return(mock_execution)

        expect(mock_execution).to receive(:update!).with(
          hash_including(status: "success")
        )

        middleware.call(context)
      end

      it "falls back to legacy create when running record creation fails" do
        allow(config).to receive(:async_logging).and_return(false)

        context = build_context
        context.input_tokens = 100
        context.output_tokens = 50

        allow(app).to receive(:call) do |ctx|
          ctx.output = "result"
          ctx
        end

        # First create! fails
        allow(RubyLLM::Agents::Execution).to receive(:create!)
          .and_raise(StandardError.new("DB error"))

        # Should still work without crashing
        result = middleware.call(context)
        expect(result.output).to eq("result")
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
      allow(config).to receive(:multi_tenancy_enabled?).and_return(false)
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

    it "falls back to false when tracking config raises an error" do
      agent_class = Class.new do
        def self.name; "ErrorAgent"; end
        def self.agent_type; :unknown_type; end
        def self.model; "test-model"; end
      end

      middleware = described_class.new(app, agent_class)
      context = RubyLLM::Agents::Pipeline::Context.new(input: "test", agent_class: agent_class)

      # Make config raise an error
      allow(RubyLLM::Agents).to receive(:configuration).and_raise(StandardError.new("Config error"))
      allow(app).to receive(:call) { |ctx| ctx.output = "result"; ctx }

      # Should not raise, just skip tracking
      expect { middleware.call(context) }.not_to raise_error
    end
  end

  describe "multi-tenancy support" do
    let(:mock_execution) do
      instance_double("RubyLLM::Agents::Execution",
                      id: 123,
                      status: "running",
                      class: RubyLLM::Agents::Execution)
    end

    before do
      allow(config).to receive(:track_embeddings).and_return(true)
      stub_const("RubyLLM::Agents::Execution", Class.new)
    end

    it "includes tenant_id when multi-tenancy is enabled" do
      allow(config).to receive(:multi_tenancy_enabled?).and_return(true)

      context = build_context
      context.tenant_id = "tenant-123"

      allow(app).to receive(:call) { |ctx| ctx.output = "result"; ctx }

      expect(RubyLLM::Agents::Execution).to receive(:create!).with(
        hash_including(tenant_id: "tenant-123")
      ).and_return(mock_execution)

      allow(mock_execution).to receive(:update!)

      middleware.call(context)
    end

    it "omits tenant_id when multi-tenancy is disabled" do
      allow(config).to receive(:multi_tenancy_enabled?).and_return(false)

      context = build_context
      context.tenant_id = "tenant-123"

      allow(app).to receive(:call) { |ctx| ctx.output = "result"; ctx }

      expect(RubyLLM::Agents::Execution).to receive(:create!).with(
        hash_not_including(:tenant_id)
      ).and_return(mock_execution)

      allow(mock_execution).to receive(:update!)

      middleware.call(context)
    end
  end

  describe "cache key tracking" do
    let(:mock_execution) do
      instance_double("RubyLLM::Agents::Execution",
                      id: 123,
                      status: "running",
                      class: RubyLLM::Agents::Execution)
    end

    before do
      allow(config).to receive(:track_embeddings).and_return(true)
      allow(config).to receive(:respond_to?).with(:track_cache_hits).and_return(true)
      allow(config).to receive(:track_cache_hits).and_return(true)
      allow(config).to receive(:multi_tenancy_enabled?).and_return(false)
      stub_const("RubyLLM::Agents::Execution", Class.new)
    end

    it "includes cache key for cached results" do
      context = build_context
      context.cached = true
      context[:cache_key] = "ruby_llm_agents/test/key"

      allow(app).to receive(:call) { |ctx| ctx.output = "result"; ctx }
      allow(RubyLLM::Agents::Execution).to receive(:create!).and_return(mock_execution)

      expect(mock_execution).to receive(:update!).with(
        hash_including(response_cache_key: "ruby_llm_agents/test/key")
      )

      middleware.call(context)
    end
  end

  describe "metadata tracking" do
    let(:mock_execution) do
      instance_double("RubyLLM::Agents::Execution",
                      id: 123,
                      status: "running",
                      class: RubyLLM::Agents::Execution)
    end

    before do
      allow(config).to receive(:track_embeddings).and_return(true)
      allow(config).to receive(:multi_tenancy_enabled?).and_return(false)
      stub_const("RubyLLM::Agents::Execution", Class.new)
    end

    it "includes custom metadata in execution record when metadata is present" do
      context = build_context
      # Use the []= method to set metadata directly on the context's @metadata hash
      context[:custom_field] = "custom_value"
      context[:request_id] = "req-123"

      # Verify metadata is set
      expect(context.metadata).not_to be_empty

      allow(app).to receive(:call) do |ctx|
        ctx.output = "result"
        ctx
      end
      allow(RubyLLM::Agents::Execution).to receive(:create!).and_return(mock_execution)

      # The middleware only includes metadata if context.metadata.any? is true
      expect(mock_execution).to receive(:update!) do |data|
        # Metadata should be included when context has metadata entries
        expect(data[:status]).to eq("success")
        # Check if metadata was properly propagated
        if context.metadata.any?
          expect(data).to have_key(:metadata)
        end
      end

      middleware.call(context)
    end

    it "does not include metadata key when metadata is empty" do
      context = build_context
      # Don't add any metadata

      allow(app).to receive(:call) { |ctx| ctx.output = "result"; ctx }
      allow(RubyLLM::Agents::Execution).to receive(:create!).and_return(mock_execution)

      expect(mock_execution).to receive(:update!).with(
        hash_not_including(:metadata)
      )

      middleware.call(context)
    end
  end

  describe "parameter sanitization" do
    let(:mock_execution) do
      instance_double("RubyLLM::Agents::Execution",
                      id: 123,
                      status: "running",
                      class: RubyLLM::Agents::Execution)
    end

    let(:agent_class_with_options) do
      Class.new do
        def self.name; "AgentWithOptions"; end
        def self.agent_type; :embedding; end
        def self.model; "test-model"; end
      end
    end

    before do
      allow(config).to receive(:track_embeddings).and_return(true)
      allow(config).to receive(:multi_tenancy_enabled?).and_return(false)
      stub_const("RubyLLM::Agents::Execution", Class.new)
    end

    it "redacts sensitive parameters" do
      agent_instance = instance_double("AgentInstance")
      allow(agent_instance).to receive(:respond_to?).with(:options, true).and_return(true)
      allow(agent_instance).to receive(:options).and_return({
        query: "test query",
        api_key: "secret-key",
        password: "secret-pass",
        token: "bearer-token",
        normal_param: "normal"
      })

      context = RubyLLM::Agents::Pipeline::Context.new(
        input: "test",
        agent_class: agent_class_with_options,
        agent_instance: agent_instance
      )

      allow(app).to receive(:call) { |ctx| ctx.output = "result"; ctx }

      expect(RubyLLM::Agents::Execution).to receive(:create!).with(
        hash_including(
          parameters: hash_including(
            "query" => "test query",
            "api_key" => "[REDACTED]",
            "password" => "[REDACTED]",
            "token" => "[REDACTED]",
            "normal_param" => "normal"
          )
        )
      ).and_return(mock_execution)

      allow(mock_execution).to receive(:update!)

      middleware.call(context)
    end
  end
end
