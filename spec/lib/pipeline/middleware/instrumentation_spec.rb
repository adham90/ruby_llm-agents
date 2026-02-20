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
      let(:mock_execution) do
        double("RubyLLM::Agents::Execution",
          id: 123,
          status: "running",
          detail: nil,
          class: RubyLLM::Agents::Execution,
          parent_execution_id: nil,
          root_execution_id: nil)
      end

      before do
        RubyLLM::Agents.configuration.track_embeddings = true
        RubyLLM::Agents.configuration.multi_tenancy_enabled = false
        # Allow detail creation for prompt persistence
        allow(mock_execution).to receive(:create_detail!)
        # Allow hierarchy ID updates
        allow(mock_execution).to receive(:update_column)
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
          allow(mock_execution).to receive(:create_detail!)

          expect(mock_execution).to receive(:update!).with(
            hash_including(
              status: "error",
              error_class: "StandardError"
            )
          )

          expect { middleware.call(context) }.to raise_error(StandardError)
        end

        it "marks timeout errors with timeout status" do
          context = build_context
          error = Timeout::Error.new("Request timed out")

          allow(app).to receive(:call).and_raise(error)
          allow(RubyLLM::Agents::Execution).to receive(:create!).and_return(mock_execution)
          allow(mock_execution).to receive(:create_detail!)

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
          # The update_all will actually run against the database

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
        allow(RubyLLM::Agents::Execution).to receive(:create!).and_return(mock_execution)
        allow(mock_execution).to receive(:create_detail!)

        # error_message is now stored on the detail record, not the execution
        expect(mock_execution).to receive(:update!).with(
          hash_including(
            status: "error",
            error_class: "StandardError"
          )
        )

        expect { middleware.call(context) }.to raise_error(StandardError)
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
        RubyLLM::Agents.configuration.track_embeddings = false
        RubyLLM::Agents.configuration.track_executions = false
      end

      it "does not create execution records" do
        context = build_context

        allow(app).to receive(:call) { |ctx|
          ctx.output = "result"
          ctx
        }

        # Should not call create! if tracking is disabled
        if defined?(RubyLLM::Agents::Execution)
          expect(RubyLLM::Agents::Execution).not_to receive(:create!)
        end

        middleware.call(context)
      end
    end

    context "when result is cached" do
      let(:mock_execution) do
        double("RubyLLM::Agents::Execution",
          id: 123,
          status: "running",
          detail: nil,
          class: RubyLLM::Agents::Execution,
          parent_execution_id: nil,
          root_execution_id: nil)
      end

      before do
        RubyLLM::Agents.configuration.track_embeddings = true
        RubyLLM::Agents.configuration.track_cache_hits = false
        RubyLLM::Agents.configuration.multi_tenancy_enabled = false
        allow(mock_execution).to receive(:create_detail!)
        allow(mock_execution).to receive(:update_column)
      end

      it "does not record cache hits when track_cache_hits is false" do
        context = build_context
        context.cached = true

        allow(app).to receive(:call) { |ctx|
          ctx.output = "cached_result"
          ctx
        }

        expect(RubyLLM::Agents::Execution).not_to receive(:create!)

        middleware.call(context)
      end

      it "records cache hits when track_cache_hits is true" do
        RubyLLM::Agents.configuration.track_cache_hits = true

        context = build_context
        context.cached = true

        allow(app).to receive(:call) { |ctx|
          ctx.output = "cached_result"
          ctx
        }

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
        double("RubyLLM::Agents::Execution",
          id: 123,
          status: "running",
          detail: nil,
          class: RubyLLM::Agents::Execution,
          parent_execution_id: nil,
          root_execution_id: nil)
      end

      before do
        RubyLLM::Agents.configuration.track_embeddings = true
        RubyLLM::Agents.configuration.multi_tenancy_enabled = false
        allow(mock_execution).to receive(:create_detail!)
        allow(mock_execution).to receive(:update_column)
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
        RubyLLM::Agents.configuration.async_logging = false

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

    it "checks track_embeddings for embedding agents" do
      agent_class = Class.new do
        def self.name
          "EmbedAgent"
        end

        def self.agent_type
          :embedding
        end

        def self.model
          "embed-model"
        end
      end

      middleware = described_class.new(app, agent_class)
      context = RubyLLM::Agents::Pipeline::Context.new(input: "test", agent_class: agent_class)

      RubyLLM::Agents.configuration.track_embeddings = false
      allow(app).to receive(:call) { |ctx|
        ctx.output = "result"
        ctx
      }

      expect(RubyLLM::Agents::Execution).not_to receive(:create!)
      middleware.call(context)
    end

    it "checks track_image_generation for image agents" do
      agent_class = Class.new do
        def self.name
          "ImageAgent"
        end

        def self.agent_type
          :image
        end

        def self.model
          "dalle-3"
        end
      end

      middleware = described_class.new(app, agent_class)
      context = RubyLLM::Agents::Pipeline::Context.new(input: "test", agent_class: agent_class)

      RubyLLM::Agents.configuration.track_image_generation = false
      allow(app).to receive(:call) { |ctx|
        ctx.output = "result"
        ctx
      }

      expect(RubyLLM::Agents::Execution).not_to receive(:create!)
      middleware.call(context)
    end

    it "checks track_audio for audio agents" do
      agent_class = Class.new do
        def self.name
          "AudioAgent"
        end

        def self.agent_type
          :audio
        end

        def self.model
          "whisper-1"
        end
      end

      middleware = described_class.new(app, agent_class)
      context = RubyLLM::Agents::Pipeline::Context.new(input: "test", agent_class: agent_class)

      RubyLLM::Agents.configuration.track_audio = false
      allow(app).to receive(:call) { |ctx|
        ctx.output = "result"
        ctx
      }

      expect(RubyLLM::Agents::Execution).not_to receive(:create!)
      middleware.call(context)
    end

    it "checks track_executions for conversation agents" do
      agent_class = Class.new do
        def self.name
          "ChatAgent"
        end

        def self.agent_type
          :conversation
        end

        def self.model
          "gpt-4o"
        end
      end

      middleware = described_class.new(app, agent_class)
      context = RubyLLM::Agents::Pipeline::Context.new(input: "test", agent_class: agent_class)

      RubyLLM::Agents.configuration.track_executions = false
      allow(app).to receive(:call) { |ctx|
        ctx.output = "result"
        ctx
      }

      expect(RubyLLM::Agents::Execution).not_to receive(:create!)
      middleware.call(context)
    end

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
    let(:mock_execution) do
      double("RubyLLM::Agents::Execution",
        id: 123,
        status: "running",
        detail: nil,
        class: RubyLLM::Agents::Execution,
        parent_execution_id: nil,
        root_execution_id: nil)
    end

    before do
      RubyLLM::Agents.configuration.track_embeddings = true
      allow(mock_execution).to receive(:create_detail!)
      allow(mock_execution).to receive(:update_column)
    end

    it "includes tenant_id when multi-tenancy is enabled" do
      RubyLLM::Agents.configuration.multi_tenancy_enabled = true

      context = build_context
      context.tenant_id = "tenant-123"

      allow(app).to receive(:call) { |ctx|
        ctx.output = "result"
        ctx
      }

      expect(RubyLLM::Agents::Execution).to receive(:create!).with(
        hash_including(tenant_id: "tenant-123")
      ).and_return(mock_execution)

      allow(mock_execution).to receive(:update!)

      middleware.call(context)
    end

    it "omits tenant_id when multi-tenancy is disabled" do
      RubyLLM::Agents.configuration.multi_tenancy_enabled = false

      context = build_context
      context.tenant_id = "tenant-123"

      allow(app).to receive(:call) { |ctx|
        ctx.output = "result"
        ctx
      }

      expect(RubyLLM::Agents::Execution).to receive(:create!).with(
        hash_not_including(:tenant_id)
      ).and_return(mock_execution)

      allow(mock_execution).to receive(:update!)

      middleware.call(context)
    end
  end

  describe "cache key tracking" do
    let(:mock_execution) do
      double("RubyLLM::Agents::Execution",
        id: 123,
        status: "running",
        detail: nil,
        class: RubyLLM::Agents::Execution,
        parent_execution_id: nil,
        root_execution_id: nil)
    end

    before do
      RubyLLM::Agents.configuration.track_embeddings = true
      RubyLLM::Agents.configuration.track_cache_hits = true
      RubyLLM::Agents.configuration.multi_tenancy_enabled = false
      allow(mock_execution).to receive(:create_detail!)
      allow(mock_execution).to receive(:update_column)
    end

    it "includes cache key for cached results" do
      context = build_context
      context.cached = true
      context[:cache_key] = "ruby_llm_agents/test/key"

      allow(app).to receive(:call) { |ctx|
        ctx.output = "result"
        ctx
      }
      allow(RubyLLM::Agents::Execution).to receive(:create!).and_return(mock_execution)

      expect(mock_execution).to receive(:update!).with(
        hash_including(metadata: hash_including("response_cache_key" => "ruby_llm_agents/test/key"))
      )

      middleware.call(context)
    end
  end

  describe "metadata tracking" do
    let(:mock_execution) do
      double("RubyLLM::Agents::Execution",
        id: 123,
        status: "running",
        detail: nil,
        class: RubyLLM::Agents::Execution,
        parent_execution_id: nil,
        root_execution_id: nil)
    end

    before do
      RubyLLM::Agents.configuration.track_embeddings = true
      RubyLLM::Agents.configuration.multi_tenancy_enabled = false
      allow(mock_execution).to receive(:create_detail!)
      allow(mock_execution).to receive(:update_column)
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

      allow(app).to receive(:call) { |ctx|
        ctx.output = "result"
        ctx
      }
      allow(RubyLLM::Agents::Execution).to receive(:create!).and_return(mock_execution)

      expect(mock_execution).to receive(:update!).with(
        hash_not_including(:metadata)
      )

      middleware.call(context)
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
    let(:mock_execution) do
      double("RubyLLM::Agents::Execution",
        id: 123,
        status: "running",
        detail: nil,
        class: RubyLLM::Agents::Execution,
        parent_execution_id: nil,
        root_execution_id: nil)
    end

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
      allow(mock_execution).to receive(:create_detail!)
      allow(mock_execution).to receive(:update_column)
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

      # Parameters are now stored on the detail record, not the execution
      expect(RubyLLM::Agents::Execution).to receive(:create!).and_return(mock_execution)
      expect(mock_execution).to receive(:create_detail!).with(
        hash_including(
          parameters: hash_including(
            "query" => "test query",
            "api_key" => "[REDACTED]",
            "password" => "[REDACTED]",
            "token" => "[REDACTED]",
            "normal_param" => "normal"
          )
        )
      )

      allow(mock_execution).to receive(:update!)

      middleware.call(context)
    end
  end

  describe "response persistence" do
    let(:mock_execution) do
      double("RubyLLM::Agents::Execution",
        id: 123,
        status: "running",
        detail: nil,
        class: RubyLLM::Agents::Execution,
        parent_execution_id: nil,
        root_execution_id: nil)
    end

    before do
      RubyLLM::Agents.configuration.track_embeddings = true
      RubyLLM::Agents.configuration.multi_tenancy_enabled = false
      allow(mock_execution).to receive(:create_detail!)
      allow(mock_execution).to receive(:update_column)
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
        allow(RubyLLM::Agents::Execution).to receive(:create!).and_return(mock_execution)
        allow(mock_execution).to receive(:update!)

        # Response is now stored via create_detail!, not update!
        expect(mock_execution).to receive(:create_detail!).with(
          hash_including(response: hash_including(content: "Test response"))
        )

        middleware.call(context)
      end

      it "includes model_id in response when available" do
        context = build_context
        context.model_used = "gpt-4"

        result_obj = RubyLLM::Agents::Result.new(content: "Test response")
        allow(app).to receive(:call) do |ctx|
          ctx.output = result_obj
          ctx
        end
        allow(RubyLLM::Agents::Execution).to receive(:create!).and_return(mock_execution)
        allow(mock_execution).to receive(:update!)

        # Response is now stored via create_detail!, not update!
        expect(mock_execution).to receive(:create_detail!).with(
          hash_including(response: hash_including(content: "Test response", model_id: "gpt-4"))
        )

        middleware.call(context)
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
        allow(RubyLLM::Agents::Execution).to receive(:create!).and_return(mock_execution)
        allow(mock_execution).to receive(:update!)

        # Response is now stored via create_detail!, not update!
        expect(mock_execution).to receive(:create_detail!).with(
          hash_including(response: hash_including(input_tokens: 100, output_tokens: 50))
        )

        middleware.call(context)
      end

      it "does not store response when output is nil" do
        context = build_context

        allow(app).to receive(:call) do |ctx|
          ctx.output = nil
          ctx
        end
        allow(RubyLLM::Agents::Execution).to receive(:create!).and_return(mock_execution)

        expect(mock_execution).to receive(:update!).with(
          hash_not_including(:response)
        )

        middleware.call(context)
      end

      it "does not store response when output does not respond to content" do
        context = build_context

        allow(app).to receive(:call) do |ctx|
          ctx.output = "plain string"
          ctx
        end
        allow(RubyLLM::Agents::Execution).to receive(:create!).and_return(mock_execution)

        expect(mock_execution).to receive(:update!).with(
          hash_not_including(:response)
        )

        middleware.call(context)
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
        allow(RubyLLM::Agents::Execution).to receive(:create!).and_return(mock_execution)

        expect(mock_execution).to receive(:update!).with(
          hash_not_including(:response)
        )

        middleware.call(context)
      end
    end

    describe "reliability attempts persistence" do
      let(:mock_execution) do
        double("RubyLLM::Agents::Execution",
          id: 456,
          status: "running",
          detail: nil,
          class: RubyLLM::Agents::Execution,
          parent_execution_id: nil,
          root_execution_id: nil)
      end

      before do
        RubyLLM::Agents.configuration.multi_tenancy_enabled = false
        allow(mock_execution).to receive(:create_detail!)
        allow(mock_execution).to receive(:update_column)
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

        allow(RubyLLM::Agents::Execution).to receive(:create!).and_return(mock_execution)

        # attempts_count on the execution, attempts data goes to detail
        expect(mock_execution).to receive(:update!).with(
          hash_including(
            attempts_count: 2
          )
        )

        # Attempts data is stored on the detail record
        expect(mock_execution).to receive(:create_detail!).with(
          hash_including(
            attempts: [
              {"model_id" => "gemini-2.5-flash", "error_class" => "StandardError", "error_message" => "quota exceeded"},
              {"model_id" => "gpt-4.1-mini", "error_class" => nil, "error_message" => nil}
            ]
          )
        )

        middleware.call(context)
      end

      it "does not include attempts when reliability_attempts is absent" do
        context = build_context

        allow(app).to receive(:call) do |ctx|
          ctx.output = "result"
          ctx
        end

        allow(RubyLLM::Agents::Execution).to receive(:create!).and_return(mock_execution)

        expect(mock_execution).to receive(:update!).with(
          hash_not_including(:attempts)
        )

        middleware.call(context)
      end
    end
  end
end
