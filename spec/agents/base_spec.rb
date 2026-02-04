# frozen_string_literal: true

require "rails_helper"

RSpec.describe RubyLLM::Agents::Base do
  describe "DSL class methods" do
    describe ".model" do
      it "sets and gets the model" do
        klass = Class.new(described_class) do
          model "gpt-4"
        end
        expect(klass.model).to eq("gpt-4")
      end

      it "inherits model from parent" do
        parent = Class.new(described_class) { model "gpt-4" }
        child = Class.new(parent)
        expect(child.model).to eq("gpt-4")
      end
    end

    describe ".temperature" do
      it "sets and gets the temperature" do
        klass = Class.new(described_class) do
          temperature 0.7
        end
        expect(klass.temperature).to eq(0.7)
      end
    end

    describe ".version" do
      it "sets and gets the version" do
        klass = Class.new(described_class) do
          version "2.0"
        end
        expect(klass.version).to eq("2.0")
      end

      it "defaults to 1.0" do
        klass = Class.new(described_class)
        expect(klass.version).to eq("1.0")
      end
    end

    describe ".param" do
      it "defines required parameters" do
        klass = Class.new(described_class) do
          param :query, required: true
        end
        expect(klass.params[:query]).to include(required: true)
      end

      it "defines parameters with defaults" do
        klass = Class.new(described_class) do
          param :limit, default: 10
        end
        expect(klass.params[:limit]).to include(default: 10)
      end
    end

    describe ".cache" do
      it "sets cache duration" do
        klass = Class.new(described_class) do
          cache 1.hour
        end
        expect(klass.cache_ttl).to eq(1.hour)
      end
    end

    describe ".streaming" do
      it "sets and gets streaming mode" do
        klass = Class.new(described_class) do
          streaming true
        end
        expect(klass.streaming).to be true
      end

      it "defaults to false" do
        klass = Class.new(described_class)
        expect(klass.streaming).to be false
      end

      it "inherits streaming from parent" do
        parent = Class.new(described_class) { streaming true }
        child = Class.new(parent)
        expect(child.streaming).to be true
      end
    end

    describe ".tools" do
      let(:mock_tool) do
        Class.new do
          def self.name
            "MockTool"
          end
        end
      end

      it "sets and gets tools" do
        tool = mock_tool
        klass = Class.new(described_class) do
          tools [tool]
        end
        expect(klass.tools).to include(tool)
      end

      it "defaults to empty array" do
        klass = Class.new(described_class)
        expect(klass.tools).to eq([])
      end

      it "allows multiple tools" do
        tool1 = mock_tool
        tool2 = Class.new { def self.name; "AnotherTool"; end }
        klass = Class.new(described_class) do
          tools [tool1, tool2]
        end
        expect(klass.tools).to include(tool1, tool2)
      end

      it "inherits tools from parent" do
        tool = mock_tool
        parent = Class.new(described_class) { tools [tool] }
        child = Class.new(parent)
        expect(child.tools).to include(tool)
      end
    end
  end

  describe "instance initialization" do
    let(:agent_class) do
      Class.new(described_class) do
        model "gpt-4"
        temperature 0.5
        param :query, required: true
        param :limit, default: 10
      end
    end

    it "sets required parameters" do
      agent = agent_class.new(query: "test")
      expect(agent.query).to eq("test")
    end

    it "uses default values for optional parameters" do
      agent = agent_class.new(query: "test")
      expect(agent.limit).to eq(10)
    end

    it "allows overriding defaults" do
      agent = agent_class.new(query: "test", limit: 20)
      expect(agent.limit).to eq(20)
    end

    it "raises error for missing required parameters" do
      expect {
        agent_class.new(limit: 10)
      }.to raise_error(ArgumentError, /missing required param/)
    end
  end

  describe "dry_run mode" do
    let(:mock_tool) do
      Class.new do
        def self.name
          "TestTool"
        end
      end
    end

    let(:agent_class) do
      Class.new(described_class) do
        model "gpt-4"
        param :query, required: true

        def system_prompt
          "Test prompt"
        end

        def user_prompt
          query
        end
      end
    end

    it "returns a Result object when dry_run: true" do
      agent = agent_class.new(query: "test", dry_run: true)
      result = agent.call

      expect(result).to be_a(RubyLLM::Agents::Result)
      expect(result.content[:dry_run]).to be true
      expect(result.content[:model]).to eq("gpt-4")
      expect(result.content[:user_prompt]).to eq("test")
      expect(result.model_id).to eq("gpt-4")
    end

    it "supports backward compatible hash access on dry_run result" do
      agent = agent_class.new(query: "test", dry_run: true)
      result = agent.call

      # Delegated methods still work
      expect(result[:dry_run]).to be true
      expect(result[:model]).to eq("gpt-4")
      expect(result[:user_prompt]).to eq("test")
    end

    it "includes streaming in dry run response" do
      streaming_class = Class.new(described_class) do
        model "gpt-4"
        streaming true
        param :query, required: true

        def user_prompt
          query
        end
      end

      result = streaming_class.call(query: "test", dry_run: true)
      expect(result[:streaming]).to be true
    end

    it "includes tools in dry run response" do
      tool = mock_tool
      tools_class = Class.new(described_class) do
        model "gpt-4"
        param :query, required: true

        def user_prompt
          query
        end
      end
      tools_class.tools(tool)

      result = tools_class.call(query: "test", dry_run: true)
      expect(result[:tools]).to include("TestTool")
    end
  end

  describe ".call" do
    let(:agent_class) do
      Class.new(described_class) do
        model "gpt-4"
        param :query, required: true

        def system_prompt
          "Test system prompt"
        end

        def user_prompt
          query
        end
      end
    end

    it "creates instance and calls #call" do
      agent_instance = instance_double(agent_class)
      allow(agent_class).to receive(:new).and_return(agent_instance)
      allow(agent_instance).to receive(:call).and_return("result")

      result = agent_class.call(query: "test")

      expect(agent_class).to have_received(:new).with(query: "test")
      expect(agent_instance).to have_received(:call)
      expect(result).to eq("result")
    end
  end

  describe "#agent_cache_key" do
    let(:agent_class) do
      Class.new(described_class) do
        model "gpt-4"
        param :query, required: true

        def system_prompt
          "Test prompt"
        end

        def user_prompt
          query
        end
      end
    end

    it "generates consistent cache key for same inputs" do
      agent1 = agent_class.new(query: "test")
      agent2 = agent_class.new(query: "test")

      expect(agent1.send(:agent_cache_key)).to eq(agent2.send(:agent_cache_key))
    end

    it "generates different cache key for different inputs" do
      agent1 = agent_class.new(query: "test1")
      agent2 = agent_class.new(query: "test2")

      expect(agent1.send(:agent_cache_key)).not_to eq(agent2.send(:agent_cache_key))
    end

    it "excludes :with from cache key" do
      agent1 = agent_class.new(query: "test", with: "image.png")
      agent2 = agent_class.new(query: "test")

      expect(agent1.send(:agent_cache_key)).to eq(agent2.send(:agent_cache_key))
    end
  end

  describe "attachments support" do
    let(:agent_class) do
      Class.new(described_class) do
        model "gpt-4o"
        param :query, required: true

        def user_prompt
          query
        end
      end
    end

    describe "#execution_options (attachments)" do
      it "returns nil for attachments when none provided" do
        agent = agent_class.new(query: "test")
        expect(agent.send(:execution_options)[:attachments]).to be_nil
      end

      it "includes :attachments when provided via :with" do
        agent = agent_class.new(query: "test", with: "image.png")
        expect(agent.send(:execution_options)[:attachments]).to eq("image.png")
      end

      it "supports array of attachments" do
        agent = agent_class.new(query: "test", with: ["a.png", "b.png"])
        expect(agent.send(:execution_options)[:attachments]).to eq(["a.png", "b.png"])
      end
    end

    describe "dry_run with attachments" do
      it "includes attachments in dry run response" do
        result = agent_class.call(query: "test", with: "photo.jpg", dry_run: true)

        expect(result[:attachments]).to eq("photo.jpg")
      end

      it "includes array attachments in dry run response" do
        result = agent_class.call(query: "test", with: ["a.png", "b.png"], dry_run: true)

        expect(result[:attachments]).to eq(["a.png", "b.png"])
      end

      it "shows nil attachments when none provided" do
        result = agent_class.call(query: "test", dry_run: true)

        expect(result[:attachments]).to be_nil
      end
    end
  end

  describe "caching behavior" do
    let(:cache_store) { ActiveSupport::Cache::MemoryStore.new }

    let(:cached_agent_class) do
      Class.new(described_class) do
        model "gpt-4"
        cache 1.hour
        param :query, required: true

        def system_prompt
          "Test system prompt"
        end

        def user_prompt
          query
        end

        def process_response(response)
          response.content
        end

        def self.name
          "CachedTestAgent"
        end
      end
    end

    let(:uncached_agent_class) do
      Class.new(described_class) do
        model "gpt-4"
        param :query, required: true

        def system_prompt
          "Test system prompt"
        end

        def user_prompt
          query
        end

        def process_response(response)
          response.content
        end

        def self.name
          "UncachedTestAgent"
        end
      end
    end

    let(:mock_response) do
      build_mock_response(content: "Cached response content", input_tokens: 100, output_tokens: 50)
    end

    let(:mock_chat) do
      build_mock_chat_client(response: mock_response)
    end

    before do
      stub_agent_configuration(cache_store: cache_store)
      stub_ruby_llm_chat(mock_chat)
      cache_store.clear
    end

    describe "when caching is enabled" do
      it "does not call the AI client on cache hit" do
        agent1 = cached_agent_class.new(query: "test query")
        agent1.call

        agent2 = cached_agent_class.new(query: "test query")
        agent2.call

        expect(mock_chat).to have_received(:ask).exactly(1).time
      end

      it "returns the cached Result on subsequent calls" do
        agent1 = cached_agent_class.new(query: "test query")
        first_result = agent1.call

        agent2 = cached_agent_class.new(query: "test query")
        second_result = agent2.call

        expect(second_result.content).to eq(first_result.content)
      end

      it "returns a Result object from cache" do
        agent1 = cached_agent_class.new(query: "test query")
        agent1.call

        agent2 = cached_agent_class.new(query: "test query")
        result = agent2.call

        expect(result).to be_a(RubyLLM::Agents::Result)
      end
    end

    describe "when skip_cache: true is passed" do
      it "calls the AI client even if response is cached" do
        agent1 = cached_agent_class.new(query: "test query")
        agent1.call

        agent2 = cached_agent_class.new(query: "test query", skip_cache: true)
        agent2.call

        expect(mock_chat).to have_received(:ask).exactly(2).times
      end
    end

    describe "when parameters differ" do
      it "calls the AI client for different inputs (cache miss)" do
        agent1 = cached_agent_class.new(query: "first query")
        agent1.call

        agent2 = cached_agent_class.new(query: "second query")
        agent2.call

        expect(mock_chat).to have_received(:ask).exactly(2).times
      end
    end

    describe "when caching is disabled" do
      it "calls the AI client on every call" do
        agent1 = uncached_agent_class.new(query: "test query")
        agent1.call

        agent2 = uncached_agent_class.new(query: "test query")
        agent2.call

        expect(mock_chat).to have_received(:ask).exactly(2).times
      end
    end

    describe "cache hit execution recording" do
      it "creates an execution record with cache_hit: true on cache hit" do
        # First call - populate cache
        agent1 = cached_agent_class.new(query: "test query")
        agent1.call

        # Second call - should be a cache hit
        agent2 = cached_agent_class.new(query: "test query")

        expect {
          agent2.call
        }.to change { RubyLLM::Agents::Execution.where(cache_hit: true).count }.by(1)
      end

      it "records 0 tokens and 0 cost for cache hits" do
        # First call - populate cache
        agent1 = cached_agent_class.new(query: "test query")
        agent1.call

        # Second call - cache hit
        agent2 = cached_agent_class.new(query: "test query")
        agent2.call

        cache_hit_execution = RubyLLM::Agents::Execution.where(cache_hit: true).last
        expect(cache_hit_execution.input_tokens).to eq(0)
        expect(cache_hit_execution.output_tokens).to eq(0)
        expect(cache_hit_execution.total_tokens).to eq(0)
        expect(cache_hit_execution.total_cost).to eq(0)
      end

      it "records the cache key in response_cache_key" do
        # First call - populate cache
        agent1 = cached_agent_class.new(query: "test query")
        agent1.call

        # Second call - cache hit
        agent2 = cached_agent_class.new(query: "test query")
        agent2.call

        cache_hit_execution = RubyLLM::Agents::Execution.where(cache_hit: true).last
        expect(cache_hit_execution.response_cache_key).to be_present
        expect(cache_hit_execution.response_cache_key).to include("ruby_llm_agent")
      end

      it "does not create cache_hit execution for first call (cache miss)" do
        agent = cached_agent_class.new(query: "unique query for this test")

        expect {
          agent.call
        }.not_to change { RubyLLM::Agents::Execution.where(cache_hit: true).count }
      end
    end
  end

  describe "conversation history (messages) support" do
    let(:agent_class) do
      Class.new(described_class) do
        model "gpt-4"
        param :query, required: true

        def user_prompt
          query
        end

        def self.name
          "TestMessagesAgent"
        end
      end
    end

    describe "#messages template method" do
      it "returns empty array by default" do
        agent = agent_class.new(query: "test")
        expect(agent.messages).to eq([])
      end

      it "can be overridden in subclass" do
        custom_messages = [
          { role: :user, content: "Hello" },
          { role: :assistant, content: "Hi there!" }
        ]

        custom_class = Class.new(agent_class) do
          define_method(:messages) { custom_messages }
        end

        agent = custom_class.new(query: "test")
        expect(agent.messages).to eq(custom_messages)
      end
    end

    describe "#resolved_messages" do
      it "returns empty array when no messages provided" do
        agent = agent_class.new(query: "test")
        expect(agent.send(:resolved_messages)).to eq([])
      end

      it "returns messages from options when passed at call time" do
        messages = [{ role: :user, content: "Previous message" }]
        agent = agent_class.new(query: "test", messages: messages)
        expect(agent.send(:resolved_messages)).to eq(messages)
      end

      it "returns messages from template method when defined" do
        template_messages = [{ role: :assistant, content: "Template message" }]

        custom_class = Class.new(agent_class) do
          define_method(:messages) { template_messages }
        end

        agent = custom_class.new(query: "test")
        expect(agent.send(:resolved_messages)).to eq(template_messages)
      end

      it "prioritizes options over template method" do
        template_messages = [{ role: :assistant, content: "Template message" }]
        option_messages = [{ role: :user, content: "Option message" }]

        custom_class = Class.new(agent_class) do
          define_method(:messages) { template_messages }
        end

        agent = custom_class.new(query: "test", messages: option_messages)
        expect(agent.send(:resolved_messages)).to eq(option_messages)
      end

      it "prioritizes options messages over template method" do
        option_messages = [{ role: :user, content: "Option message" }]
        template_messages = [{ role: :user, content: "Template message" }]

        custom_class = Class.new(agent_class) do
          define_method(:messages) { template_messages }
        end

        agent = custom_class.new(query: "test", messages: option_messages)

        expect(agent.send(:resolved_messages)).to eq(option_messages)
      end
    end

    describe "#apply_messages" do
      let(:mock_chat) do
        build_mock_chat_client
      end

      before do
        stub_ruby_llm_chat(mock_chat)
      end

      it "applies messages via add_message calls" do
        messages = [
          { role: :user, content: "First message" },
          { role: :assistant, content: "Second message" }
        ]

        agent = agent_class.new(query: "test", messages: messages)
        agent.send(:build_client)

        expect(mock_chat).to have_received(:add_message).with(role: :user, content: "First message")
        expect(mock_chat).to have_received(:add_message).with(role: :assistant, content: "Second message")
      end

      it "uses symbol roles" do
        messages = [{ role: :user, content: "Hello" }]
        agent = agent_class.new(query: "test", messages: messages)
        agent.send(:build_client)

        expect(mock_chat).to have_received(:add_message).with(role: :user, content: "Hello")
      end

      it "converts string roles to symbols" do
        messages = [{ role: "assistant", content: "Hello" }]
        agent = agent_class.new(query: "test", messages: messages)
        agent.send(:build_client)

        expect(mock_chat).to have_received(:add_message).with(role: :assistant, content: "Hello")
      end
    end

    describe "integration with agent execution" do
      let(:mock_response) do
        build_mock_response(content: "Response with context", input_tokens: 100, output_tokens: 50)
      end

      let(:mock_chat) do
        build_mock_chat_client(response: mock_response)
      end

      before do
        stub_agent_configuration
        stub_ruby_llm_chat(mock_chat)
      end

      it "passes messages to the client when called via class method" do
        messages = [{ role: :user, content: "Remember my name is Alice" }]

        agent = agent_class.new(query: "What is my name?", messages: messages)
        agent.send(:build_client)

        expect(mock_chat).to have_received(:add_message).with(role: :user, content: "Remember my name is Alice")
      end

      it "works with messages passed to constructor" do
        agent = agent_class.new(
          query: "Continue our conversation",
          messages: [
            { role: :user, content: "Tell me a joke" },
            { role: :assistant, content: "Why did the chicken cross the road?" }
          ]
        )
        agent.send(:build_client)

        expect(mock_chat).to have_received(:add_message).with(role: :user, content: "Tell me a joke")
        expect(mock_chat).to have_received(:add_message).with(role: :assistant, content: "Why did the chicken cross the road?")
      end

      it "works with template method in subclass" do
        conversation_history = [
          { role: :user, content: "What is 2+2?" },
          { role: :assistant, content: "4" }
        ]

        chat_agent_class = Class.new(agent_class) do
          define_method(:messages) { conversation_history }
        end

        agent = chat_agent_class.new(query: "What about 3+3?")
        agent.send(:build_client)

        expect(mock_chat).to have_received(:add_message).with(role: :user, content: "What is 2+2?")
        expect(mock_chat).to have_received(:add_message).with(role: :assistant, content: "4")
      end
    end

    describe "with dynamic messages based on params" do
      it "allows messages to access agent params" do
        dynamic_agent_class = Class.new(agent_class) do
          param :context_type, default: :general

          def messages
            case context_type
            when :technical
              [{ role: :system, content: "You are a technical expert" }]
            when :friendly
              [{ role: :system, content: "You are a friendly assistant" }]
            else
              []
            end
          end
        end

        technical_agent = dynamic_agent_class.new(query: "Help me", context_type: :technical)
        expect(technical_agent.send(:resolved_messages)).to eq([
          { role: :system, content: "You are a technical expert" }
        ])

        friendly_agent = dynamic_agent_class.new(query: "Help me", context_type: :friendly)
        expect(friendly_agent.send(:resolved_messages)).to eq([
          { role: :system, content: "You are a friendly assistant" }
        ])

        default_agent = dynamic_agent_class.new(query: "Help me")
        expect(default_agent.send(:resolved_messages)).to eq([])
      end
    end
  end

  describe ".agent_type" do
    it "returns :conversation" do
      expect(described_class.agent_type).to eq(:conversation)
    end
  end

  describe "#resolved_tenant_id" do
    let(:agent_class) do
      Class.new(described_class) do
        model "gpt-4"
        param :query, required: true

        def user_prompt
          query
        end
      end
    end

    it "returns nil when no tenant is resolved" do
      agent = agent_class.new(query: "test")
      allow(agent).to receive(:resolve_tenant).and_return(nil)

      expect(agent.resolved_tenant_id).to be_nil
    end

    it "returns id from hash tenant" do
      agent = agent_class.new(query: "test")
      allow(agent).to receive(:resolve_tenant).and_return({ id: 123 })

      expect(agent.resolved_tenant_id).to eq("123")
    end

    it "returns nil when tenant hash has no id" do
      agent = agent_class.new(query: "test")
      allow(agent).to receive(:resolve_tenant).and_return({ name: "Test Tenant" })

      expect(agent.resolved_tenant_id).to be_nil
    end
  end

  describe "callbacks" do
    let(:callback_agent_class) do
      Class.new(described_class) do
        model "gpt-4"
        param :query, required: true

        before_call :track_before_call
        after_call :track_after_call

        def system_prompt
          "Test prompt"
        end

        def user_prompt
          query
        end

        def self.name
          "CallbackTestAgent"
        end

        def before_call_executed?
          @before_call_executed
        end

        def after_call_executed?
          @after_call_executed
        end

        private

        def track_before_call(context)
          @before_call_executed = true
        end

        def track_after_call(context, response)
          @after_call_executed = true
        end
      end
    end

    it "runs before_call callback before LLM call" do
      agent = callback_agent_class.new(query: "test")

      # Mock the LLM response
      mock_response = build_mock_response(content: "Test response", input_tokens: 100, output_tokens: 50)
      mock_chat = build_mock_chat_client(response: mock_response)
      stub_ruby_llm_chat(mock_chat)
      stub_agent_configuration

      # Create a context for pipeline execution
      context = RubyLLM::Agents::Pipeline::Context.new(
        input: "test",
        agent_class: callback_agent_class,
        agent_instance: agent
      )

      agent.execute(context)

      expect(agent.before_call_executed?).to be true
    end

    it "runs after_call callback after LLM call" do
      agent = callback_agent_class.new(query: "test")

      # Mock the LLM response
      mock_response = build_mock_response(content: "Test response", input_tokens: 100, output_tokens: 50)
      mock_chat = build_mock_chat_client(response: mock_response)
      stub_ruby_llm_chat(mock_chat)
      stub_agent_configuration

      # Create a context for pipeline execution
      context = RubyLLM::Agents::Pipeline::Context.new(
        input: "test",
        agent_class: callback_agent_class,
        agent_instance: agent
      )

      agent.execute(context)

      expect(agent.after_call_executed?).to be true
    end

    it "allows before_call to block execution by raising" do
      blocking_agent_class = Class.new(described_class) do
        model "gpt-4"
        param :query, required: true

        before_call :block_execution

        def user_prompt
          query
        end

        def self.name
          "BlockingCallbackAgent"
        end

        private

        def block_execution(context)
          raise "Execution blocked"
        end
      end

      agent = blocking_agent_class.new(query: "test")

      context = RubyLLM::Agents::Pipeline::Context.new(
        input: "test",
        agent_class: blocking_agent_class,
        agent_instance: agent
      )

      expect { agent.execute(context) }.to raise_error("Execution blocked")
    end

    it "supports block-based callbacks" do
      block_callback_executed = false

      block_agent_class = Class.new(described_class) do
        model "gpt-4"
        param :query, required: true

        def user_prompt
          query
        end

        def self.name
          "BlockCallbackAgent"
        end
      end

      # Add block callback at class level
      block_agent_class.before_call { |_context| block_callback_executed = true }

      agent = block_agent_class.new(query: "test")

      # Mock the LLM response
      mock_response = build_mock_response(content: "Test response", input_tokens: 100, output_tokens: 50)
      mock_chat = build_mock_chat_client(response: mock_response)
      stub_ruby_llm_chat(mock_chat)
      stub_agent_configuration

      context = RubyLLM::Agents::Pipeline::Context.new(
        input: "test",
        agent_class: block_agent_class,
        agent_instance: agent
      )

      agent.execute(context)

      expect(block_callback_executed).to be true
    end
  end
end
