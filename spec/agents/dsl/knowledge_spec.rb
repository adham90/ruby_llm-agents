# frozen_string_literal: true

require "rails_helper"

RSpec.describe RubyLLM::Agents::DSL::Knowledge do
  let(:knowledge_fixture_path) do
    File.expand_path("../../fixtures/knowledge", __dir__)
  end

  # --- Class-level DSL ---

  describe ".knows" do
    it "registers a static knowledge entry" do
      klass = Class.new(RubyLLM::Agents::Base) do
        knows :ruby_conventions
      end

      expect(klass.knowledge_entries.size).to eq(1)
      expect(klass.knowledge_entries.first[:name]).to eq(:ruby_conventions)
      expect(klass.knowledge_entries.first[:loader]).to be_nil
    end

    it "registers a dynamic knowledge entry with a block" do
      klass = Class.new(RubyLLM::Agents::Base) do
        knows(:custom_rules) { "some rules" }
      end

      expect(klass.knowledge_entries.size).to eq(1)
      expect(klass.knowledge_entries.first[:loader]).to be_a(Proc)
    end

    it "registers multiple static entries inline" do
      klass = Class.new(RubyLLM::Agents::Base) do
        knows :refund_policy, :shipping_faq, :pricing
      end

      expect(klass.knowledge_entries.size).to eq(3)
      expect(klass.knowledge_entries.map { |e| e[:name] })
        .to eq([:refund_policy, :shipping_faq, :pricing])
      expect(klass.knowledge_entries.all? { |e| e[:loader].nil? }).to be true
    end

    it "deduplicates entries by name" do
      klass = Class.new(RubyLLM::Agents::Base) do
        knows :rules
        knows(:rules) { "override" }
      end

      expect(klass.knowledge_entries.size).to eq(1)
      expect(klass.knowledge_entries.first[:loader]).to be_a(Proc)
    end
  end

  describe ".knowledge_path" do
    it "sets and returns a custom path" do
      klass = Class.new(RubyLLM::Agents::Base) do
        knowledge_path "custom/knowledge"
      end

      expect(klass.knowledge_path).to eq("custom/knowledge")
    end

    it "defaults to nil when not configured" do
      klass = Class.new(RubyLLM::Agents::Base)

      RubyLLM::Agents.reset_configuration!
      expect(klass.knowledge_path).to be_nil
    end

    it "inherits knowledge_path from parent class" do
      parent = Class.new(RubyLLM::Agents::Base) do
        knowledge_path "parent/knowledge"
      end

      child = Class.new(parent)

      expect(child.knowledge_path).to eq("parent/knowledge")
    end

    it "falls back to global configuration" do
      RubyLLM::Agents.reset_configuration!
      RubyLLM::Agents.configure do |config|
        config.knowledge_path = "global/knowledge"
      end

      klass = Class.new(RubyLLM::Agents::Base)
      expect(klass.knowledge_path).to eq("global/knowledge")
    ensure
      RubyLLM::Agents.reset_configuration!
    end
  end

  describe ".knowledge_entries inheritance" do
    it "inherits entries from parent class" do
      parent = Class.new(RubyLLM::Agents::Base) do
        knows :parent_rules
      end

      child = Class.new(parent) do
        knows :child_rules
      end

      expect(child.knowledge_entries.map { |e| e[:name] })
        .to eq([:parent_rules, :child_rules])
    end

    it "does not modify parent when child adds entries" do
      parent = Class.new(RubyLLM::Agents::Base) do
        knows :parent_rules
      end

      Class.new(parent) do
        knows :child_rules
      end

      expect(parent.knowledge_entries.size).to eq(1)
    end

    it "allows child to override parent entry by name" do
      parent = Class.new(RubyLLM::Agents::Base) do
        knows :shared_rules
      end

      child = Class.new(parent) do
        knows(:shared_rules) { "child version" }
      end

      expect(child.knowledge_entries.size).to eq(1)
      expect(child.knowledge_entries.first[:loader]).to be_a(Proc)
    end
  end

  # --- Instance-level resolution ---

  describe "#compiled_knowledge" do
    it "loads static knowledge from a markdown file" do
      klass = Class.new(RubyLLM::Agents::Base) do
        knows :ruby_conventions
      end
      klass.knowledge_path(knowledge_fixture_path)

      agent = klass.new
      knowledge = agent.compiled_knowledge

      expect(knowledge).to include("Ruby Conventions")
      expect(knowledge).to include("Use 2-space indentation")
    end

    it "returns empty string when knowledge file not found" do
      klass = Class.new(RubyLLM::Agents::Base) do
        knowledge_path "nonexistent/path"
        knows :missing
      end

      agent = klass.new
      expect(agent.compiled_knowledge).to eq("")
    end

    it "returns empty string when knowledge_path is nil for static entry" do
      RubyLLM::Agents.reset_configuration!
      klass = Class.new(RubyLLM::Agents::Base) do
        knows :some_file
      end

      agent = klass.new
      expect(agent.compiled_knowledge).to eq("")
    end

    it "evaluates dynamic block at call time" do
      call_count = 0
      klass = Class.new(RubyLLM::Agents::Base) do
        knows(:counter) do
          call_count += 1
          "Call ##{call_count}"
        end
      end

      agent = klass.new
      expect(agent.compiled_knowledge).to include("Call #1")
      expect(agent.compiled_knowledge).to include("Call #2")
    end

    it "formats array results as bullet list" do
      klass = Class.new(RubyLLM::Agents::Base) do
        knows(:rules) { ["Rule one", "Rule two"] }
      end

      agent = klass.new
      knowledge = agent.compiled_knowledge

      expect(knowledge).to include("- Rule one")
      expect(knowledge).to include("- Rule two")
    end

    it "formats string results directly" do
      klass = Class.new(RubyLLM::Agents::Base) do
        knows(:rules) { "Use RSpec, not Minitest" }
      end

      agent = klass.new
      expect(agent.compiled_knowledge).to include("Use RSpec, not Minitest")
    end

    it "skips nil results from dynamic block" do
      klass = Class.new(RubyLLM::Agents::Base) do
        knows(:nothing) { nil }
      end

      agent = klass.new
      expect(agent.compiled_knowledge).to eq("")
    end

    it "combines static and dynamic knowledge with separators" do
      klass = Class.new(RubyLLM::Agents::Base) do
        knows :ruby_conventions
        knows(:team_rules) { "Use RSpec, not Minitest" }
      end
      klass.knowledge_path(knowledge_fixture_path)

      agent = klass.new
      knowledge = agent.compiled_knowledge

      expect(knowledge).to include("Ruby Conventions")
      expect(knowledge).to include("Use RSpec, not Minitest")
      expect(knowledge).to include("---")
    end

    it "returns empty string when no knowledge declared" do
      klass = Class.new(RubyLLM::Agents::Base)
      agent = klass.new
      expect(agent.compiled_knowledge).to eq("")
    end

    it "skips entry when if: condition returns false" do
      klass = Class.new(RubyLLM::Agents::Base) do
        knows(:included) { "secret" }
        knows :excluded, if: -> { false }
      end

      agent = klass.new
      knowledge = agent.compiled_knowledge

      expect(knowledge).to include("secret")
      expect(knowledge).not_to include("Excluded")
    end

    it "includes entry when if: condition returns true" do
      klass = Class.new(RubyLLM::Agents::Base) do
        knows(:gated, if: -> { true }) { "included" }
      end

      agent = klass.new
      expect(agent.compiled_knowledge).to include("included")
    end

    it "evaluates if: condition via instance_exec with agent context" do
      klass = Class.new(RubyLLM::Agents::Base) do
        param :premium, default: false
        knows(:premium_faq, if: -> { premium }) { "Premium content" }
      end

      regular = klass.new(premium: false)
      expect(regular.compiled_knowledge).to eq("")

      premium_agent = klass.new(premium: true)
      expect(premium_agent.compiled_knowledge).to include("Premium content")
    end

    it "runs dynamic blocks in the agent instance context" do
      klass = Class.new(RubyLLM::Agents::Base) do
        knows(:self_check) { self.class.name || "anonymous" }
      end

      agent = klass.new
      expect(agent.compiled_knowledge).not_to be_empty
    end

    it "falls back to file without .md extension" do
      klass = Class.new(RubyLLM::Agents::Base) do
        knows :plain_rules
      end
      klass.knowledge_path(knowledge_fixture_path)

      agent = klass.new
      expect(agent.compiled_knowledge).to include("plain text rules without a .md extension")
    end

    it "converts non-string non-array results via to_s" do
      klass = Class.new(RubyLLM::Agents::Base) do
        knows(:count) { 42 }
      end

      agent = klass.new
      expect(agent.compiled_knowledge).to include("42")
    end

    it "skips empty array results" do
      klass = Class.new(RubyLLM::Agents::Base) do
        knows(:empty) { [] }
      end

      agent = klass.new
      expect(agent.compiled_knowledge).to eq("")
    end

    it "applies if: condition to static file entries" do
      klass = Class.new(RubyLLM::Agents::Base) do
        param :include_conventions, default: false
        knows :ruby_conventions, if: -> { include_conventions }
      end
      klass.knowledge_path(knowledge_fixture_path)

      without = klass.new(include_conventions: false)
      expect(without.compiled_knowledge).to eq("")

      with = klass.new(include_conventions: true)
      expect(with.compiled_knowledge).to include("Use 2-space indentation")
    end

    it "accesses agent params from dynamic blocks" do
      klass = Class.new(RubyLLM::Agents::Base) do
        param :topic, required: true
        knows(:context) { "The topic is #{topic}" }
      end

      agent = klass.new(topic: "testing")
      expect(agent.compiled_knowledge).to include("The topic is testing")
    end
  end

  # --- Integration with system prompt ---

  describe "system prompt integration" do
    it "auto-appends knowledge when using the system DSL" do
      klass = Class.new(RubyLLM::Agents::Base) do
        system "You are a helpful assistant."
        knows(:rules) { "Always be polite." }
      end

      agent = klass.new
      prompt = agent.system_prompt

      expect(prompt).to include("You are a helpful assistant.")
      expect(prompt).to include("Always be polite.")
    end

    it "preserves placeholder interpolation in system prompt" do
      klass = Class.new(RubyLLM::Agents::Base) do
        system "You help {user_name} with tasks."
        knows(:rules) { "Be concise." }
      end

      agent = klass.new(user_name: "Alice")
      prompt = agent.system_prompt

      expect(prompt).to include("You help Alice with tasks.")
      expect(prompt).to include("Be concise.")
    end

    it "returns knowledge alone when no system DSL is set" do
      klass = Class.new(RubyLLM::Agents::Base) do
        knows(:rules) { "Always be polite." }
      end

      agent = klass.new
      prompt = agent.system_prompt

      expect(prompt).to include("Always be polite.")
    end

    it "returns nil when no system DSL and no knowledge" do
      klass = Class.new(RubyLLM::Agents::Base)
      agent = klass.new
      expect(agent.system_prompt).to be_nil
    end

    it "works with .ask() flow" do
      klass = Class.new(RubyLLM::Agents::Base) do
        system "You are a coding assistant."
        knows(:rules) { "Use Ruby 3.1+ syntax." }
      end

      agent = klass.new
      expect(agent.system_prompt).to include("Use Ruby 3.1+ syntax.")
      expect(agent.system_prompt).to include("You are a coding assistant.")
    end
  end
end
