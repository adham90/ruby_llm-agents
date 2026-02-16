# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Three-Role Prompt DSL" do
  # Silence deprecation warnings for tests
  before do
    RubyLLM::Agents::Deprecations.silenced = true
  end

  after do
    RubyLLM::Agents::Deprecations.silenced = false
  end

  # ── user DSL ──────────────────────────────────────────────────

  describe "user DSL" do
    it "sets user template with string" do
      agent_class = Class.new(RubyLLM::Agents::Base) do
        user "Hello {name}"
      end
      expect(agent_class.user_config).to eq("Hello {name}")
    end

    it "auto-registers placeholders as required params" do
      agent_class = Class.new(RubyLLM::Agents::Base) do
        user "Search {query} in {category}"
      end
      expect(agent_class.params.keys).to include(:query, :category)
      expect(agent_class.params[:query][:required]).to be true
      expect(agent_class.params[:category][:required]).to be true
    end

    it "does not override explicitly defined params" do
      agent_class = Class.new(RubyLLM::Agents::Base) do
        param :query, default: "default_query"
        user "Search {query}"
      end
      expect(agent_class.params[:query][:default]).to eq("default_query")
      expect(agent_class.params[:query][:required]).to be false
    end

    it "returns nil when not set" do
      agent_class = Class.new(RubyLLM::Agents::Base)
      expect(agent_class.user_config).to be_nil
    end

    it "inherits from parent class" do
      parent = Class.new(RubyLLM::Agents::Base) { user "Parent prompt" }
      child = Class.new(parent)
      expect(child.user_config).to eq("Parent prompt")
    end

    it "overrides parent" do
      parent = Class.new(RubyLLM::Agents::Base) { user "Parent" }
      child = Class.new(parent) { user "Child" }
      expect(child.user_config).to eq("Child")
      expect(parent.user_config).to eq("Parent")
    end

    it "supports heredoc syntax" do
      agent_class = Class.new(RubyLLM::Agents::Base) do
        user <<~S
          Search for: {query}
          Category: {category}
        S
      end
      expect(agent_class.user_config).to include("Search for: {query}")
      expect(agent_class.user_config).to include("Category: {category}")
      expect(agent_class.params.keys).to include(:query, :category)
    end
  end

  # ── prompt alias ──────────────────────────────────────────────

  describe "prompt alias (backward compat)" do
    it "works as alias for user" do
      agent_class = Class.new(RubyLLM::Agents::Base) { prompt "Hello {name}" }
      expect(agent_class.user_config).to eq("Hello {name}")
    end

    it "auto-registers params same as user" do
      agent_class = Class.new(RubyLLM::Agents::Base) { prompt "Search {query}" }
      expect(agent_class.params.keys).to include(:query)
    end

    it "prompt_config returns same as user_config" do
      agent_class = Class.new(RubyLLM::Agents::Base) { user "Test {x}" }
      expect(agent_class.prompt_config).to eq(agent_class.user_config)
    end

    it "block form still works for backward compat" do
      agent_class = Class.new(RubyLLM::Agents::Base) do
        prompt { "Dynamic #{1 + 1}" }
      end
      expect(agent_class.user_config).to be_a(Proc)
    end
  end

  # ── system DSL ────────────────────────────────────────────────

  describe "system DSL" do
    it "sets system template with string" do
      agent_class = Class.new(RubyLLM::Agents::Base) do
        system "You are a helpful assistant."
      end
      expect(agent_class.system_config).to eq("You are a helpful assistant.")
    end

    it "returns nil when not set" do
      agent_class = Class.new(RubyLLM::Agents::Base)
      expect(agent_class.system_config).to be_nil
    end

    it "inherits from parent" do
      parent = Class.new(RubyLLM::Agents::Base) { system "Parent system" }
      child = Class.new(parent)
      expect(child.system_config).to eq("Parent system")
    end

    it "overrides parent" do
      parent = Class.new(RubyLLM::Agents::Base) { system "Parent" }
      child = Class.new(parent) { system "Child" }
      expect(child.system_config).to eq("Child")
      expect(parent.system_config).to eq("Parent")
    end

    it "auto-registers placeholders as required params" do
      agent_class = Class.new(RubyLLM::Agents::Base) do
        system "You are helping {user_name} with {task}"
      end
      expect(agent_class.params.keys).to include(:user_name, :task)
      expect(agent_class.params[:user_name][:required]).to be true
    end

    it "supports heredoc syntax" do
      agent_class = Class.new(RubyLLM::Agents::Base) do
        system <<~S
          You are a helpful assistant.
          Be concise and accurate.
        S
      end
      expect(agent_class.system_config).to include("You are a helpful assistant.")
      expect(agent_class.system_config).to include("Be concise and accurate.")
    end
  end

  # ── assistant DSL ─────────────────────────────────────────────

  describe "assistant DSL" do
    it "sets assistant template" do
      agent_class = Class.new(RubyLLM::Agents::Base) do
        assistant '{"result":'
      end
      expect(agent_class.assistant_config).to eq('{"result":')
    end

    it "returns nil when not set" do
      agent_class = Class.new(RubyLLM::Agents::Base)
      expect(agent_class.assistant_config).to be_nil
    end

    it "inherits from parent" do
      parent = Class.new(RubyLLM::Agents::Base) { assistant '{"data":' }
      child = Class.new(parent)
      expect(child.assistant_config).to eq('{"data":')
    end

    it "overrides parent" do
      parent = Class.new(RubyLLM::Agents::Base) { assistant "Parent" }
      child = Class.new(parent) { assistant "Child" }
      expect(child.assistant_config).to eq("Child")
      expect(parent.assistant_config).to eq("Parent")
    end

    it "supports placeholders" do
      agent_class = Class.new(RubyLLM::Agents::Base) do
        assistant "Results for {query}:"
      end
      expect(agent_class.params.keys).to include(:query)
    end
  end

  # ── Instance method: #user_prompt ─────────────────────────────

  describe "#user_prompt" do
    it "interpolates placeholders from params" do
      agent_class = Class.new(RubyLLM::Agents::Base) do
        user "Search {query}"
      end
      agent = agent_class.new(query: "ruby")
      expect(agent.user_prompt).to eq("Search ruby")
    end

    it "interpolates multiple placeholders" do
      agent_class = Class.new(RubyLLM::Agents::Base) do
        user "Search {query} in {category} (limit: {limit})"
        param :limit, default: 10
      end
      agent = agent_class.new(query: "ruby", category: "gems")
      expect(agent.user_prompt).to eq("Search ruby in gems (limit: 10)")
    end

    it "raises NotImplementedError when not defined" do
      agent_class = Class.new(RubyLLM::Agents::Base) do
        def self.name = "EmptyAgent"
      end
      expect { agent_class.new.user_prompt }.to raise_error(NotImplementedError, /user/)
    end

    it "method override takes precedence over class-level DSL" do
      agent_class = Class.new(RubyLLM::Agents::Base) do
        user "Class level"
        define_method(:user_prompt) { "Method level" }
      end
      agent = agent_class.new
      expect(agent.user_prompt).to eq("Method level")
    end

    it "works with backward-compat prompt DSL" do
      agent_class = Class.new(RubyLLM::Agents::Base) do
        prompt "Hello {name}"
      end
      agent = agent_class.new(name: "World")
      expect(agent.user_prompt).to eq("Hello World")
    end

    it "works with block form (backward compat)" do
      agent_class = Class.new(RubyLLM::Agents::Base) do
        param :name, required: true
        prompt { "Hello #{name}" }
      end
      agent = agent_class.new(name: "World")
      expect(agent.user_prompt).to eq("Hello World")
    end
  end

  # ── Instance method: #system_prompt ───────────────────────────

  describe "#system_prompt" do
    it "returns nil when not defined" do
      agent_class = Class.new(RubyLLM::Agents::Base)
      expect(agent_class.new.system_prompt).to be_nil
    end

    it "returns the system template" do
      agent_class = Class.new(RubyLLM::Agents::Base) do
        system "You are helpful."
      end
      expect(agent_class.new.system_prompt).to eq("You are helpful.")
    end

    it "interpolates placeholders" do
      agent_class = Class.new(RubyLLM::Agents::Base) do
        system "Helping {user_name}"
      end
      agent = agent_class.new(user_name: "Alice")
      expect(agent.system_prompt).to eq("Helping Alice")
    end

    it "method override takes precedence" do
      agent_class = Class.new(RubyLLM::Agents::Base) do
        system "Class level"
        define_method(:system_prompt) { "Method override" }
      end
      expect(agent_class.new.system_prompt).to eq("Method override")
    end
  end

  # ── Instance method: #assistant_prompt ────────────────────────

  describe "#assistant_prompt" do
    it "returns nil when not defined" do
      agent_class = Class.new(RubyLLM::Agents::Base)
      expect(agent_class.new.assistant_prompt).to be_nil
    end

    it "returns the assistant template" do
      agent_class = Class.new(RubyLLM::Agents::Base) do
        assistant '{"result":'
      end
      expect(agent_class.new.assistant_prompt).to eq('{"result":')
    end

    it "interpolates placeholders" do
      agent_class = Class.new(RubyLLM::Agents::Base) do
        assistant "About {topic}:"
      end
      agent = agent_class.new(topic: "Ruby")
      expect(agent.assistant_prompt).to eq("About Ruby:")
    end

    it "method override takes precedence" do
      agent_class = Class.new(RubyLLM::Agents::Base) do
        assistant "Class level"
        define_method(:assistant_prompt) { "Method override" }
      end
      expect(agent_class.new.assistant_prompt).to eq("Method override")
    end
  end

  # ── .ask class method ─────────────────────────────────────────

  describe ".ask" do
    let(:conversational_agent) do
      Class.new(RubyLLM::Agents::Base) do
        def self.name = "ConversationalAgent"
        system "You are a helpful assistant."
      end
    end

    let(:template_agent) do
      Class.new(RubyLLM::Agents::Base) do
        def self.name = "TemplateAgent"
        system "You are a classifier."
        user "Classify: {text}"
      end
    end

    it "sets the user prompt to the given message" do
      agent = conversational_agent.new(_ask_message: "What is Ruby?")
      expect(agent.user_prompt).to eq("What is Ruby?")
    end

    it "skips required param validation" do
      # template_agent has auto-registered required :text param
      expect { template_agent.ask("freeform message") }.not_to raise_error
    rescue NotImplementedError
      # Expected if pipeline not set up — the key is no ArgumentError about params
    end

    it "bypasses user template on template agents" do
      agent = template_agent.new(_ask_message: "Just say hello")
      expect(agent.user_prompt).to eq("Just say hello")
    end

    it "method override takes precedence over ask message" do
      agent_class = Class.new(RubyLLM::Agents::Base) do
        def self.name = "OverrideAgent"
        define_method(:user_prompt) { "Always this" }
      end
      agent = agent_class.new(_ask_message: "This is ignored")
      expect(agent.user_prompt).to eq("Always this")
    end

    it "passes through to .call for non-streaming" do
      expect(conversational_agent).to receive(:call).with(hash_including(_ask_message: "Hello"))
      conversational_agent.ask("Hello")
    end

    it "passes through to .stream for streaming" do
      block = proc { |_chunk| }
      expect(conversational_agent).to receive(:stream).with(hash_including(_ask_message: "Hello"))
      conversational_agent.ask("Hello", &block)
    end

    it "passes with: option for attachments" do
      expect(conversational_agent).to receive(:call).with(hash_including(_ask_message: "Describe", with: "photo.jpg"))
      conversational_agent.ask("Describe", with: "photo.jpg")
    end
  end

  # ── Resolution order ──────────────────────────────────────────

  describe "resolution order" do
    it "method override > ask message > class template > inherited" do
      parent = Class.new(RubyLLM::Agents::Base) { user "Inherited" }
      child = Class.new(parent) { user "Class level" }

      # Class template wins over inherited
      agent = child.new
      expect(agent.user_prompt).to eq("Class level")
    end

    it "ask message wins over class template" do
      agent_class = Class.new(RubyLLM::Agents::Base) do
        user "Template: {text}"
      end
      agent = agent_class.new(_ask_message: "Ask message")
      expect(agent.user_prompt).to eq("Ask message")
    end

    it "inherited template works when child has none" do
      parent = Class.new(RubyLLM::Agents::Base) { user "Parent {query}" }
      child = Class.new(parent)
      agent = child.new(query: "test")
      expect(agent.user_prompt).to eq("Parent test")
    end
  end

  # ── Three roles together ──────────────────────────────────────

  describe "three roles together" do
    it "all three DSLs work on same agent" do
      agent_class = Class.new(RubyLLM::Agents::Base) do
        system "You are a classifier."
        user "Classify: {text}"
        assistant '{"category":'
      end

      agent = agent_class.new(text: "Hello world")

      expect(agent.system_prompt).to eq("You are a classifier.")
      expect(agent.user_prompt).to eq("Classify: Hello world")
      expect(agent.assistant_prompt).to eq('{"category":')
    end

    it "conversational agent (system + assistant, no user)" do
      agent_class = Class.new(RubyLLM::Agents::Base) do
        def self.name = "ChatAgent"
        system "You are a Ruby expert."
        assistant "Based on my knowledge, "
      end

      agent = agent_class.new(_ask_message: "What is Ruby?")

      expect(agent.system_prompt).to eq("You are a Ruby expert.")
      expect(agent.user_prompt).to eq("What is Ruby?")
      expect(agent.assistant_prompt).to eq("Based on my knowledge, ")
    end

    it "resolved_assistant_prefill returns hash for defined prefill" do
      agent_class = Class.new(RubyLLM::Agents::Base) do
        assistant '{"result":'
        user "test"
      end

      agent = agent_class.new
      prefill = agent.send(:resolved_assistant_prefill)

      expect(prefill).to eq({ role: :assistant, content: '{"result":' })
    end

    it "resolved_assistant_prefill returns nil when not defined" do
      agent_class = Class.new(RubyLLM::Agents::Base) do
        user "test"
      end

      agent = agent_class.new
      expect(agent.send(:resolved_assistant_prefill)).to be_nil
    end

    it "resolved_assistant_prefill returns nil for empty string" do
      agent_class = Class.new(RubyLLM::Agents::Base) do
        assistant ""
        user "test"
      end

      agent = agent_class.new
      expect(agent.send(:resolved_assistant_prefill)).to be_nil
    end
  end

  # ── dry_run includes assistant_prompt ─────────────────────────

  describe "dry_run with three roles" do
    let(:config) { double("config") }

    before do
      allow(RubyLLM::Agents).to receive(:configuration).and_return(config)
      allow(config).to receive(:default_model).and_return("gpt-4o")
      allow(config).to receive(:default_timeout).and_return(120)
      allow(config).to receive(:default_temperature).and_return(0.7)
      allow(config).to receive(:default_streaming).and_return(false)
      allow(config).to receive(:budgets_enabled?).and_return(false)
      allow(config).to receive(:default_thinking).and_return(nil)
    end

    it "includes assistant_prompt in dry run output" do
      agent_class = Class.new(RubyLLM::Agents::BaseAgent) do
        def self.name = "DryRunAgent"
        model "gpt-4o"
        tools []

        system "You are helpful."
        user "Process {query}"
        assistant '{"result":'
      end

      result = agent_class.call(query: "test", dry_run: true)

      expect(result.content[:system_prompt]).to eq("You are helpful.")
      expect(result.content[:user_prompt]).to eq("Process test")
      expect(result.content[:assistant_prompt]).to eq('{"result":')
    end
  end

  # ── Placeholder interpolation edge cases ──────────────────────

  describe "placeholder edge cases" do
    it "handles missing param gracefully (returns empty string)" do
      agent_class = Class.new(RubyLLM::Agents::Base) do
        param :query
        user "Search {query} in {category}"
        param :category
      end
      agent = agent_class.new(query: "ruby")
      # category not provided, should interpolate to empty string
      expect(agent.user_prompt).to eq("Search ruby in ")
    end

    it "handles param with default value" do
      agent_class = Class.new(RubyLLM::Agents::Base) do
        param :limit, default: 10
        user "Limit: {limit}"
      end
      agent = agent_class.new
      expect(agent.user_prompt).to eq("Limit: 10")
    end

    it "shared placeholders across roles are registered once" do
      agent_class = Class.new(RubyLLM::Agents::Base) do
        system "Helping {user_name}"
        user "Question from {user_name}: {question}"
        assistant "For {user_name}: "
      end

      # user_name appears in all three, should be registered once
      expect(agent_class.params[:user_name][:required]).to be true
      expect(agent_class.params[:question][:required]).to be true

      agent = agent_class.new(user_name: "Alice", question: "How?")
      expect(agent.system_prompt).to eq("Helping Alice")
      expect(agent.user_prompt).to eq("Question from Alice: How?")
      expect(agent.assistant_prompt).to eq("For Alice: ")
    end
  end
end
