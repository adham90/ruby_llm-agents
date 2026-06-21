# frozen_string_literal: true

require "rails_helper"
require "ostruct"

# Coverage-focused specs for the less-traveled branches of the Instrumentation
# middleware. Everything is driven through the REAL middleware
# (RubyLLM::Agents::Pipeline::Middleware::Instrumentation) with a lambda `app`
# and a real Pipeline::Context, mirroring instrumentation_spec.rb. The only
# things faked are the external boundaries (the LLM "app" lambda, and constant
# visibility for the AS::Notifications absence branch).
RSpec.describe RubyLLM::Agents::Pipeline::Middleware::Instrumentation, type: :model do
  # A real, minimal agent class. agent_type is configurable per example so we
  # can hit every branch of tracking_enabled?.
  def build_agent_class(name:, agent_type: :embedding, model: "test-model")
    Class.new do
      define_singleton_method(:name) { name }
      define_singleton_method(:agent_type) { agent_type }
      define_singleton_method(:model) { model }
    end
  end

  let(:agent_class) { build_agent_class(name: "CoverageAgent") }

  def build_context(klass = agent_class, **options)
    RubyLLM::Agents::Pipeline::Context.new(input: "test", agent_class: klass, **options)
  end

  def build_middleware(app, klass = agent_class)
    described_class.new(app, klass)
  end

  # A pass-through "app" that sets an output, like a real downstream pipeline.
  let(:passthrough_app) do
    lambda do |ctx|
      ctx.output = RubyLLM::Agents::Result.new(content: "ok")
      ctx
    end
  end

  before do
    RubyLLM::Agents.reset_configuration!
    RubyLLM::Agents.configure do |c|
      c.track_executions = true
      c.track_embeddings = true
      c.track_image_generation = true
      c.track_audio = true
      c.async_logging = false
      c.persist_prompts = true
      c.persist_responses = true
      c.multi_tenancy_enabled = false
    end
  end

  after do
    RubyLLM::Agents.reset_configuration!
  end

  # ---------------------------------------------------------------------------
  # capture_llm_requests: the three branches called out in the task.
  # ---------------------------------------------------------------------------
  describe "#capture_llm_requests" do
    let(:middleware) { build_middleware(->(ctx) { ctx }) }

    def emit_request
      ActiveSupport::Notifications.instrument("request.ruby_llm", provider: "openai") { :ok }
    end

    it "early-returns (yields) without subscribing when AS::Notifications is undefined" do
      context = build_context
      yielded = false

      # Temporarily remove the AS::Notifications constant *only* for the duration
      # of this single method call, restoring it immediately in an ensure so it
      # is back in place before any RSpec/DatabaseCleaner teardown runs (which
      # itself relies on AS::Notifications). This manipulates constant
      # visibility, not any internal gem class. It drives the
      # `return yield unless defined?(ActiveSupport::Notifications)` branch.
      saved = ActiveSupport.send(:remove_const, :Notifications)
      result =
        begin
          middleware.send(:capture_llm_requests, context) do
            yielded = true
            :downstream_value
          end
        ensure
          ActiveSupport.const_set(:Notifications, saved)
        end

      expect(yielded).to be(true)
      expect(result).to eq(:downstream_value)
      # No accumulator was created, so no request metrics are recorded.
      expect(context[:llm_request_count]).to be_nil
      expect(context[:llm_request_ms]).to be_nil
    end

    it "attributes nested requests to the innermost accumulator only" do
      outer = build_context
      inner = build_context

      middleware.send(:capture_llm_requests, outer) do
        emit_request # outer
        middleware.send(:capture_llm_requests, inner) do
          emit_request # inner only
          emit_request # inner only
        end
        emit_request # outer again
      end

      expect(outer[:llm_request_count]).to eq(2)
      expect(inner[:llm_request_count]).to eq(2)
    end

    it "still records request metrics in the ensure block when the block raises" do
      context = build_context

      expect {
        middleware.send(:capture_llm_requests, context) do
          emit_request
          raise "boom"
        end
      }.to raise_error("boom")

      expect(context[:llm_request_count]).to eq(1)
      expect(context[:llm_request_ms]).to be >= 0
    end

    it "records nothing when no request.ruby_llm events fire" do
      context = build_context

      middleware.send(:capture_llm_requests, context) { :no_requests }

      expect(context[:llm_request_count]).to be_nil
    end
  end

  # ---------------------------------------------------------------------------
  # tracking_enabled? per agent type (the case statement + rescue).
  # ---------------------------------------------------------------------------
  describe "#tracking_enabled? per agent type" do
    {
      embedding: {flag: :track_embeddings, model: "text-embedding-3-small"},
      image: {flag: :track_image_generation, model: "dall-e-3"},
      audio: {flag: :track_audio, model: "tts-1"},
      conversation: {flag: :track_executions, model: "gpt-4o"}
    }.each do |type, info|
      it "uses #{info[:flag]} for #{type} agents (records when enabled)" do
        klass = build_agent_class(name: "Agent#{type}", agent_type: type, model: info[:model])
        context = build_context(klass)

        expect { build_middleware(passthrough_app, klass).call(context) }
          .to change(RubyLLM::Agents::Execution, :count).by(1)
      end

      it "uses #{info[:flag]} for #{type} agents (skips when disabled)" do
        RubyLLM::Agents.configuration.public_send("#{info[:flag]}=", false)
        klass = build_agent_class(name: "Agent#{type}", agent_type: type, model: info[:model])
        context = build_context(klass)

        expect { build_middleware(passthrough_app, klass).call(context) }
          .not_to change(RubyLLM::Agents::Execution, :count)
      end
    end

    it "falls back to false (skips tracking) when reading config raises" do
      context = build_context

      allow(RubyLLM::Agents).to receive(:configuration).and_raise(StandardError, "config boom")

      expect { build_middleware(passthrough_app).call(context) }.not_to raise_error
    end
  end

  # ---------------------------------------------------------------------------
  # build_running_execution_data: replay source + context-level hierarchy.
  # ---------------------------------------------------------------------------
  describe "replay source + execution hierarchy in the running record" do
    it "stores replay_source_id in metadata when the agent options carry it" do
      replay_agent = Class.new do
        def self.name = "ReplayAgent"
        def self.agent_type = :embedding
        def self.model = "test-model"

        def options
          {_replay_source_id: 4242}
        end
      end

      instance = replay_agent.new
      context = build_context(replay_agent, agent_instance: instance)

      build_middleware(passthrough_app, replay_agent).call(context)

      execution = RubyLLM::Agents::Execution.last
      expect(execution.metadata["replay_source_id"]).to eq("4242")
    end

    it "uses context-level parent/root execution ids (agent-as-tool path)" do
      parent = RubyLLM::Agents::Execution.create!(
        agent_type: "ParentAgent", model_id: "test-model",
        started_at: Time.current, status: "success"
      )

      context = build_context(parent_execution_id: parent.id)

      build_middleware(passthrough_app).call(context)

      child = RubyLLM::Agents::Execution.where(agent_type: "CoverageAgent").last
      expect(child.parent_execution_id).to eq(parent.id)
      # root defaults to parent_execution_id when no explicit root given
      expect(child.root_execution_id).to eq(parent.id)
    end
  end

  # ---------------------------------------------------------------------------
  # mark_execution_failed!: emergency path. Drive it directly with a REAL
  # running Execution that has no detail record, so the create! branch fires.
  # ---------------------------------------------------------------------------
  describe "#mark_execution_failed! emergency path" do
    let(:middleware) { build_middleware(->(ctx) { ctx }) }

    it "creates a new ExecutionDetail with the error message when none exists" do
      execution = RubyLLM::Agents::Execution.create!(
        agent_type: "CoverageAgent", model_id: "test-model",
        started_at: Time.current, status: "running"
      )
      expect(execution.detail).to be_nil

      error = RuntimeError.new("fatal failure")
      error.set_backtrace(["/app/foo.rb:1:in `bar'"])

      middleware.send(:mark_execution_failed!, execution, error: error)

      execution.reload
      expect(execution.status).to eq("error")
      expect(execution.error_class).to eq("RuntimeError")
      expect(execution.detail).to be_present
      expect(execution.detail.error_message).to include("RuntimeError: fatal failure")
    end

    it "updates the existing ExecutionDetail when one is already present" do
      execution = RubyLLM::Agents::Execution.create!(
        agent_type: "CoverageAgent", model_id: "test-model",
        started_at: Time.current, status: "running"
      )
      execution.create_detail!(parameters: {"q" => "v"})

      middleware.send(:mark_execution_failed!, execution, error: StandardError.new("late boom"))

      execution.reload
      expect(execution.status).to eq("error")
      expect(execution.detail.error_message).to include("StandardError: late boom")
      expect(execution.detail.parameters).to eq("q" => "v")
    end

    it "uses 'Unknown error' and UnknownError class when error is nil" do
      execution = RubyLLM::Agents::Execution.create!(
        agent_type: "CoverageAgent", model_id: "test-model",
        started_at: Time.current, status: "running"
      )

      middleware.send(:mark_execution_failed!, execution, error: nil)

      execution.reload
      expect(execution.status).to eq("error")
      expect(execution.error_class).to eq("UnknownError")
      expect(execution.detail.error_message).to eq("Unknown error")
    end

    it "is a no-op for a record that is not running" do
      execution = RubyLLM::Agents::Execution.create!(
        agent_type: "CoverageAgent", model_id: "test-model",
        started_at: Time.current, completed_at: Time.current, status: "success"
      )

      expect {
        middleware.send(:mark_execution_failed!, execution, error: StandardError.new("x"))
      }.not_to change { execution.reload.status }
    end

    it "is a no-op when execution is nil" do
      expect { middleware.send(:mark_execution_failed!, nil, error: StandardError.new("x")) }
        .not_to raise_error
    end

    it "swallows a failure while storing the error detail (inner rescue)" do
      execution = RubyLLM::Agents::Execution.create!(
        agent_type: "CoverageAgent", model_id: "test-model",
        started_at: Time.current, status: "running"
      )

      # The status update_all succeeds; only the best-effort detail store fails.
      # We fail the detail-table boundary (ExecutionDetail.create!), not the
      # middleware under test.
      allow(RubyLLM::Agents::ExecutionDetail)
        .to receive(:create!).and_raise(StandardError, "detail store boom")

      expect {
        middleware.send(:mark_execution_failed!, execution, error: StandardError.new("boom"))
      }.not_to raise_error

      # Status was still flipped to error via update_all.
      expect(execution.reload.status).to eq("error")
    end

    it "swallows a failure of the emergency status update itself (outer rescue)" do
      execution = RubyLLM::Agents::Execution.create!(
        agent_type: "CoverageAgent", model_id: "test-model",
        started_at: Time.current, status: "running"
      )

      # Simulate the DB write boundary failing: update_all raises. This is the
      # data-store boundary, the analog of an LLM/network failure.
      relation = RubyLLM::Agents::Execution.where(id: execution.id, status: "running")
      allow(RubyLLM::Agents::Execution).to receive(:where).and_return(relation)
      allow(relation).to receive(:update_all).and_raise(StandardError, "db write boom")

      expect {
        middleware.send(:mark_execution_failed!, execution, error: StandardError.new("boom"))
      }.not_to raise_error
    end
  end

  # ---------------------------------------------------------------------------
  # build_running_execution_data: replay_source_id rescue when options raises.
  # ---------------------------------------------------------------------------
  describe "replay_source_id extraction rescue" do
    it "swallows an exception raised while reading replay source from options" do
      exploding_options_agent = Class.new do
        def self.name = "ExplodingOptionsAgent"
        def self.agent_type = :embedding
        def self.model = "test-model"

        # respond_to?(:options, true) is true, but calling it raises — this
        # drives both the sanitize rescue AND the replay-source rescue.
        def options
          raise "options boom"
        end
      end

      instance = exploding_options_agent.new
      context = build_context(exploding_options_agent, agent_instance: instance)

      # Execution proceeds and is recorded despite options blowing up.
      expect { build_middleware(passthrough_app, exploding_options_agent).call(context) }
        .to change(RubyLLM::Agents::Execution, :count).by(1)

      execution = RubyLLM::Agents::Execution.last
      expect(execution.metadata).not_to include("replay_source_id")
    end
  end

  # ---------------------------------------------------------------------------
  # build_error_message: backtrace formatting path.
  # ---------------------------------------------------------------------------
  describe "#build_error_message" do
    let(:middleware) { build_middleware(->(ctx) { ctx }) }

    it "returns 'Unknown error' for nil" do
      expect(middleware.send(:build_error_message, nil)).to eq("Unknown error")
    end

    it "includes class, message, and capped backtrace frames" do
      error = StandardError.new("kaboom")
      error.set_backtrace((1..20).map { |i| "/app/file#{i}.rb:#{i}:in `m#{i}'" })

      message = middleware.send(:build_error_message, error)

      expect(message).to start_with("StandardError: kaboom")
      expect(message).to include("Backtrace (first 10 frames):")
      expect(message).to include("/app/file1.rb")
      expect(message).to include("/app/file10.rb")
      # Only the first 10 frames are kept.
      expect(message).not_to include("/app/file11.rb")
    end

    it "omits the backtrace section when there is no backtrace" do
      error = StandardError.new("no trace")
      message = middleware.send(:build_error_message, error)

      expect(message).to eq("StandardError: no trace")
    end
  end

  # ---------------------------------------------------------------------------
  # truncate_error_message
  # ---------------------------------------------------------------------------
  describe "#truncate_error_message" do
    let(:middleware) { build_middleware(->(ctx) { ctx }) }

    it "returns empty string for nil" do
      expect(middleware.send(:truncate_error_message, nil)).to eq("")
    end

    it "truncates long messages to 5000 chars" do
      result = middleware.send(:truncate_error_message, "x" * 6000)
      expect(result.length).to be <= 5000
    end

    it "passes through short messages" do
      expect(middleware.send(:truncate_error_message, "short")).to eq("short")
    end

    it "falls back to a hard substring when truncate raises (rescue path)" do
      # A real String subclass instance whose #truncate blows up but whose [] still
      # works. We wrap it in an object whose #to_s returns *that same instance*, so
      # `message.to_s.truncate(5000)` invokes the failing override (driving the
      # rescue), while the fallback `message.to_s[0, 1000]` still succeeds.
      angry_string = Class.new(String) do
        def truncate(*)
          raise "truncate boom"
        end

        # Keep to_s returning self (the subclass) instead of a plain String copy.
        def to_s
          self
        end
      end.new("y" * 2000)

      wrapper = Object.new
      wrapper.define_singleton_method(:to_s) { angry_string }

      result = middleware.send(:truncate_error_message, wrapper)

      expect(result.length).to eq(1000)
      expect(result).to start_with("yyy")
    end
  end

  # ---------------------------------------------------------------------------
  # serialize_response
  # ---------------------------------------------------------------------------
  describe "#serialize_response" do
    let(:middleware) { build_middleware(->(ctx) { ctx }) }

    it "returns nil when there is no output" do
      context = build_context
      expect(middleware.send(:serialize_response, context)).to be_nil
    end

    it "returns nil when output content is nil" do
      context = build_context
      context.output = RubyLLM::Agents::Result.new(content: nil)
      expect(middleware.send(:serialize_response, context)).to be_nil
    end

    it "builds a response hash with content, model_id, and token counts" do
      context = build_context
      context.output = RubyLLM::Agents::Result.new(content: "hello")
      context.model_used = "gpt-4o"
      context.input_tokens = 11
      context.output_tokens = 7

      data = middleware.send(:serialize_response, context)

      expect(data).to include(content: "hello", model_id: "gpt-4o", input_tokens: 11, output_tokens: 7)
    end

    it "returns nil and logs when content access raises" do
      context = build_context
      # A real object whose #content blows up — exercises the rescue path.
      exploding = Object.new
      def exploding.content
        raise "content boom"
      end
      context.output = exploding

      expect(middleware.send(:serialize_response, context)).to be_nil
    end
  end

  # ---------------------------------------------------------------------------
  # save_execution_details: assistant_prompt + rescue path through the
  # full middleware run (persist_prompts on).
  # ---------------------------------------------------------------------------
  describe "save_execution_details (prompts + assistant prefill)" do
    let(:prompt_agent) do
      Class.new do
        def self.name = "PromptAgent"
        def self.agent_type = :conversation
        def self.model = "gpt-4o"
      end
    end

    it "persists system/user/assistant prompts when persist_prompts is enabled" do
      context = RubyLLM::Agents::Pipeline::Context.new(
        input: "the user message",
        agent_class: prompt_agent,
        options: {system_prompt: "you are helpful", assistant_prefill: "Sure,"}
      )

      build_middleware(passthrough_app, prompt_agent).call(context)

      detail = RubyLLM::Agents::Execution.last.detail
      expect(detail.system_prompt).to eq("you are helpful")
      expect(detail.user_prompt).to eq("the user message")
      # assistant_prompt column exists in the dummy schema, so it is persisted.
      expect(detail.assistant_prompt).to eq("Sure,")
    end

    it "does not raise when saving details fails (rescue path)" do
      context = RubyLLM::Agents::Pipeline::Context.new(
        input: "msg", agent_class: prompt_agent,
        options: {system_prompt: "sys"}
      )

      mw = build_middleware(passthrough_app, prompt_agent)

      # The running record is created first; force the *detail* save to fail by
      # making create_detail!/update! raise on the persisted execution. We do
      # this by stubbing the detail-save boundary on ExecutionDetail, not on the
      # middleware under test.
      allow_any_instance_of(RubyLLM::Agents::Execution)
        .to receive(:create_detail!).and_raise(StandardError, "detail boom")
      allow_any_instance_of(RubyLLM::Agents::ExecutionDetail)
        .to receive(:update!).and_raise(StandardError, "detail boom")

      expect { mw.call(context) }.not_to raise_error

      execution = RubyLLM::Agents::Execution.last
      expect(execution.status).to eq("success")
    end
  end

  describe "#assistant_prompt_column_exists?" do
    let(:middleware) { build_middleware(->(ctx) { ctx }) }

    it "returns true for the dummy schema and memoizes the result" do
      expect(middleware.send(:assistant_prompt_column_exists?)).to be(true)
      # Second call hits the memoized branch.
      expect(middleware.send(:assistant_prompt_column_exists?)).to be(true)
    end

    it "returns false (and does not raise) when the schema query blows up" do
      fresh = build_middleware(->(ctx) { ctx })

      # Fail the schema-introspection boundary. column_names is the DB schema
      # query; failing it drives the rescue branch.
      allow(RubyLLM::Agents::ExecutionDetail)
        .to receive(:column_names).and_raise(StandardError, "no schema")

      expect(fresh.send(:assistant_prompt_column_exists?)).to be(false)
    end
  end

  # ---------------------------------------------------------------------------
  # sanitize_parameters: rescue when options raises.
  # ---------------------------------------------------------------------------
  describe "#sanitize_parameters rescue" do
    let(:middleware) { build_middleware(->(ctx) { ctx }) }

    it "returns {} when the agent's options method raises" do
      bad_agent = Object.new
      def bad_agent.options
        raise "no options for you"
      end

      context = build_context(agent_instance: bad_agent)

      expect(middleware.send(:sanitize_parameters, context)).to eq({})
    end

    it "returns {} when the agent does not respond to options" do
      context = build_context(agent_instance: Object.new)
      expect(middleware.send(:sanitize_parameters, context)).to eq({})
    end
  end

  # ---------------------------------------------------------------------------
  # persist_execution legacy fallback: queue_async_logging vs sync create.
  # We force the legacy path by making the *initial* running-record create
  # return nil (raise once), so complete_execution falls back to
  # persist_execution.
  # ---------------------------------------------------------------------------
  describe "legacy persistence fallback (running record was nil)" do
    def force_running_record_failure
      first = true
      allow(RubyLLM::Agents::Execution).to receive(:create!).and_wrap_original do |orig, *args|
        if first
          first = false
          raise StandardError, "initial create failed"
        end
        orig.call(*args)
      end
    end

    # NOTE: async_logging? guards on `defined?(Infrastructure::ExecutionLoggerJob)`,
    # which never resolves (there is no Infrastructure module in this namespace),
    # so the queue_async_logging branch is currently unreachable dead code. We do
    # not fabricate that constant to force it, since that would not exercise a
    # real production path. The legacy fallback therefore always takes the
    # synchronous create_execution_record branch, covered below.
    it "creates the record synchronously (with detail) even when async_logging is enabled" do
      RubyLLM::Agents.configuration.async_logging = true
      force_running_record_failure

      context = build_context
      context.input_tokens = 100
      context.output_tokens = 50

      build_middleware(passthrough_app).call(context)

      execution = RubyLLM::Agents::Execution.where(agent_type: "CoverageAgent").last
      expect(execution).to be_present
      expect(execution.status).to eq("success")
    end

    it "creates the record synchronously (with detail) when async_logging is disabled" do
      RubyLLM::Agents.configuration.async_logging = false
      force_running_record_failure

      context = build_context
      context.input_tokens = 100
      context.output_tokens = 50

      build_middleware(passthrough_app).call(context)

      execution = RubyLLM::Agents::Execution.where(agent_type: "CoverageAgent").last
      expect(execution).to be_present
      expect(execution.status).to eq("success")
      # create_execution_record builds a detail record from _detail_data.
      expect(execution.detail).to be_present
    end

    it "marks the legacy record as timeout for a Timeout::Error" do
      RubyLLM::Agents.configuration.async_logging = false
      force_running_record_failure

      timeout_app = ->(_ctx) { raise Timeout::Error, "slow" }
      context = build_context

      expect { build_middleware(timeout_app).call(context) }.to raise_error(Timeout::Error)

      execution = RubyLLM::Agents::Execution.where(agent_type: "CoverageAgent").last
      expect(execution).to be_present
      expect(execution.status).to eq("timeout")
    end
  end

  describe "#async_logging?" do
    let(:middleware) { build_middleware(->(ctx) { ctx }) }

    it "returns false (and does not raise) when config reading blows up" do
      allow(RubyLLM::Agents).to receive(:configuration).and_raise(StandardError, "boom")
      expect(middleware.send(:async_logging?)).to be(false)
    end
  end

  describe "#track_cache_hits?" do
    let(:middleware) { build_middleware(->(ctx) { ctx }) }

    it "returns false (and does not raise) when config reading blows up" do
      allow(RubyLLM::Agents).to receive(:configuration).and_raise(StandardError, "boom")
      expect(middleware.send(:track_cache_hits?)).to be(false)
    end
  end

  # ---------------------------------------------------------------------------
  # Audio persistence: maybe_persist_audio_response.
  # ---------------------------------------------------------------------------
  describe "audio persistence" do
    let(:speaker_agent) do
      Class.new do
        def self.name = "SpeakerAgent"
        def self.agent_type = :audio
        def self.model = "tts-1"
      end
    end

    def build_speech_result(**overrides)
      RubyLLM::Agents::SpeechResult.new({
        audio: "RAWAUDIOBYTES",
        audio_url: "https://cdn.example.com/audio.mp3",
        format: :mp3,
        duration: 1.5,
        file_size: 13,
        voice_id: "alloy",
        provider: :openai
      }.merge(overrides))
    end

    it "always persists audio_url (no binary) when persist_audio_data is off" do
      RubyLLM::Agents.configuration.persist_audio_data = false

      app = ->(ctx) {
        ctx.output = build_speech_result
        ctx
      }
      context = RubyLLM::Agents::Pipeline::Context.new(input: "say hi", agent_class: speaker_agent)

      build_middleware(app, speaker_agent).call(context)

      detail = RubyLLM::Agents::Execution.last.detail
      expect(detail.response["audio_url"]).to eq("https://cdn.example.com/audio.mp3")
      # No data URI persisted when opted out.
      expect(detail.response).not_to have_key("audio_data_uri")
    end

    it "persists the full audio data URI when persist_audio_data is on" do
      RubyLLM::Agents.configuration.persist_audio_data = true

      app = ->(ctx) {
        ctx.output = build_speech_result
        ctx
      }
      context = RubyLLM::Agents::Pipeline::Context.new(input: "say hi", agent_class: speaker_agent)

      build_middleware(app, speaker_agent).call(context)

      detail = RubyLLM::Agents::Execution.last.detail
      expect(detail.response["audio_data_uri"]).to start_with("data:audio/mpeg;base64,")
      expect(detail.response["format"]).to eq("mp3")
      expect(detail.response["voice_id"]).to eq("alloy")
      expect(detail.response["provider"]).to eq("openai")
    end

    it "does not raise when audio persistence blows up (rescue path)" do
      RubyLLM::Agents.configuration.persist_audio_data = true

      middleware = build_middleware(->(ctx) { ctx }, speaker_agent)

      # A SpeechResult whose to_data_uri raises — exercises the rescue in
      # maybe_persist_audio_response without touching the middleware internals.
      result = build_speech_result
      def result.to_data_uri
        raise "encode boom"
      end

      detail_data = {}
      context = RubyLLM::Agents::Pipeline::Context.new(input: "x", agent_class: speaker_agent)
      context.output = result

      expect {
        middleware.send(:maybe_persist_audio_response, context, detail_data)
      }.not_to raise_error
    end

    it "ignores non-speech outputs" do
      middleware = build_middleware(->(ctx) { ctx }, speaker_agent)
      detail_data = {response: {content: "text"}}
      context = RubyLLM::Agents::Pipeline::Context.new(input: "x", agent_class: speaker_agent)
      context.output = RubyLLM::Agents::Result.new(content: "text")

      middleware.send(:maybe_persist_audio_response, context, detail_data)

      expect(detail_data).to eq(response: {content: "text"})
    end
  end

  # ---------------------------------------------------------------------------
  # build_completion_data: rescue when context metadata read raises.
  # ---------------------------------------------------------------------------
  describe "#build_completion_data metadata rescue" do
    let(:middleware) { build_middleware(->(ctx) { ctx }) }

    it "swallows a failing context.metadata read and still returns valid data" do
      context = build_context
      context.completed_at = Time.current
      context.started_at = Time.current

      # Make the real context's metadata accessor raise once during the build.
      allow(context).to receive(:metadata).and_raise(StandardError, "metadata boom")

      data = middleware.send(:build_completion_data, context, "success")

      expect(data[:status]).to eq("success")
      # No crash; metadata could not be merged from context but build succeeded.
      expect(data).to be_a(Hash)
    end
  end

  # ---------------------------------------------------------------------------
  # emit_start_notification / emit_complete_notification rescue branches.
  # These should never break execution even if instrumentation throws.
  # ---------------------------------------------------------------------------
  describe "notification rescue branches" do
    let(:middleware) { build_middleware(->(ctx) { ctx }) }

    it "swallows errors raised while emitting the start notification" do
      context = build_context

      allow(ActiveSupport::Notifications).to receive(:instrument).and_raise(StandardError, "notif boom")

      expect { middleware.send(:emit_start_notification, context) }.not_to raise_error
    end

    it "swallows errors raised while emitting the complete notification" do
      context = build_context

      allow(ActiveSupport::Notifications).to receive(:instrument).and_raise(StandardError, "notif boom")

      expect { middleware.send(:emit_complete_notification, context, "success") }.not_to raise_error
    end
  end
end
