# frozen_string_literal: true

require "rails_helper"

RSpec.describe "DSL overridable: keyword" do
  before do
    RubyLLM::Agents.reset_configuration!
    # Clean up any overrides from previous tests
    RubyLLM::Agents::AgentOverride.delete_all
  end

  describe ".model with overridable: true" do
    it "registers the field as overridable" do
      klass = Class.new(RubyLLM::Agents::Base) do
        model "gpt-4o", overridable: true
      end

      expect(klass.overridable_fields).to include(:model)
    end

    it "returns the code value when no override exists" do
      klass = Class.new(RubyLLM::Agents::Base) do
        model "gpt-4o", overridable: true
      end
      klass.clear_override_cache!

      expect(klass.model).to eq("gpt-4o")
    end

    it "returns the override value when one exists" do
      klass = Class.new(RubyLLM::Agents::Base) do
        def self.name = "OverridableModelAgent"

        model "gpt-4o", overridable: true
      end

      RubyLLM::Agents::AgentOverride.create!(
        agent_type: "OverridableModelAgent",
        settings: {"model" => "claude-sonnet-4-5"}
      )
      klass.clear_override_cache!

      expect(klass.model).to eq("claude-sonnet-4-5")
    end
  end

  describe ".model without overridable" do
    it "does not register the field as overridable" do
      klass = Class.new(RubyLLM::Agents::Base) do
        model "gpt-4o"
      end

      expect(klass.overridable_fields).not_to include(:model)
    end

    it "ignores overrides even if they exist in the database" do
      klass = Class.new(RubyLLM::Agents::Base) do
        def self.name = "LockedModelAgent"

        model "gpt-4o"
      end

      RubyLLM::Agents::AgentOverride.create!(
        agent_type: "LockedModelAgent",
        settings: {"model" => "claude-sonnet-4-5"}
      )
      klass.clear_override_cache!

      expect(klass.model).to eq("gpt-4o")
    end
  end

  describe ".temperature with overridable: true" do
    it "registers the field and applies overrides" do
      klass = Class.new(RubyLLM::Agents::Base) do
        def self.name = "OverridableTempAgent"

        temperature 0.7, overridable: true
      end

      RubyLLM::Agents::AgentOverride.create!(
        agent_type: "OverridableTempAgent",
        settings: {"temperature" => 0.3}
      )
      klass.clear_override_cache!

      expect(klass.overridable_fields).to include(:temperature)
      expect(klass.temperature).to eq(0.3)
    end
  end

  describe ".timeout with overridable: true" do
    it "registers the field and applies overrides" do
      klass = Class.new(RubyLLM::Agents::Base) do
        def self.name = "OverridableTimeoutAgent"

        timeout 30, overridable: true
      end

      RubyLLM::Agents::AgentOverride.create!(
        agent_type: "OverridableTimeoutAgent",
        settings: {"timeout" => 60}
      )
      klass.clear_override_cache!

      expect(klass.overridable_fields).to include(:timeout)
      expect(klass.timeout).to eq(60)
    end
  end

  describe ".streaming with overridable: true" do
    it "registers the field and applies overrides" do
      klass = Class.new(RubyLLM::Agents::Base) do
        def self.name = "OverridableStreamAgent"

        streaming false, overridable: true
      end

      RubyLLM::Agents::AgentOverride.create!(
        agent_type: "OverridableStreamAgent",
        settings: {"streaming" => true}
      )
      klass.clear_override_cache!

      expect(klass.overridable_fields).to include(:streaming)
      expect(klass.streaming).to be true
    end
  end

  describe ".overridable_fields" do
    it "returns empty array when nothing is overridable" do
      klass = Class.new(RubyLLM::Agents::Base) do
        model "gpt-4o"
      end

      expect(klass.overridable_fields).to eq([])
    end

    it "includes all registered overridable fields" do
      klass = Class.new(RubyLLM::Agents::Base) do
        model "gpt-4o", overridable: true
        temperature 0.7, overridable: true
        timeout 30
      end

      expect(klass.overridable_fields).to contain_exactly(:model, :temperature)
    end

    it "inherits overridable fields from parent" do
      parent = Class.new(RubyLLM::Agents::Base) do
        model "gpt-4o", overridable: true
      end
      child = Class.new(parent) do
        temperature 0.5, overridable: true
      end

      expect(child.overridable_fields).to contain_exactly(:model, :temperature)
    end
  end

  describe ".overridable?" do
    it "returns false when no fields are overridable" do
      klass = Class.new(RubyLLM::Agents::Base) do
        model "gpt-4o"
      end

      expect(klass.overridable?).to be false
    end

    it "returns true when at least one field is overridable" do
      klass = Class.new(RubyLLM::Agents::Base) do
        model "gpt-4o", overridable: true
      end

      expect(klass.overridable?).to be true
    end
  end

  describe ".active_overrides" do
    it "returns only overrides for fields that are overridable" do
      klass = Class.new(RubyLLM::Agents::Base) do
        def self.name = "SelectiveOverrideAgent"

        model "gpt-4o", overridable: true
        temperature 0.7
      end

      RubyLLM::Agents::AgentOverride.create!(
        agent_type: "SelectiveOverrideAgent",
        settings: {"model" => "gpt-4o-mini", "temperature" => 0.1}
      )
      klass.clear_override_cache!

      overrides = klass.active_overrides
      expect(overrides).to include("model" => "gpt-4o-mini")
      expect(overrides).not_to have_key("temperature")
    end

    it "returns empty hash when no overrides exist" do
      klass = Class.new(RubyLLM::Agents::Base) do
        model "gpt-4o", overridable: true
      end
      klass.clear_override_cache!

      expect(klass.active_overrides).to eq({})
    end
  end

  describe ".clear_override_cache!" do
    it "forces reload of overrides on next access" do
      klass = Class.new(RubyLLM::Agents::Base) do
        def self.name = "CacheBustAgent"

        model "gpt-4o", overridable: true
      end
      klass.clear_override_cache!

      # First access — no override
      expect(klass.model).to eq("gpt-4o")

      # Create override
      RubyLLM::Agents::AgentOverride.create!(
        agent_type: "CacheBustAgent",
        settings: {"model" => "gpt-4o-mini"}
      )

      # Still cached
      expect(klass.model).to eq("gpt-4o")

      # Bust cache
      klass.clear_override_cache!
      expect(klass.model).to eq("gpt-4o-mini")
    end
  end

  describe "call-site argument wins over override" do
    it "uses the model passed at initialization over the override" do
      klass = Class.new(RubyLLM::Agents::Base) do
        def self.name = "CallSiteWinsAgent"

        model "gpt-4o", overridable: true
        system "You are a test agent."
        user "Hello {name}"
      end

      RubyLLM::Agents::AgentOverride.create!(
        agent_type: "CallSiteWinsAgent",
        settings: {"model" => "gpt-4o-mini"}
      )
      klass.clear_override_cache!

      # The class-level getter returns the override
      expect(klass.model).to eq("gpt-4o-mini")

      # But an instance created with an explicit model uses that
      instance = klass.new(model: "claude-opus-4", name: "test")
      expect(instance.model).to eq("claude-opus-4")
    end
  end
end
