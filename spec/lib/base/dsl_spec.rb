# frozen_string_literal: true

require "rails_helper"

RSpec.describe RubyLLM::Agents::Base::DSL do
  # Helper to create a fresh agent class for each test
  def create_agent_class(&block)
    Class.new(RubyLLM::Agents::Base) do
      class_eval(&block) if block
    end
  end

  describe "constants" do
    it "defines VERSION constant" do
      expect(described_class::VERSION).to eq("1.0")
    end

    it "defines CACHE_TTL constant" do
      expect(described_class::CACHE_TTL).to eq(1.hour)
    end
  end

  describe ".description" do
    it "sets and gets the description" do
      klass = create_agent_class do
        description "Searches the knowledge base"
      end
      expect(klass.description).to eq("Searches the knowledge base")
    end

    it "defaults to nil" do
      klass = create_agent_class
      expect(klass.description).to be_nil
    end

    it "inherits from parent" do
      parent = create_agent_class { description "Parent description" }
      child = Class.new(parent)
      expect(child.description).to eq("Parent description")
    end

    it "can override parent description" do
      parent = create_agent_class { description "Parent description" }
      child = Class.new(parent) { description "Child description" }
      expect(child.description).to eq("Child description")
    end
  end

  describe ".timeout" do
    it "sets and gets the timeout" do
      klass = create_agent_class { timeout 30 }
      expect(klass.timeout).to eq(30)
    end

    it "inherits from parent" do
      parent = create_agent_class { timeout 60 }
      child = Class.new(parent)
      expect(child.timeout).to eq(60)
    end

    it "falls back to configuration default" do
      klass = create_agent_class
      expect(klass.timeout).to eq(RubyLLM::Agents.configuration.default_timeout)
    end

    it "can override parent timeout" do
      parent = create_agent_class { timeout 60 }
      child = Class.new(parent) { timeout 30 }
      expect(child.timeout).to eq(30)
    end
  end

  describe ".model" do
    it "falls back to configuration default" do
      klass = create_agent_class
      expect(klass.model).to eq(RubyLLM::Agents.configuration.default_model)
    end

    it "can be overridden in child class" do
      parent = create_agent_class { model "gpt-4" }
      child = Class.new(parent) { model "claude-3" }
      expect(child.model).to eq("claude-3")
      expect(parent.model).to eq("gpt-4") # Parent unchanged
    end
  end

  describe ".temperature" do
    it "falls back to configuration default" do
      klass = create_agent_class
      expect(klass.temperature).to eq(RubyLLM::Agents.configuration.default_temperature)
    end

    it "inherits from parent" do
      parent = create_agent_class { temperature 0.5 }
      child = Class.new(parent)
      expect(child.temperature).to eq(0.5)
    end
  end

  describe "deep inheritance" do
    it "inherits through multiple levels" do
      grandparent = create_agent_class do
        model "gpt-4"
        temperature 0.7
        version "1.0"
      end
      parent = Class.new(grandparent)
      child = Class.new(parent)

      expect(child.model).to eq("gpt-4")
      expect(child.temperature).to eq(0.7)
      expect(child.version).to eq("1.0")
    end

    it "allows overriding at any level" do
      grandparent = create_agent_class { model "gpt-4" }
      parent = Class.new(grandparent) { model "claude-3" }
      child = Class.new(parent) { model "gemini-pro" }

      expect(grandparent.model).to eq("gpt-4")
      expect(parent.model).to eq("claude-3")
      expect(child.model).to eq("gemini-pro")
    end
  end

  describe "Caching DSL" do
    describe ".cache_for" do
      it "enables caching" do
        klass = create_agent_class { cache_for 1.hour }
        expect(klass.cache_enabled?).to be true
      end

      it "sets cache TTL" do
        klass = create_agent_class { cache_for 30.minutes }
        expect(klass.cache_ttl).to eq(30.minutes)
      end
    end

    describe ".cache" do
      it "emits deprecation warning" do
        expect(RubyLLM::Agents::Deprecations).to receive(:warn).with(
          /cache\(ttl\) is deprecated/,
          kind_of(Array)
        )

        create_agent_class { cache 1.hour }
      end

      it "still enables caching via cache_for" do
        RubyLLM::Agents::Deprecations.silence do
          klass = create_agent_class { cache 2.hours }
          expect(klass.cache_enabled?).to be true
          expect(klass.cache_ttl).to eq(2.hours)
        end
      end

      it "uses default TTL when called without argument" do
        RubyLLM::Agents::Deprecations.silence do
          klass = create_agent_class { cache }
          expect(klass.cache_ttl).to eq(1.hour) # CACHE_TTL constant
        end
      end
    end

    describe ".cache_enabled?" do
      it "returns false by default" do
        klass = create_agent_class
        expect(klass.cache_enabled?).to be false
      end

      it "returns true after cache_for is called" do
        klass = create_agent_class { cache_for 1.hour }
        expect(klass.cache_enabled?).to be true
      end
    end

    describe ".cache_ttl" do
      it "returns default TTL when not set" do
        klass = create_agent_class
        expect(klass.cache_ttl).to eq(1.hour)
      end

      it "returns configured TTL" do
        klass = create_agent_class { cache_for 15.minutes }
        expect(klass.cache_ttl).to eq(15.minutes)
      end
    end
  end

  describe "Reliability DSL" do
    describe ".reliability block" do
      it "configures retries via block" do
        klass = create_agent_class do
          reliability do
            retries max: 3, backoff: :exponential
          end
        end

        config = klass.retries_config
        expect(config[:max]).to eq(3)
        expect(config[:backoff]).to eq(:exponential)
      end

      it "configures fallback_models via block" do
        klass = create_agent_class do
          reliability do
            fallback_models "claude-3", "gemini-pro"
          end
        end

        expect(klass.fallback_models).to eq(%w[claude-3 gemini-pro])
      end

      it "configures total_timeout via block" do
        klass = create_agent_class do
          reliability do
            total_timeout 30
          end
        end

        expect(klass.total_timeout).to eq(30)
      end

      it "configures circuit_breaker via block" do
        klass = create_agent_class do
          reliability do
            circuit_breaker errors: 5, within: 120, cooldown: 60
          end
        end

        config = klass.circuit_breaker_config
        expect(config[:errors]).to eq(5)
        expect(config[:within]).to eq(120)
        expect(config[:cooldown]).to eq(60)
      end

      it "configures multiple options in one block" do
        klass = create_agent_class do
          reliability do
            retries max: 2
            fallback_models "backup-model"
            total_timeout 20
            circuit_breaker errors: 3
          end
        end

        expect(klass.retries_config[:max]).to eq(2)
        expect(klass.fallback_models).to eq(["backup-model"])
        expect(klass.total_timeout).to eq(20)
        expect(klass.circuit_breaker_config[:errors]).to eq(3)
      end
    end

    describe ".retries" do
      it "sets max retries" do
        klass = create_agent_class { retries max: 5 }
        expect(klass.retries_config[:max]).to eq(5)
      end

      it "sets backoff strategy" do
        klass = create_agent_class { retries backoff: :constant }
        expect(klass.retries_config[:backoff]).to eq(:constant)
      end

      it "sets base delay" do
        klass = create_agent_class { retries base: 0.5 }
        expect(klass.retries_config[:base]).to eq(0.5)
      end

      it "sets max delay" do
        klass = create_agent_class { retries max_delay: 10.0 }
        expect(klass.retries_config[:max_delay]).to eq(10.0)
      end

      it "sets custom error classes" do
        custom_error = Class.new(StandardError)
        klass = create_agent_class { retries on: [custom_error] }
        expect(klass.retries_config[:on]).to eq([custom_error])
      end

      it "merges with default config" do
        klass = create_agent_class { retries max: 3 }
        config = klass.retries_config

        # Should have max from our setting
        expect(config[:max]).to eq(3)
        # Should preserve other defaults from configuration
        expect(config).to have_key(:backoff)
      end

      it "returns config when called without arguments" do
        klass = create_agent_class { retries max: 2 }
        expect(klass.retries).to eq(klass.retries_config)
      end
    end

    describe ".retries_config" do
      it "returns nil when not configured" do
        klass = create_agent_class
        expect(klass.retries_config).to be_nil
      end

      it "inherits from parent" do
        parent = create_agent_class { retries max: 4 }
        child = Class.new(parent)
        expect(child.retries_config[:max]).to eq(4)
      end

      it "returns configured value when set" do
        klass = create_agent_class { retries max: 2 }
        expect(klass.retries_config[:max]).to eq(2)
      end
    end

    describe ".fallback_models" do
      it "sets fallback models as array" do
        klass = create_agent_class { fallback_models ["claude-3", "gemini"] }
        expect(klass.fallback_models).to eq(["claude-3", "gemini"])
      end

      it "inherits from parent" do
        parent = create_agent_class { fallback_models ["backup"] }
        child = Class.new(parent)
        expect(child.fallback_models).to eq(["backup"])
      end

      it "falls back to configuration default" do
        klass = create_agent_class
        expect(klass.fallback_models).to eq(RubyLLM::Agents.configuration.default_fallback_models)
      end

      it "can override parent" do
        parent = create_agent_class { fallback_models ["parent-backup"] }
        child = Class.new(parent) { fallback_models ["child-backup"] }
        expect(child.fallback_models).to eq(["child-backup"])
      end
    end

    describe ".total_timeout" do
      it "sets total timeout" do
        klass = create_agent_class { total_timeout 45 }
        expect(klass.total_timeout).to eq(45)
      end

      it "inherits from parent" do
        parent = create_agent_class { total_timeout 60 }
        child = Class.new(parent)
        expect(child.total_timeout).to eq(60)
      end

      it "falls back to configuration default" do
        klass = create_agent_class
        expect(klass.total_timeout).to eq(RubyLLM::Agents.configuration.default_total_timeout)
      end
    end

    describe ".circuit_breaker" do
      it "sets errors threshold" do
        klass = create_agent_class { circuit_breaker errors: 5 }
        expect(klass.circuit_breaker_config[:errors]).to eq(5)
      end

      it "sets within window" do
        klass = create_agent_class { circuit_breaker within: 120 }
        expect(klass.circuit_breaker_config[:within]).to eq(120)
      end

      it "sets cooldown period" do
        klass = create_agent_class { circuit_breaker cooldown: 600 }
        expect(klass.circuit_breaker_config[:cooldown]).to eq(600)
      end

      it "uses default values for unspecified options" do
        klass = create_agent_class { circuit_breaker errors: 3 }
        config = klass.circuit_breaker_config

        expect(config[:errors]).to eq(3)
        expect(config[:within]).to eq(60)   # default
        expect(config[:cooldown]).to eq(300) # default
      end

      it "returns nil when not configured" do
        klass = create_agent_class
        expect(klass.circuit_breaker_config).to be_nil
      end
    end

    describe ".circuit_breaker_config" do
      it "inherits from parent" do
        parent = create_agent_class { circuit_breaker errors: 10 }
        child = Class.new(parent)
        expect(child.circuit_breaker_config[:errors]).to eq(10)
      end
    end
  end

  describe "Parameter DSL" do
    describe ".param" do
      it "defines required parameter" do
        klass = create_agent_class { param :query, required: true }
        expect(klass.params[:query][:required]).to be true
      end

      it "defines parameter with default" do
        klass = create_agent_class { param :limit, default: 10 }
        expect(klass.params[:limit][:default]).to eq(10)
      end

      it "defines parameter with type" do
        klass = create_agent_class { param :count, type: Integer }
        expect(klass.params[:count][:type]).to eq(Integer)
      end

      it "creates accessor method" do
        klass = create_agent_class do
          param :name, default: "test"

          def user_prompt
            name
          end
        end

        agent = klass.new
        expect(agent.name).to eq("test")
      end

      it "accessor returns option value over default" do
        klass = create_agent_class do
          param :name, default: "default"

          def user_prompt
            name
          end
        end

        agent = klass.new(name: "custom")
        expect(agent.name).to eq("custom")
      end

      it "accessor handles string keys in options" do
        klass = create_agent_class do
          param :name, default: "default"

          def user_prompt
            name
          end
        end

        agent = klass.new("name" => "string_key")
        expect(agent.name).to eq("string_key")
      end

      it "stores full param definition" do
        klass = create_agent_class do
          param :data, required: true, default: {}, type: Hash
        end

        definition = klass.params[:data]
        expect(definition[:required]).to be true
        expect(definition[:default]).to eq({})
        expect(definition[:type]).to eq(Hash)
      end
    end

    describe ".params" do
      it "returns empty hash when no params defined" do
        klass = create_agent_class
        expect(klass.params).to eq({})
      end

      it "merges parent and child params" do
        parent = create_agent_class { param :parent_param, default: 1 }
        child = Class.new(parent) { param :child_param, default: 2 }

        expect(child.params.keys).to contain_exactly(:parent_param, :child_param)
      end

      it "child can override parent param" do
        parent = create_agent_class { param :shared, default: "parent" }
        child = Class.new(parent) { param :shared, default: "child" }

        expect(parent.params[:shared][:default]).to eq("parent")
        expect(child.params[:shared][:default]).to eq("child")
      end

      it "does not modify parent params" do
        parent = create_agent_class { param :original, default: 1 }
        Class.new(parent) { param :added, default: 2 }

        expect(parent.params.keys).to eq([:original])
      end
    end
  end

  describe "Streaming DSL" do
    describe ".streaming" do
      it "enables streaming" do
        klass = create_agent_class { streaming true }
        expect(klass.streaming).to be true
      end

      it "disables streaming" do
        klass = create_agent_class { streaming false }
        expect(klass.streaming).to be false
      end

      it "defaults to configuration value" do
        klass = create_agent_class
        expect(klass.streaming).to eq(RubyLLM::Agents.configuration.default_streaming)
      end

      it "inherits from parent" do
        parent = create_agent_class { streaming true }
        child = Class.new(parent)
        expect(child.streaming).to be true
      end

      it "can override parent" do
        parent = create_agent_class { streaming true }
        child = Class.new(parent) { streaming false }
        expect(child.streaming).to be false
      end
    end
  end

  describe "Tools DSL" do
    let(:mock_tool) { Class.new { def self.name; "MockTool"; end } }
    let(:another_tool) { Class.new { def self.name; "AnotherTool"; end } }

    describe ".tools" do
      it "wraps single tool in array" do
        tool = mock_tool
        klass = create_agent_class { tools [tool] }
        expect(klass.tools).to eq([tool])
      end

      it "accepts array of tools" do
        tools = [mock_tool, another_tool]
        klass = create_agent_class { tools tools }
        expect(klass.tools).to eq(tools)
      end

      it "inherits from parent" do
        tool = mock_tool
        parent = create_agent_class { tools [tool] }
        child = Class.new(parent)
        expect(child.tools).to include(tool)
      end

      it "can override parent tools" do
        parent_tool = mock_tool
        child_tool = another_tool

        parent = create_agent_class { tools [parent_tool] }
        child = Class.new(parent) { tools [child_tool] }

        expect(child.tools).to eq([child_tool])
        expect(child.tools).not_to include(parent_tool)
      end

      it "falls back to configuration default" do
        klass = create_agent_class
        expect(klass.tools).to eq(RubyLLM::Agents.configuration.default_tools)
      end
    end
  end

  describe "#inherited_or_default" do
    it "returns superclass value when available" do
      parent = create_agent_class { model "parent-model" }
      child = Class.new(parent)

      # Access via model which uses inherited_or_default
      expect(child.model).to eq("parent-model")
    end

    it "returns default when superclass does not respond" do
      klass = create_agent_class
      # When not set and no parent, falls back to config default
      expect(klass.model).to eq(RubyLLM::Agents.configuration.default_model)
    end
  end

  describe "complete agent configuration" do
    it "supports full configuration" do
      tool = Class.new { def self.name; "TestTool"; end }

      klass = create_agent_class do
        model "gpt-4o"
        temperature 0.8
        version "2.0"
        description "A fully configured agent"
        timeout 45

        cache_for 2.hours
        streaming true
        tools [tool]

        param :query, required: true
        param :limit, default: 10, type: Integer

        reliability do
          retries max: 3, backoff: :exponential, base: 0.5
          fallback_models "claude-3-sonnet"
          total_timeout 60
          circuit_breaker errors: 5, within: 120, cooldown: 300
        end
      end

      expect(klass.model).to eq("gpt-4o")
      expect(klass.temperature).to eq(0.8)
      expect(klass.version).to eq("2.0")
      expect(klass.description).to eq("A fully configured agent")
      expect(klass.timeout).to eq(45)
      expect(klass.cache_enabled?).to be true
      expect(klass.cache_ttl).to eq(2.hours)
      expect(klass.streaming).to be true
      expect(klass.tools).to include(tool)
      expect(klass.params[:query][:required]).to be true
      expect(klass.params[:limit][:default]).to eq(10)
      expect(klass.retries_config[:max]).to eq(3)
      expect(klass.fallback_models).to eq(["claude-3-sonnet"])
      expect(klass.total_timeout).to eq(60)
      expect(klass.circuit_breaker_config[:errors]).to eq(5)
    end
  end
end
