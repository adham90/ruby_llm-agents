# frozen_string_literal: true

require "rails_helper"

# Coverage-focused specs for the less-trodden branches of BaseAgent.
#
# These exercise real code paths: real RubyLLM::Message objects, real
# RubyLLM::Models pricing, and real Pipeline::Context. The only thing faked is
# the LLM network boundary (RubyLLM::Chat#ask/#complete via a stubbed
# RubyLLM.chat), which the testing rules explicitly permit.
RSpec.describe RubyLLM::Agents::BaseAgent, "uncovered branches", type: :model do
  # A minimal agent that can build a client and resolve prompts.
  let(:agent_class) do
    Class.new(described_class) do
      def self.name
        "CoverageTestAgent"
      end

      model "gpt-4o"
      system "You are a test agent."
      user "Say hi"
    end
  end

  # Bare instance with an empty options hash — lets us drive private methods
  # directly without running the whole pipeline (mirrors base_agent_cost_spec).
  # @tracked_tool_calls mirrors what #initialize sets so capture_response works.
  let(:agent) do
    agent_class.allocate.tap do |a|
      a.instance_variable_set(:@options, {})
      a.instance_variable_set(:@tracked_tool_calls, [])
      a.instance_variable_set(:@model, agent_class.model)
    end
  end

  def new_context(klass: agent_class, instance: agent)
    RubyLLM::Agents::Pipeline::Context.new(
      input: "hi",
      agent_class: klass,
      agent_instance: instance
    )
  end

  # --- stream class method (lines 77-79) --------------------------------------

  describe ".stream" do
    it "raises ArgumentError without a block" do
      expect { agent_class.stream(foo: 1) }.to raise_error(ArgumentError, /Block required/)
    end

    it "sets @force_streaming on the instance and calls it" do
      captured = nil
      # Stub the LLM boundary: a client whose ask streams one chunk.
      chunk = RubyLLM::Message.new(role: :assistant, content: "hi", model_id: "gpt-4o")
      client = build_mock_chat_client
      allow(client).to receive(:ask) do |_prompt, **_opts, &blk|
        blk&.call(chunk)
        RubyLLM::Message.new(role: :assistant, content: "hi", model_id: "gpt-4o",
          input_tokens: 5, output_tokens: 2)
      end
      stub_ruby_llm_chat(client)
      stub_agent_configuration(track_executions: false)

      agent_class.stream(foo: 1) { |c| captured = c }

      expect(captured).to eq(chunk)
    end
  end

  # --- thinking_config / default_streaming / default_temperature rescue -------
  # (lines 330, 340, 346)

  describe "configuration fallbacks when configuration access raises" do
    before do
      # Replace configuration with an object that raises on the reads these
      # methods perform, exercising the rescue branches.
      @real = RubyLLM::Agents.instance_variable_get(:@configuration)
      raising = Object.new
      def raising.default_thinking = raise("boom")
      def raising.default_streaming = raise("boom")
      def raising.default_temperature = raise("boom")
      RubyLLM::Agents.instance_variable_set(:@configuration, raising)
    end

    after do
      RubyLLM::Agents.instance_variable_set(:@configuration, @real)
    end

    it "thinking_config rescues to nil" do
      bare = Class.new(described_class) { def self.name = "ThinkingBare" }
      expect(bare.thinking_config).to be_nil
    end

    it "default_streaming rescues to false" do
      bare = Class.new(described_class) { def self.name = "StreamingBare" }
      expect(bare.streaming).to be(false)
    end

    it "default_temperature rescues to 0.7" do
      bare = Class.new(described_class) { def self.name = "TempBare" }
      expect(bare.temperature).to eq(0.7)
    end
  end

  # --- tool_description_for (lines 597-602) -----------------------------------

  describe "#tool_description_for" do
    it "uses .description when the class exposes one" do
      tool = Class.new do
        def self.description = "A described tool"
        def self.name = "DescribedTool"
      end
      expect(agent.send(:tool_description_for, tool)).to eq("A described tool")
    end

    it "instantiates a RubyLLM::Tool subclass to read its instance description" do
      # No class-level description set -> tool.description is nil, so the first
      # branch is skipped and the RubyLLM::Tool branch instantiates to read the
      # instance description (also nil here, which is returned as-is).
      tool = Class.new(RubyLLM::Tool) do
        def self.name = "InstanceDescribedTool"
      end
      expect(tool.description).to be_nil
      expect(agent.send(:tool_description_for, tool)).to be_nil
    end

    it "falls back to the tool name when no description is available" do
      tool = Class.new do
        def self.name = "NamelessButNamed"
      end
      # No .description method at all -> first branch false, not a RubyLLM::Tool
      # -> else branch returns tool.name.to_s
      expect(agent.send(:tool_description_for, tool)).to eq("NamelessButNamed")
    end
  end

  # --- resolved_tools when an instance-level #tools is defined (line 611-612) --

  describe "#resolved_tools with an instance method override" do
    it "calls the instance-level tools method" do
      sentinel_tool = Class.new(RubyLLM::Tool) do
        def self.name = "SentinelTool"
      end

      klass = Class.new(described_class) do
        def self.name = "InstanceToolsAgent"
        model "gpt-4o"
      end
      klass.send(:define_method, :tools) { [sentinel_tool] }

      instance = klass.allocate.tap { |a| a.instance_variable_set(:@options, {}) }
      expect(instance.send(:resolved_tools)).to eq([sentinel_tool])
    end
  end

  # --- tool_name_for fallback to to_s (line 645) ------------------------------

  describe "#tool_name_for" do
    it "falls back to to_s for objects that are neither named nor tools" do
      obj = Object.new
      # Object#to_s returns something like "#<Object:0x...>"; assert it matches.
      expect(agent.send(:tool_name_for, obj)).to eq(obj.to_s)
    end
  end

  # --- execute rescue branches (lines 769-774) --------------------------------

  describe "#execute error handling" do
    def run_execute_with_client(error:)
      client = build_mock_chat_client
      allow(client).to receive(:ask).and_raise(error)
      stub_ruby_llm_chat(client)
      stub_agent_configuration(track_executions: false)

      ctx = new_context
      agent.send(:execute, ctx)
      ctx
    end

    it "maps CancelledError to a cancelled Result" do
      ctx = run_execute_with_client(error: RubyLLM::Agents::CancelledError.new("stop"))
      expect(ctx.output).to be_a(RubyLLM::Agents::Result)
      expect(ctx.output.cancelled?).to be(true)
    end

    it "wraps UnauthorizedError with a setup hint" do
      err = RubyLLM::UnauthorizedError.new(nil, "bad key")
      expect { run_execute_with_client(error: err) }.to raise_error(
        RubyLLM::Agents::ConfigurationError, /API key for OpenAI is missing or invalid/
      )
    end

    it "wraps ForbiddenError with a setup hint" do
      err = RubyLLM::ForbiddenError.new(nil, "forbidden")
      expect { run_execute_with_client(error: err) }.to raise_error(
        RubyLLM::Agents::ConfigurationError, /rails ruby_llm_agents:doctor/
      )
    end

    it "wraps ModelNotFoundError with a model hint" do
      err = RubyLLM::ModelNotFoundError.new("no such model")
      expect { run_execute_with_client(error: err) }.to raise_error(
        RubyLLM::Agents::ConfigurationError, /Model 'gpt-4o' was not found/
      )
    end
  end

  # --- execute_with_prefill streaming branch (lines 871-887) ------------------

  describe "#execute_with_prefill streaming" do
    let(:prefill_agent_class) do
      Class.new(described_class) do
        def self.name = "PrefillStreamAgent"
        model "gpt-4o"
        user "Continue this"
        assistant "Sure, here goes:"
      end
    end

    let(:prefill_agent) do
      prefill_agent_class.allocate.tap do |a|
        a.instance_variable_set(:@options, {})
        a.instance_variable_set(:@force_streaming, true)
      end
    end

    it "streams chunks, records time_to_first_token, and returns the final message" do
      chunks = [
        RubyLLM::Message.new(role: :assistant, content: "Hello ", model_id: "gpt-4o"),
        RubyLLM::Message.new(role: :assistant, content: "world", model_id: "gpt-4o")
      ]
      final = RubyLLM::Message.new(role: :assistant, content: "Hello world",
        model_id: "gpt-4o", input_tokens: 10, output_tokens: 4)

      client = build_mock_chat_client
      allow(client).to receive(:complete) do |&blk|
        chunks.each { |c| blk&.call(c) }
        final
      end

      received = []
      ctx = new_context(klass: prefill_agent_class, instance: prefill_agent)
      ctx.started_at = Time.current - 1
      ctx.stream_block = ->(chunk) { received << chunk }

      response = prefill_agent.send(:execute_with_prefill, client, ctx, {role: :assistant, content: "Sure"})

      expect(response).to eq(final)
      expect(received.map(&:content)).to eq(["Hello ", "world"])
      expect(ctx.time_to_first_token_ms).to be_a(Integer)
      expect(ctx.time_to_first_token_ms).to be >= 0
    end

    it "emits StreamEvents when stream_events is enabled" do
      final = RubyLLM::Message.new(role: :assistant, content: "done", model_id: "gpt-4o")
      client = build_mock_chat_client
      allow(client).to receive(:complete) do |&blk|
        blk&.call(RubyLLM::Message.new(role: :assistant, content: "x", model_id: "gpt-4o"))
        final
      end

      events = []
      ctx = new_context(klass: prefill_agent_class, instance: prefill_agent)
      ctx.stream_events = true
      ctx.stream_block = ->(event) { events << event }

      prefill_agent.send(:execute_with_prefill, client, ctx, {role: :assistant, content: "Sure"})

      expect(events).to all(be_a(RubyLLM::Agents::StreamEvent))
      expect(events.first.type).to eq(:chunk)
      expect(events.first.data[:content]).to eq("x")
    end
  end

  # --- capture_response halt path (lines 928-958) -----------------------------

  describe "#capture_response with Tool::Halt" do
    it "recovers token/model metadata from the last assistant message in the client history" do
      assistant_msg = RubyLLM::Message.new(
        role: :assistant, content: "partial", model_id: "gpt-4o",
        input_tokens: 1000, output_tokens: 500, cached_tokens: 200, cache_creation_tokens: 30
      )
      client = build_mock_chat_client
      allow(client).to receive(:messages).and_return([
        RubyLLM::Message.new(role: :user, content: "q", model_id: "gpt-4o"),
        assistant_msg
      ])
      agent.instance_variable_set(:@client, client)

      halt = RubyLLM::Tool::Halt.new("stopped")
      ctx = new_context

      agent.send(:capture_response, halt, ctx)

      expect(ctx.input_tokens).to eq(1000)
      expect(ctx.output_tokens).to eq(500)
      expect(ctx.model_used).to eq("gpt-4o")
      expect(ctx.finish_reason).to eq("halt")
      expect(ctx[:cached_tokens]).to eq(200)
      expect(ctx[:cache_creation_tokens]).to eq(30)
      # Costs are calculated since metadata + input_tokens are present.
      expect(ctx.total_cost).to be > 0
    end

    it "falls back to the agent model when no usage-bearing message exists" do
      client = build_mock_chat_client
      allow(client).to receive(:messages).and_return([
        RubyLLM::Message.new(role: :user, content: "q", model_id: "gpt-4o")
      ])
      agent.instance_variable_set(:@client, client)

      ctx = new_context
      agent.send(:capture_response, RubyLLM::Tool::Halt.new("stopped"), ctx)

      expect(ctx.model_used).to eq("gpt-4o")
      expect(ctx.finish_reason).to eq("halt")
      expect(ctx.input_tokens).to eq(0) # default; no metadata recovered
    end
  end

  describe "#last_assistant_message_from_client" do
    it "returns nil when the client has no messages" do
      agent.instance_variable_set(:@client, nil)
      expect(agent.send(:last_assistant_message_from_client)).to be_nil
    end

    it "finds the most recent assistant message carrying input_tokens" do
      older = RubyLLM::Message.new(role: :assistant, content: "old", model_id: "gpt-4o", input_tokens: 1)
      newer = RubyLLM::Message.new(role: :assistant, content: "new", model_id: "gpt-4o", input_tokens: 2)
      client = build_mock_chat_client
      allow(client).to receive(:messages).and_return([older, newer])
      agent.instance_variable_set(:@client, client)

      expect(agent.send(:last_assistant_message_from_client)).to eq(newer)
    end
  end

  # --- reasoning exclusion in #calculate_costs (lines 1029-1035) --------------

  describe "#reasoning_tokens_charged and reasoning exclusion in #calculate_costs" do
    # Builds a real RubyLLM::Cost from controlled tokens and pricing so the
    # reasoning ("thinking") component is priced by the library itself, mirroring
    # spec/lib/base_agent_cost_spec.rb. Only this RubyLLM boundary is real; no
    # internal methods are stubbed.
    def build_cost(prices:, thinking: nil)
      tokens = RubyLLM::Tokens.new(input: 1, output: 1, thinking: thinking)
      text = Struct.new(
        :input, :output, :cache_read_input, :cache_write_input, :reasoning_output,
        keyword_init: true
      ).new(**prices)
      pricing = Struct.new(:text_tokens).new(text)
      model = Struct.new(:pricing).new(pricing)

      RubyLLM::Cost.new(tokens: tokens, model: model)
    end

    # A response carrying reasoning_tokens (the production RubyLLM::Message shape).
    def message_with_reasoning(reasoning_tokens:)
      Struct.new(:reasoning_tokens).new(reasoning_tokens)
    end

    describe "#reasoning_tokens_charged" do
      let(:response) { message_with_reasoning(reasoning_tokens: 300) }

      it "returns 0 when no cost_breakdown was recorded" do
        ctx = new_context
        expect(ctx[:cost_breakdown]).to be_nil
        expect(agent.send(:reasoning_tokens_charged, response, ctx)).to eq(0)
      end

      it "returns 0 when the breakdown has no :thinking key" do
        ctx = new_context
        ctx[:cost_breakdown] = {cache_read: 0.1}
        expect(agent.send(:reasoning_tokens_charged, response, ctx)).to eq(0)
      end

      it "returns 0 when the response does not respond to reasoning_tokens" do
        ctx = new_context
        ctx[:cost_breakdown] = {thinking: 0.0009}
        plain = Struct.new(:content).new("x")
        expect(plain.respond_to?(:reasoning_tokens)).to be(false)
        expect(agent.send(:reasoning_tokens_charged, plain, ctx)).to eq(0)
      end

      it "returns the reasoning token count when reasoning was charged" do
        ctx = new_context
        ctx[:cost_breakdown] = {thinking: 0.0009}
        expect(agent.send(:reasoning_tokens_charged, response, ctx)).to eq(300)
      end
    end

    # A registry model that prices reasoning apart from output (output=8,
    # reasoning_output=3). Providers fold reasoning tokens into output_tokens, so
    # charging the full output at the output rate AND the reasoning rate would
    # double-bill those tokens.
    let(:model_id) { "perplexity/sonar-deep-research" }
    let(:pricing) { RubyLLM::Models.find(model_id).pricing.text_tokens }

    let(:reasoning_agent_class) do
      Class.new(described_class) do
        def self.name = "ReasoningExclusionAgent"
        model "perplexity/sonar-deep-research"
      end
    end

    let(:reasoning_agent) do
      reasoning_agent_class.allocate.tap do |a|
        a.instance_variable_set(:@options, {})
        a.instance_variable_set(:@model, reasoning_agent_class.model)
      end
    end

    let(:reasoning_context) do
      ctx = RubyLLM::Agents::Pipeline::Context.new(
        input: "hi",
        agent_class: reasoning_agent_class,
        agent_instance: reasoning_agent
      )
      ctx.input_tokens = 1000
      ctx.output_tokens = 500 # 300 of which are reasoning tokens
      ctx
    end

    it "excludes reasoning tokens from the output charge and bills them once" do
      # Registry sanity: reasoning is priced separately from output.
      expect(pricing.input).to eq(2)
      expect(pricing.output).to eq(8)
      expect(pricing.reasoning_output).to eq(3)

      extra = build_cost(
        thinking: 300,
        prices: {
          input: pricing.input,
          output: pricing.output,
          cache_read_input: pricing.cache_read_input,
          cache_write_input: pricing.cache_write_input,
          reasoning_output: pricing.reasoning_output
        }
      )
      response = Struct.new(:model_id, :reasoning_tokens, keyword_init: true) do
        def cost(*) = @cost

        def with_cost(c)
          @cost = c
          self
        end
      end.new(model_id: model_id, reasoning_tokens: 300).with_cost(extra)

      reasoning_agent.send(:calculate_costs, response, reasoning_context)

      # 300 of the 500 output tokens are reasoning -> output charge covers only
      # the remaining 200 tokens at the output rate.
      expected_output = ((500 - 300) / 1_000_000.0) * pricing.output
      expect(reasoning_context.output_cost).to be_within(1e-12).of(expected_output)

      # Reasoning is billed once, at the reasoning rate, via the breakdown.
      expect(reasoning_context[:cost_breakdown]).to eq(thinking: extra.thinking.round(6))
      reasoning_cost = (300 / 1_000_000.0) * pricing.reasoning_output
      expected_total = (reasoning_context.input_cost + expected_output + reasoning_cost).round(6)
      expect(reasoning_context.total_cost).to be_within(1e-9).of(expected_total)
    end

    it "does not subtract reasoning when the cost helper degrades (no breakdown)" do
      # The response exposes reasoning_tokens but its #cost raises, so
      # extra_token_costs degrades and records no breakdown. Reasoning must NOT
      # be removed from the output charge, otherwise it would vanish entirely.
      response = Struct.new(:model_id, :reasoning_tokens, keyword_init: true) do
        def cost(*) = raise("pricing blew up")
      end.new(model_id: model_id, reasoning_tokens: 300)

      with_captured_rails_logger([]) do
        reasoning_agent.send(:calculate_costs, response, reasoning_context)
      end

      expect(reasoning_context[:cost_breakdown]).to be_nil
      # All 500 output tokens billed at the output rate; reasoning never billed.
      expected_output = (500 / 1_000_000.0) * pricing.output
      expect(reasoning_context.output_cost).to be_within(1e-12).of(expected_output)
      expected_total = (reasoning_context.input_cost + expected_output).round(6)
      expect(reasoning_context.total_cost).to be_within(1e-9).of(expected_total)
    end
  end

  # --- response_cost / extra_token_costs rescue + log_cost_warning ------------
  # (lines 1061-1066, 1081-1082, 1092-1098)

  describe "#response_cost rescue path" do
    let(:model_info) { RubyLLM::Models.find("gpt-4o") }

    it "returns nil when the response does not respond to cost" do
      plain = Struct.new(:content).new("x")
      expect(agent.send(:response_cost, plain, model_info)).to be_nil
    end

    it "rescues and returns nil when cost raises, logging a warning" do
      raising = Object.new
      def raising.respond_to?(name, *) = (name == :cost) || super
      def raising.cost(*) = raise("pricing blew up")

      logged = []
      with_captured_rails_logger(logged) do
        expect(agent.send(:response_cost, raising, model_info)).to be_nil
      end
      expect(logged.join).to include("response_cost skipped")
      expect(logged.join).to include("pricing blew up")
    end
  end

  describe "#extra_token_costs rescue path" do
    let(:model_info) { RubyLLM::Models.find("gpt-4o") }

    it "degrades to 0.0 and logs when component extraction raises" do
      # A cost object whose component reader raises mid-extraction.
      bad_cost = Object.new
      def bad_cost.cache_read = raise("nope")
      def bad_cost.cache_write = 0
      def bad_cost.thinking = 0

      response = Object.new
      response.define_singleton_method(:respond_to?) { |name, *| name == :cost || super(name) }
      response.define_singleton_method(:cost) { |*| bad_cost }

      logged = []
      result = with_captured_rails_logger(logged) do
        agent.send(:extra_token_costs, response, model_info, new_context)
      end
      expect(result).to eq(0.0)
      expect(logged.join).to include("extra_token_costs skipped")
    end
  end

  describe "#log_cost_warning" do
    it "writes a debug breadcrumb when Rails.logger is present" do
      logged = []
      with_captured_rails_logger(logged) do
        agent.send(:log_cost_warning, "my_source", RuntimeError.new("kaboom"))
      end
      expect(logged.join).to include("[RubyLLM::Agents] my_source skipped: RuntimeError: kaboom")
    end

    it "does not raise when Rails.logger is nil" do
      original = Rails.logger
      Rails.logger = nil
      expect {
        agent.send(:log_cost_warning, "my_source", RuntimeError.new("kaboom"))
      }.not_to raise_error
    ensure
      Rails.logger = original
    end

    it "swallows errors raised while logging" do
      original = Rails.logger
      exploding = Object.new
      def exploding.debug(*) = raise("logger broke")
      Rails.logger = exploding
      expect {
        agent.send(:log_cost_warning, "my_source", RuntimeError.new("kaboom"))
      }.not_to raise_error
    ensure
      Rails.logger = original
    end
  end

  # --- find_model_info rescue (lines 1104-1110) -------------------------------

  describe "#find_model_info" do
    it "returns nil for nil model_id" do
      expect(agent.send(:find_model_info, nil)).to be_nil
    end

    it "returns nil (rescued) for an unknown model id" do
      expect(agent.send(:find_model_info, "totally-unknown-model-xyz")).to be_nil
    end

    it "returns real model info for a known model" do
      info = agent.send(:find_model_info, "gpt-4o")
      expect(info).to respond_to(:pricing)
    end
  end

  # --- anthropic_model? (lines 1119-1125) -------------------------------------

  describe "#anthropic_model?" do
    it "uses the registry provider when available" do
      # claude-sonnet-4-5 resolves to the anthropic provider in the registry.
      info = agent.send(:find_model_info, "claude-sonnet-4-5")
      skip "model not in registry" unless info&.provider
      expect(agent.send(:anthropic_model?, "claude-sonnet-4-5")).to be(true)
    end

    it "falls back to pattern matching for unknown claude-prefixed ids" do
      expect(agent.send(:anthropic_model?, "claude-made-up-9000")).to be(true)
    end

    it "is false for non-anthropic ids not in the registry" do
      expect(agent.send(:anthropic_model?, "some-random-model")).to be(false)
    end
  end

  # --- extract_tool_result error? branch (lines 1335-1338) --------------------

  describe "#extract_tool_result" do
    it "maps an Exception result to an error with class/message" do
      data = agent.send(:extract_tool_result, ArgumentError.new("bad arg"))
      expect(data[:status]).to eq("error")
      expect(data[:content]).to eq("bad arg")
      expect(data[:error_message]).to eq("ArgumentError: bad arg")
    end

    it "maps an error?-responding result to an error using its content/error_message" do
      result = Struct.new(:content, :error_message) do
        def error? = true
      end.new("failure body", "the error message")

      data = agent.send(:extract_tool_result, result)
      expect(data[:status]).to eq("error")
      expect(data[:content]).to eq("failure body")
      expect(data[:error_message]).to eq("the error message")
    end

    it "maps an error?-responding result without error_message to its content" do
      result = Object.new
      def result.error? = true
      def result.content = "boom text"
      def result.respond_to?(name, *) = %i[error? content].include?(name) || super

      data = agent.send(:extract_tool_result, result)
      expect(data[:status]).to eq("error")
      expect(data[:content]).to eq("boom text")
      expect(data[:error_message]).to eq("boom text")
    end

    it "treats a hash with an error key as an error" do
      data = agent.send(:extract_tool_result, {content: "x", error: "kaput"})
      expect(data[:status]).to eq("error")
      expect(data[:error_message]).to eq("kaput")
    end

    it "treats a plain string as success" do
      data = agent.send(:extract_tool_result, "all good")
      expect(data[:status]).to eq("success")
      expect(data[:content]).to eq("all good")
    end
  end

  # --- tool_result_max_length rescue (lines 1372-1376) ------------------------

  describe "#tool_result_max_length" do
    it "returns the configured value" do
      RubyLLM::Agents.reset_configuration!
      RubyLLM::Agents.configure { |c| c.tool_result_max_length = 42 }
      expect(agent.send(:tool_result_max_length)).to eq(42)
    ensure
      RubyLLM::Agents.reset_configuration!
    end

    it "rescues to 10_000 when configuration access raises" do
      real = RubyLLM::Agents.instance_variable_get(:@configuration)
      raising = Object.new
      def raising.tool_result_max_length = raise("boom")
      RubyLLM::Agents.instance_variable_set(:@configuration, raising)
      expect(agent.send(:tool_result_max_length)).to eq(10_000)
    ensure
      RubyLLM::Agents.instance_variable_set(:@configuration, real)
    end
  end

  # --- detect_provider branches (lines 1417-1427) -----------------------------

  describe "#detect_provider" do
    it "returns nil for nil model_id" do
      expect(agent.send(:detect_provider, nil)).to be_nil
    end

    it "detects OpenAI" do
      expect(agent.send(:detect_provider, "gpt-4o")).to eq("OpenAI")
      expect(agent.send(:detect_provider, "o3-mini")).to eq("OpenAI")
      expect(agent.send(:detect_provider, "whisper-1")).to eq("OpenAI")
    end

    it "detects Anthropic" do
      expect(agent.send(:detect_provider, "claude-sonnet-4-5")).to eq("Anthropic")
    end

    it "detects Google (Gemini)" do
      expect(agent.send(:detect_provider, "gemini-2.0-flash")).to eq("Google (Gemini)")
      expect(agent.send(:detect_provider, "gemma-2")).to eq("Google (Gemini)")
    end

    it "detects DeepSeek" do
      expect(agent.send(:detect_provider, "deepseek-chat")).to eq("DeepSeek")
    end

    it "detects Mistral" do
      expect(agent.send(:detect_provider, "mistral-large")).to eq("Mistral")
      expect(agent.send(:detect_provider, "mixtral-8x7b")).to eq("Mistral")
    end

    it "returns nil for an unrecognized model" do
      expect(agent.send(:detect_provider, "some-obscure-model")).to be_nil
    end
  end

  # Temporarily swaps in a logger that records debug lines, restoring the
  # original afterward. Returns the block's value.
  def with_captured_rails_logger(sink)
    original = Rails.logger
    capturing = Object.new
    capturing.define_singleton_method(:debug) { |msg = nil| sink << msg.to_s }
    Rails.logger = capturing
    yield
  ensure
    Rails.logger = original
  end
end
