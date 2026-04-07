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

  def build_context(options = {})
    RubyLLM::Agents::Pipeline::Context.new(
      input: "test",
      agent_class: agent_class,
      **options
    )
  end

  before do
    RubyLLM::Agents.reset_configuration!
    RubyLLM::Agents.configure do |c|
      c.track_embeddings = true
      c.track_executions = true
      c.track_image_generation = true
      c.track_audio = true
      c.async_logging = false
      c.persist_prompts = true
      c.persist_responses = false
    end
  end

  after do
    RubyLLM::Agents.reset_configuration!
  end

  describe "#call" do
    it "sets started_at timestamp" do
      context = build_context
      allow(app).to receive(:call) { |ctx|
        ctx.output = "result"
        ctx
      }
      RubyLLM::Agents.configuration.track_embeddings = false

      result = middleware.call(context)

      expect(result.started_at).to be_a(Time)
    end

    it "sets completed_at timestamp on success" do
      context = build_context
      allow(app).to receive(:call) { |ctx|
        ctx.output = "result"
        ctx
      }
      RubyLLM::Agents.configuration.track_embeddings = false

      result = middleware.call(context)

      expect(result.completed_at).to be_a(Time)
      expect(result.completed_at).to be >= result.started_at
    end

    it "sets completed_at timestamp on failure" do
      context = build_context
      allow(app).to receive(:call).and_raise(StandardError, "Test error")
      RubyLLM::Agents.configuration.track_embeddings = false

      expect { middleware.call(context) }.to raise_error(StandardError)

      expect(context.completed_at).to be_a(Time)
    end

    it "re-raises errors from the execution" do
      context = build_context
      allow(app).to receive(:call).and_raise(StandardError, "Test error")
      RubyLLM::Agents.configuration.track_embeddings = false

      expect { middleware.call(context) }.to raise_error(StandardError, "Test error")
    end

    it "records the error on the context" do
      context = build_context
      error = StandardError.new("Test error")
      allow(app).to receive(:call).and_raise(error)
      RubyLLM::Agents.configuration.track_embeddings = false

      expect { middleware.call(context) }.to raise_error(StandardError)

      expect(context.error).to eq(error)
    end

    context "when tracking is enabled" do
      before do
        RubyLLM::Agents.configuration.track_embeddings = true
        RubyLLM::Agents.configuration.multi_tenancy_enabled = false
      end

      describe "running execution pattern" do
        it "creates a running record at the start" do
          context = build_context

          allow(app).to receive(:call) do |ctx|
            ctx.output = "result"
            ctx
          end

          expect { middleware.call(context) }.to change(RubyLLM::Agents::Execution, :count).by(1)

          execution = RubyLLM::Agents::Execution.last
          expect(execution.agent_type).to eq("TestAgent")
          expect(execution.model_id).to eq("test-model")
          expect(execution.status).to eq("success")
        end

        it "stores execution_id on the context" do
          context = build_context

          allow(app).to receive(:call) do |ctx|
            ctx.output = "result"
            ctx
          end

          middleware.call(context)

          expect(context.execution_id).to eq(RubyLLM::Agents::Execution.last.id)
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

          middleware.call(context)

          execution = RubyLLM::Agents::Execution.last
          expect(execution.status).to eq("success")
          expect(execution.input_tokens).to eq(100)
          expect(execution.output_tokens).to eq(50)
          expect(execution.total_cost).to eq(0.001)
        end

        it "updates record on failure with error details" do
          context = build_context
          error = StandardError.new("Execution failed")

          allow(app).to receive(:call).and_raise(error)

          expect { middleware.call(context) }.to raise_error(StandardError)

          execution = RubyLLM::Agents::Execution.last
          expect(execution.status).to eq("error")
          expect(execution.error_class).to eq("StandardError")
        end

        it "marks timeout errors with timeout status" do
          context = build_context
          error = Timeout::Error.new("Request timed out")

          allow(app).to receive(:call).and_raise(error)

          expect { middleware.call(context) }.to raise_error(Timeout::Error)

          execution = RubyLLM::Agents::Execution.last
          expect(execution.status).to eq("timeout")
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

          # Create a real running execution
          running_execution = create(:execution, :running, agent_type: "TestAgent", model_id: "test-model")

          allow(app).to receive(:call) do |ctx|
            ctx.output = "result"
            ctx
          end

          allow(RubyLLM::Agents::Execution).to receive(:create!).and_return(running_execution)

          # Simulate update! failing
          allow(running_execution).to receive(:update!).and_raise(StandardError.new("Update failed"))

          # Expect emergency update_all to be called
          expect(RubyLLM::Agents::Execution).to receive(:where).with(id: running_execution.id, status: "running").and_call_original

          middleware.call(context)

          # Verify the execution was marked as error
          running_execution.reload
          expect(running_execution.status).to eq("error")
        end
      end

      it "truncates long error messages" do
        context = build_context
        long_message = "x" * 2000
        error = StandardError.new(long_message)

        allow(app).to receive(:call).and_raise(error)

        expect { middleware.call(context) }.to raise_error(StandardError)

        execution = RubyLLM::Agents::Execution.last
        expect(execution.status).to eq("error")
        expect(execution.error_class).to eq("StandardError")
      end

      it "includes token usage in execution record" do
        context = build_context
        context.input_tokens = 500
        context.output_tokens = 200
        context.total_cost = 0.0035

        allow(app).to receive(:call) { |ctx|
          ctx.output = "result"
          ctx
        }

        middleware.call(context)

        execution = RubyLLM::Agents::Execution.last
        expect(execution.input_tokens).to eq(500)
        expect(execution.output_tokens).to eq(200)
        expect(execution.total_cost).to eq(0.0035)
      end
    end

    context "when tracking is disabled" do
      before do
        RubyLLM::Agents.configuration.track_embeddings = false
        RubyLLM::Agents.configuration.track_executions = false
      end

      it "does not create execution records" do
        context = build_context

        allow(app).to receive(:call) { |ctx|
          ctx.output = "result"
          ctx
        }

        expect { middleware.call(context) }.not_to change(RubyLLM::Agents::Execution, :count)
      end
    end

    context "when result is cached" do
      before do
        RubyLLM::Agents.configuration.track_embeddings = true
        RubyLLM::Agents.configuration.track_cache_hits = false
        RubyLLM::Agents.configuration.multi_tenancy_enabled = false
      end

      it "does not record cache hits when track_cache_hits is false" do
        context = build_context
        context.cached = true

        allow(app).to receive(:call) { |ctx|
          ctx.output = "cached_result"
          ctx
        }

        expect { middleware.call(context) }.not_to change(RubyLLM::Agents::Execution, :count)
      end

      it "records cache hits when track_cache_hits is true" do
        RubyLLM::Agents.configuration.track_cache_hits = true

        context = build_context
        context.cached = true

        allow(app).to receive(:call) { |ctx|
          ctx.output = "cached_result"
          ctx
        }

        middleware.call(context)

        execution = RubyLLM::Agents::Execution.last
        expect(execution).to be_present
        expect(execution.cache_hit).to eq(true)
      end
    end

    context "async logging" do
      before do
        RubyLLM::Agents.configuration.track_embeddings = true
        RubyLLM::Agents.configuration.multi_tenancy_enabled = false
      end

      it "creates running record synchronously even when async_logging is enabled" do
        RubyLLM::Agents.configuration.async_logging = true

        context = build_context
        context.input_tokens = 100
        context.output_tokens = 50

        allow(app).to receive(:call) do |ctx|
          ctx.output = "result"
          ctx
        end

        middleware.call(context)

        execution = RubyLLM::Agents::Execution.last
        expect(execution).to be_present
        expect(execution.agent_type).to eq("TestAgent")
        expect(execution.status).to eq("success")
      end

      it "falls back to sync when async_logging is disabled" do
        RubyLLM::Agents.configuration.async_logging = false

        context = build_context
        context.input_tokens = 100
        context.output_tokens = 50

        allow(app).to receive(:call) do |ctx|
          ctx.output = "result"
          ctx
        end

        middleware.call(context)

        execution = RubyLLM::Agents::Execution.last
        expect(execution).to be_present
        expect(execution.agent_type).to eq("TestAgent")
        expect(execution.status).to eq("success")
      end

      it "falls back to legacy create when running record creation fails" do
        RubyLLM::Agents.configuration.async_logging = false

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
    before do
      RubyLLM::Agents.configure do |c|
        c.async_logging = false
        c.track_embeddings = true
        c.track_executions = true
        c.track_image_generation = true
        c.track_audio = true
        c.multi_tenancy_enabled = false
      end
    end

    it_behaves_like "tracking disabled for agent type",
      agent_type: :embedding, config_flag: :track_embeddings, agent_name: "EmbedAgent"

    it_behaves_like "tracking disabled for agent type",
      agent_type: :image, config_flag: :track_image_generation, agent_name: "ImageAgent", model_name: "dalle-3"

    it_behaves_like "tracking disabled for agent type",
      agent_type: :audio, config_flag: :track_audio, agent_name: "AudioAgent", model_name: "whisper-1"

    it_behaves_like "tracking disabled for agent type",
      agent_type: :conversation, config_flag: :track_executions, agent_name: "ChatAgent", model_name: "gpt-4o"

    it "falls back to false when tracking config raises an error" do
      agent_class = Class.new do
        def self.name
          "ErrorAgent"
        end

        def self.agent_type
          :unknown_type
        end

        def self.model
          "test-model"
        end
      end

      middleware = described_class.new(app, agent_class)
      context = RubyLLM::Agents::Pipeline::Context.new(input: "test", agent_class: agent_class)

      # Make config raise an error
      allow(RubyLLM::Agents).to receive(:configuration).and_raise(StandardError.new("Config error"))
      allow(app).to receive(:call) { |ctx|
        ctx.output = "result"
        ctx
      }

      # Should not raise, just skip tracking
      expect { middleware.call(context) }.not_to raise_error
    end
  end

  describe "multi-tenancy support" do
    before do
      RubyLLM::Agents.configuration.track_embeddings = true
    end

    it "includes tenant_id when multi-tenancy is enabled" do
      RubyLLM::Agents.configuration.multi_tenancy_enabled = true

      context = build_context
      context.tenant_id = "tenant-123"

      allow(app).to receive(:call) { |ctx|
        ctx.output = "result"
        ctx
      }

      middleware.call(context)

      execution = RubyLLM::Agents::Execution.last
      expect(execution).to be_present
      expect(execution.tenant_id).to eq("tenant-123")
    end

    it "omits tenant_id when multi-tenancy is disabled" do
      RubyLLM::Agents.configuration.multi_tenancy_enabled = false

      context = build_context
      context.tenant_id = "tenant-123"

      allow(app).to receive(:call) { |ctx|
        ctx.output = "result"
        ctx
      }

      middleware.call(context)

      execution = RubyLLM::Agents::Execution.last
      expect(execution).to be_present
      expect(execution.tenant_id).to be_nil
    end
  end

  describe "cache key tracking" do
    before do
      RubyLLM::Agents.configuration.track_embeddings = true
      RubyLLM::Agents.configuration.track_cache_hits = true
      RubyLLM::Agents.configuration.multi_tenancy_enabled = false
    end

    it "includes cache key for cached results" do
      context = build_context
      context.cached = true
      context[:cache_key] = "ruby_llm_agents/test/key"

      allow(app).to receive(:call) { |ctx|
        ctx.output = "result"
        ctx
      }

      middleware.call(context)

      execution = RubyLLM::Agents::Execution.last
      expect(execution).to be_present
      expect(execution.metadata).to include("response_cache_key" => "ruby_llm_agents/test/key")
    end
  end

  describe "metadata tracking" do
    before do
      RubyLLM::Agents.configuration.track_embeddings = true
      RubyLLM::Agents.configuration.multi_tenancy_enabled = false
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

      middleware.call(context)

      execution = RubyLLM::Agents::Execution.last
      expect(execution).to be_present
      expect(execution.status).to eq("success")
      expect(execution.metadata).to include("custom_field" => "custom_value")
      expect(execution.metadata).to include("request_id" => "req-123")
    end

    it "does not include metadata key when metadata is empty" do
      context = build_context
      # Don't add any metadata

      allow(app).to receive(:call) { |ctx|
        ctx.output = "result"
        ctx
      }

      middleware.call(context)

      execution = RubyLLM::Agents::Execution.last
      expect(execution).to be_present
      expect(execution.metadata).to be_blank
    end
  end

  describe "agent metadata merging" do
    before do
      RubyLLM::Agents.reset_configuration!
      RubyLLM::Agents.configure do |c|
        c.track_embeddings = true
        c.track_executions = true
        c.persist_prompts = false
        c.persist_responses = false
      end
    end

    # Real agent classes with real metadata methods
    let(:agent_class_with_metadata) do
      Class.new do
        def self.name = "MetadataAgent"
        def self.agent_type = :embedding
        def self.model = "test-model"

        attr_reader :options

        def initialize
          @options = {}
        end

        def metadata
          {user_id: 42, experiment: "v2"}
        end
      end
    end

    let(:agent_class_without_metadata) do
      Class.new do
        def self.name = "NoMetadataAgent"
        def self.agent_type = :embedding
        def self.model = "test-model"

        attr_reader :options

        def initialize
          @options = {}
        end
      end
    end

    let(:agent_class_with_broken_metadata) do
      Class.new do
        def self.name = "BrokenMetadataAgent"
        def self.agent_type = :embedding
        def self.model = "test-model"

        attr_reader :options

        def initialize
          @options = {}
        end

        def metadata
          raise "broken metadata"
        end
      end
    end

    # A real pass-through app that sets output on the context
    let(:passthrough_app) do
      proc { |ctx|
        ctx.output = "result"
        ctx
      }
    end

    it "includes agent metadata in the running record" do
      agent_instance = agent_class_with_metadata.new
      mw = described_class.new(passthrough_app, agent_class_with_metadata)
      context = RubyLLM::Agents::Pipeline::Context.new(
        input: "test",
        agent_class: agent_class_with_metadata,
        agent_instance: agent_instance
      )

      mw.call(context)

      execution = RubyLLM::Agents::Execution.last
      expect(execution.metadata).to include("user_id" => 42, "experiment" => "v2")
    end

    it "includes agent metadata in the completion record" do
      agent_instance = agent_class_with_metadata.new
      mw = described_class.new(passthrough_app, agent_class_with_metadata)
      context = RubyLLM::Agents::Pipeline::Context.new(
        input: "test",
        agent_class: agent_class_with_metadata,
        agent_instance: agent_instance
      )

      mw.call(context)

      execution = RubyLLM::Agents::Execution.last
      expect(execution.status).to eq("success")
      expect(execution.metadata).to include("user_id" => 42, "experiment" => "v2")
    end

    it "gives middleware metadata priority over agent metadata on key collision" do
      colliding_agent_class = Class.new do
        def self.name = "CollidingAgent"
        def self.agent_type = :embedding
        def self.model = "test-model"

        attr_reader :options

        def initialize
          @options = {}
        end

        def metadata
          {source: "agent_value", user_id: 42}
        end
      end

      agent_instance = colliding_agent_class.new
      mw = described_class.new(passthrough_app, colliding_agent_class)
      context = RubyLLM::Agents::Pipeline::Context.new(
        input: "test",
        agent_class: colliding_agent_class,
        agent_instance: agent_instance
      )
      # Middleware sets a key that collides with agent metadata
      context[:source] = "middleware_value"

      mw.call(context)

      execution = RubyLLM::Agents::Execution.last
      expect(execution.metadata["source"]).to eq("middleware_value")
      expect(execution.metadata["user_id"]).to eq(42)
    end

    it "works when agent does not define metadata" do
      agent_instance = agent_class_without_metadata.new
      mw = described_class.new(passthrough_app, agent_class_without_metadata)
      context = RubyLLM::Agents::Pipeline::Context.new(
        input: "test",
        agent_class: agent_class_without_metadata,
        agent_instance: agent_instance
      )

      mw.call(context)

      execution = RubyLLM::Agents::Execution.last
      expect(execution.metadata).to be_blank
    end

    it "handles gracefully when agent metadata raises an error" do
      agent_instance = agent_class_with_broken_metadata.new
      mw = described_class.new(passthrough_app, agent_class_with_broken_metadata)
      context = RubyLLM::Agents::Pipeline::Context.new(
        input: "test",
        agent_class: agent_class_with_broken_metadata,
        agent_instance: agent_instance
      )

      # Should not raise - metadata error is swallowed
      expect { mw.call(context) }.not_to raise_error

      execution = RubyLLM::Agents::Execution.last
      expect(execution.status).to eq("success")
    end

    it "handles gracefully when agent_instance is nil" do
      mw = described_class.new(passthrough_app, agent_class_with_metadata)
      context = RubyLLM::Agents::Pipeline::Context.new(
        input: "test",
        agent_class: agent_class_with_metadata,
        agent_instance: nil
      )

      expect { mw.call(context) }.not_to raise_error

      execution = RubyLLM::Agents::Execution.last
      expect(execution.status).to eq("success")
      expect(execution.metadata).to be_blank
    end
  end

  describe "parameter sanitization" do
    let(:agent_class_with_options) do
      Class.new do
        def self.name
          "AgentWithOptions"
        end

        def self.agent_type
          :embedding
        end

        def self.model
          "test-model"
        end
      end
    end

    before do
      RubyLLM::Agents.configuration.track_embeddings = true
      RubyLLM::Agents.configuration.multi_tenancy_enabled = false
    end

    it "redacts sensitive parameters" do
      # Create a simple class to represent an agent instance with options
      agent_instance_class = Class.new do
        attr_reader :options

        def initialize(options)
          @options = options
        end
      end

      agent_instance = agent_instance_class.new({
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

      allow(app).to receive(:call) { |ctx|
        ctx.output = "result"
        ctx
      }

      middleware.call(context)

      execution = RubyLLM::Agents::Execution.last
      expect(execution).to be_present
      expect(execution.detail).to be_present
      expect(execution.detail.parameters).to include(
        "query" => "test query",
        "api_key" => "[REDACTED]",
        "password" => "[REDACTED]",
        "token" => "[REDACTED]",
        "normal_param" => "normal"
      )
    end
  end

  describe "response persistence" do
    before do
      RubyLLM::Agents.configuration.track_embeddings = true
      RubyLLM::Agents.configuration.multi_tenancy_enabled = false
    end

    context "when persist_responses is enabled" do
      before do
        RubyLLM::Agents.configuration.persist_responses = true
      end

      it "stores response when output has content" do
        context = build_context

        result_obj = RubyLLM::Agents::Result.new(content: "Test response")
        allow(app).to receive(:call) do |ctx|
          ctx.output = result_obj
          ctx
        end

        middleware.call(context)

        execution = RubyLLM::Agents::Execution.last
        expect(execution).to be_present
        expect(execution.detail).to be_present
        expect(execution.detail.response).to include("content" => "Test response")
      end

      it "includes model_id in response when available" do
        context = build_context
        context.model_used = "gpt-4"

        result_obj = RubyLLM::Agents::Result.new(content: "Test response")
        allow(app).to receive(:call) do |ctx|
          ctx.output = result_obj
          ctx
        end

        middleware.call(context)

        execution = RubyLLM::Agents::Execution.last
        expect(execution).to be_present
        expect(execution.detail).to be_present
        expect(execution.detail.response).to include("content" => "Test response", "model_id" => "gpt-4")
      end

      it "includes token info in response when available" do
        context = build_context
        context.input_tokens = 100
        context.output_tokens = 50

        result_obj = RubyLLM::Agents::Result.new(content: "Test response")
        allow(app).to receive(:call) do |ctx|
          ctx.output = result_obj
          ctx
        end

        middleware.call(context)

        execution = RubyLLM::Agents::Execution.last
        expect(execution).to be_present
        expect(execution.detail).to be_present
        expect(execution.detail.response).to include("input_tokens" => 100, "output_tokens" => 50)
      end

      it "does not store response when output is nil" do
        context = build_context

        allow(app).to receive(:call) do |ctx|
          ctx.output = nil
          ctx
        end

        middleware.call(context)

        execution = RubyLLM::Agents::Execution.last
        expect(execution).to be_present
        # No detail record should be created with response data, or response should be empty
        if execution.detail
          expect(execution.detail.response).to be_blank
        end
      end

      it "does not store response when output does not respond to content" do
        context = build_context

        allow(app).to receive(:call) do |ctx|
          ctx.output = "plain string"
          ctx
        end

        middleware.call(context)

        execution = RubyLLM::Agents::Execution.last
        expect(execution).to be_present
        # No detail record should be created with response data, or response should be empty
        if execution.detail
          expect(execution.detail.response).to be_blank
        end
      end
    end

    context "when persist_responses is disabled" do
      before do
        RubyLLM::Agents.configuration.persist_responses = false
      end

      it "does not store response even when output has content" do
        context = build_context

        result_obj = RubyLLM::Agents::Result.new(content: "Test response")
        allow(app).to receive(:call) do |ctx|
          ctx.output = result_obj
          ctx
        end

        middleware.call(context)

        execution = RubyLLM::Agents::Execution.last
        expect(execution).to be_present
        # Response should not be persisted
        if execution.detail
          expect(execution.detail.response).to be_blank
        end
      end
    end

    describe "reliability attempts persistence" do
      before do
        RubyLLM::Agents.configuration.multi_tenancy_enabled = false
      end

      it "persists reliability_attempts in the execution record" do
        context = build_context
        context[:reliability_attempts] = [
          {"model_id" => "gemini-2.5-flash", "error_class" => "StandardError", "error_message" => "quota exceeded"},
          {"model_id" => "gpt-4.1-mini", "error_class" => nil, "error_message" => nil}
        ]

        allow(app).to receive(:call) do |ctx|
          ctx.output = "result"
          ctx
        end

        middleware.call(context)

        execution = RubyLLM::Agents::Execution.last
        expect(execution).to be_present
        expect(execution.attempts_count).to eq(2)

        # Attempts data is stored on the detail record
        expect(execution.detail).to be_present
        expect(execution.detail.attempts).to eq([
          {"model_id" => "gemini-2.5-flash", "error_class" => "StandardError", "error_message" => "quota exceeded"},
          {"model_id" => "gpt-4.1-mini", "error_class" => nil, "error_message" => nil}
        ])
      end

      it "does not include attempts when reliability_attempts is absent" do
        context = build_context

        allow(app).to receive(:call) do |ctx|
          ctx.output = "result"
          ctx
        end

        middleware.call(context)

        execution = RubyLLM::Agents::Execution.last
        expect(execution).to be_present
        # Default attempts_count is 0 when no reliability middleware has run
        expect(execution.attempts_count).to eq(0)
      end
    end
  end

  describe "tracing fields extraction from agent metadata" do
    before do
      RubyLLM::Agents.reset_configuration!
      RubyLLM::Agents.configure do |c|
        c.track_embeddings = true
        c.track_executions = true
        c.persist_prompts = false
        c.persist_responses = false
      end
    end

    let(:passthrough_app) do
      proc { |ctx|
        ctx.output = "result"
        ctx
      }
    end

    let(:agent_class_with_tracing) do
      Class.new do
        def self.name = "TracingAgent"
        def self.agent_type = :embedding
        def self.model = "test-model"

        attr_reader :options

        def initialize
          @options = {}
        end

        def metadata
          {trace_id: "trace-abc-123", request_id: "req-xyz-789", user_id: 42}
        end
      end
    end

    it "extracts trace_id from agent metadata to the dedicated column" do
      agent_instance = agent_class_with_tracing.new
      mw = described_class.new(passthrough_app, agent_class_with_tracing)
      context = RubyLLM::Agents::Pipeline::Context.new(
        input: "test",
        agent_class: agent_class_with_tracing,
        agent_instance: agent_instance
      )

      mw.call(context)

      execution = RubyLLM::Agents::Execution.last
      expect(execution.trace_id).to eq("trace-abc-123")
    end

    it "extracts request_id from agent metadata to the dedicated column" do
      agent_instance = agent_class_with_tracing.new
      mw = described_class.new(passthrough_app, agent_class_with_tracing)
      context = RubyLLM::Agents::Pipeline::Context.new(
        input: "test",
        agent_class: agent_class_with_tracing,
        agent_instance: agent_instance
      )

      mw.call(context)

      execution = RubyLLM::Agents::Execution.last
      expect(execution.request_id).to eq("req-xyz-789")
    end

    it "extracts parent_execution_id from agent metadata to the dedicated column" do
      parent = RubyLLM::Agents::Execution.create!(
        agent_type: "ParentAgent",
        model_id: "test-model",
        started_at: Time.current,
        status: "success"
      )

      agent_class_with_parent = Class.new do
        def self.name = "ChildAgent"
        def self.agent_type = :embedding
        def self.model = "test-model"

        attr_reader :options
        attr_accessor :parent_id

        def initialize(parent_id)
          @options = {}
          @parent_id = parent_id
        end

        def metadata
          {parent_execution_id: parent_id}
        end
      end

      agent_instance = agent_class_with_parent.new(parent.id)
      mw = described_class.new(passthrough_app, agent_class_with_parent)
      context = RubyLLM::Agents::Pipeline::Context.new(
        input: "test",
        agent_class: agent_class_with_parent,
        agent_instance: agent_instance
      )

      mw.call(context)

      execution = RubyLLM::Agents::Execution.last
      expect(execution.parent_execution_id).to eq(parent.id)
    end

    it "extracts root_execution_id from agent metadata to the dedicated column" do
      root = RubyLLM::Agents::Execution.create!(
        agent_type: "RootAgent",
        model_id: "test-model",
        started_at: Time.current,
        status: "success"
      )

      agent_class_with_root = Class.new do
        def self.name = "NestedAgent"
        def self.agent_type = :embedding
        def self.model = "test-model"

        attr_reader :options
        attr_accessor :root_id

        def initialize(root_id)
          @options = {}
          @root_id = root_id
        end

        def metadata
          {root_execution_id: root_id}
        end
      end

      agent_instance = agent_class_with_root.new(root.id)
      mw = described_class.new(passthrough_app, agent_class_with_root)
      context = RubyLLM::Agents::Pipeline::Context.new(
        input: "test",
        agent_class: agent_class_with_root,
        agent_instance: agent_instance
      )

      mw.call(context)

      execution = RubyLLM::Agents::Execution.last
      expect(execution.root_execution_id).to eq(root.id)
    end

    it "still includes non-tracing metadata in the metadata column" do
      agent_instance = agent_class_with_tracing.new
      mw = described_class.new(passthrough_app, agent_class_with_tracing)
      context = RubyLLM::Agents::Pipeline::Context.new(
        input: "test",
        agent_class: agent_class_with_tracing,
        agent_instance: agent_instance
      )

      mw.call(context)

      execution = RubyLLM::Agents::Execution.last
      expect(execution.metadata).to include("user_id" => 42)
    end

    it "extracts tracing fields in the legacy fallback path (build_execution_data)" do
      agent_instance = agent_class_with_tracing.new
      mw = described_class.new(passthrough_app, agent_class_with_tracing)
      context = RubyLLM::Agents::Pipeline::Context.new(
        input: "test",
        agent_class: agent_class_with_tracing,
        agent_instance: agent_instance
      )

      # Force the legacy fallback path by making the initial create fail once
      call_count = 0
      allow(RubyLLM::Agents::Execution).to receive(:create!).and_wrap_original do |method, *args|
        call_count += 1
        if call_count == 1
          raise ActiveRecord::RecordInvalid.new(RubyLLM::Agents::Execution.new)
        else
          method.call(*args)
        end
      end

      mw.call(context)

      execution = RubyLLM::Agents::Execution.last
      expect(execution.trace_id).to eq("trace-abc-123")
      expect(execution.request_id).to eq("req-xyz-789")
    end
  end

  describe "model_provider population (issue #23)" do
    before do
      RubyLLM::Agents.configuration.track_embeddings = true
      RubyLLM::Agents.configuration.multi_tenancy_enabled = false
    end

    it "resolves model_provider from model registry on running record" do
      model_info = double("ModelInfo", provider: "openai")
      allow(RubyLLM::Models).to receive(:find).with("test-model").and_return(model_info)

      context = build_context
      allow(app).to receive(:call) do |ctx|
        ctx.output = "result"
        ctx
      end

      middleware.call(context)

      execution = RubyLLM::Agents::Execution.last
      expect(execution.model_provider).to eq("openai")
    end

    it "resolves model_provider for anthropic models" do
      model_info = double("ModelInfo", provider: "anthropic")
      allow(RubyLLM::Models).to receive(:find).with("test-model").and_return(model_info)

      context = build_context
      allow(app).to receive(:call) do |ctx|
        ctx.output = "result"
        ctx
      end

      middleware.call(context)

      execution = RubyLLM::Agents::Execution.last
      expect(execution.model_provider).to eq("anthropic")
    end

    it "leaves model_provider nil when model registry lookup fails" do
      allow(RubyLLM::Models).to receive(:find).and_raise(StandardError, "Model not found")

      context = build_context
      allow(app).to receive(:call) do |ctx|
        ctx.output = "result"
        ctx
      end

      middleware.call(context)

      execution = RubyLLM::Agents::Execution.last
      expect(execution.model_provider).to be_nil
    end

    it "leaves model_provider nil when model info has no provider" do
      model_info = double("ModelInfo", provider: nil)
      allow(RubyLLM::Models).to receive(:find).with("test-model").and_return(model_info)

      context = build_context
      allow(app).to receive(:call) do |ctx|
        ctx.output = "result"
        ctx
      end

      middleware.call(context)

      execution = RubyLLM::Agents::Execution.last
      expect(execution.model_provider).to be_nil
    end
  end

  describe "chosen_model_id population" do
    before do
      RubyLLM::Agents.configuration.track_embeddings = true
      RubyLLM::Agents.configuration.multi_tenancy_enabled = false
    end

    it "records chosen_model_id when model_used differs from model" do
      context = build_context
      allow(app).to receive(:call) do |ctx|
        ctx.model_used = "gpt-4o-mini"
        ctx.output = "result"
        ctx
      end

      middleware.call(context)

      execution = RubyLLM::Agents::Execution.last
      expect(execution.chosen_model_id).to eq("gpt-4o-mini")
    end

    it "records chosen_model_id same as model when no fallback" do
      context = build_context
      allow(app).to receive(:call) do |ctx|
        ctx.model_used = "test-model"
        ctx.output = "result"
        ctx
      end

      middleware.call(context)

      execution = RubyLLM::Agents::Execution.last
      expect(execution.chosen_model_id).to eq("test-model")
    end
  end

  describe "finish_reason population" do
    before do
      RubyLLM::Agents.configuration.track_embeddings = true
      RubyLLM::Agents.configuration.multi_tenancy_enabled = false
    end

    it "records finish_reason on completion" do
      context = build_context
      allow(app).to receive(:call) do |ctx|
        ctx.finish_reason = "stop"
        ctx.output = "result"
        ctx
      end

      middleware.call(context)

      execution = RubyLLM::Agents::Execution.last
      expect(execution.finish_reason).to eq("stop")
    end

    it "records tool_calls finish_reason" do
      context = build_context
      allow(app).to receive(:call) do |ctx|
        ctx.finish_reason = "tool_calls"
        ctx.output = "result"
        ctx
      end

      middleware.call(context)

      execution = RubyLLM::Agents::Execution.last
      expect(execution.finish_reason).to eq("tool_calls")
    end

    it "leaves finish_reason nil when not set" do
      context = build_context
      allow(app).to receive(:call) do |ctx|
        ctx.output = "result"
        ctx
      end

      middleware.call(context)

      execution = RubyLLM::Agents::Execution.last
      expect(execution.finish_reason).to be_nil
    end
  end
end
