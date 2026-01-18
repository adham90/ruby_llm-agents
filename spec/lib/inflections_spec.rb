# frozen_string_literal: true

require "rails_helper"

RSpec.describe "RubyLLM Inflections" do
  describe "ActiveSupport::Inflector" do
    describe "LLM acronym" do
      it "is registered as an acronym" do
        acronyms = ActiveSupport::Inflector.inflections.acronyms
        expect(acronyms).to have_key("llm")
        expect(acronyms["llm"]).to eq("LLM")
      end

      it "camelize handles LLM correctly" do
        expect("llm".camelize).to eq("LLM")
      end

      it "camelize handles prefix with LLM correctly" do
        expect("ruby_llm".camelize).to eq("RubyLLM")
      end

      it "camelize handles LLM in middle of string" do
        expect("my_llm_agent".camelize).to eq("MyLLMAgent")
      end

      it "camelize handles LLM at end of string" do
        expect("custom_llm".camelize).to eq("CustomLLM")
      end
    end

    describe "ruby_llm uncountable" do
      it "is registered as uncountable" do
        uncountables = ActiveSupport::Inflector.inflections.uncountables
        expect(uncountables).to include("ruby_llm")
      end

      it "pluralize does not change ruby_llm" do
        expect("ruby_llm".pluralize).to eq("ruby_llm")
      end

      it "singularize does not change ruby_llm" do
        expect("ruby_llm".singularize).to eq("ruby_llm")
      end
    end
  end

  describe "RubyLLMInflectionFix" do
    it "is defined" do
      expect(defined?(RubyLLMInflectionFix)).to eq("constant")
    end

    it "is prepended to String" do
      expect(String.ancestors).to include(RubyLLMInflectionFix)
    end

    it "prepends before String itself" do
      string_index = String.ancestors.index(String)
      fix_index = String.ancestors.index(RubyLLMInflectionFix)
      expect(fix_index).to be < string_index
    end
  end

  describe "String#underscore" do
    describe "RubyLLM handling" do
      it "converts RubyLLM to ruby_llm" do
        expect("RubyLLM".underscore).to eq("ruby_llm")
      end

      it "converts RubyLLM::Agents to ruby_llm/agents" do
        expect("RubyLLM::Agents".underscore).to eq("ruby_llm/agents")
      end

      it "converts RubyLLM::Agents::Base to ruby_llm/agents/base" do
        expect("RubyLLM::Agents::Base".underscore).to eq("ruby_llm/agents/base")
      end

      it "converts nested RubyLLM namespaces correctly" do
        expect("RubyLLM::Agents::Reliability::CircuitBreaker".underscore).to eq("ruby_llm/agents/reliability/circuit_breaker")
      end
    end

    describe "other LLM strings" do
      it "handles standalone LLM" do
        expect("LLM".underscore).to eq("llm")
      end

      it "handles MyLLM" do
        expect("MyLLM".underscore).to eq("my_llm")
      end

      it "handles LLMAgent" do
        expect("LLMAgent".underscore).to eq("llm_agent")
      end

      it "handles CustomLLMService" do
        expect("CustomLLMService".underscore).to eq("custom_llm_service")
      end
    end

    describe "regular strings unaffected" do
      it "handles regular camel case" do
        expect("MyClass".underscore).to eq("my_class")
      end

      it "handles multi-word camel case" do
        expect("MySpecialClassName".underscore).to eq("my_special_class_name")
      end

      it "handles namespaced classes" do
        expect("Foo::Bar::Baz".underscore).to eq("foo/bar/baz")
      end

      it "handles already underscored strings" do
        expect("already_underscored".underscore).to eq("already_underscored")
      end
    end

    describe "edge cases" do
      it "handles empty string" do
        expect("".underscore).to eq("")
      end

      it "handles single character" do
        expect("A".underscore).to eq("a")
      end

      it "handles lowercase string" do
        expect("lowercase".underscore).to eq("lowercase")
      end

      it "handles RubyLLM appearing multiple times" do
        # This is a contrived example but tests the gsub behavior
        result = "RubyLLMRubyLLM".underscore
        expect(result).to include("ruby_llm")
        expect(result).not_to include("rubyllm")
      end
    end
  end

  describe "camelize and underscore round-trip" do
    it "round-trips RubyLLM correctly" do
      original = "RubyLLM"
      underscored = original.underscore
      camelized = underscored.camelize

      expect(camelized).to eq(original)
    end

    it "round-trips RubyLLM::Agents correctly" do
      original = "RubyLLM::Agents"
      underscored = original.underscore
      camelized = underscored.camelize

      expect(camelized).to eq(original)
    end

    it "round-trips RubyLLM::Agents::Base correctly" do
      original = "RubyLLM::Agents::Base"
      underscored = original.underscore
      camelized = underscored.camelize

      expect(camelized).to eq(original)
    end

    it "round-trips complex namespace correctly" do
      original = "RubyLLM::Agents::Reliability::CircuitBreaker"
      underscored = original.underscore
      camelized = underscored.camelize

      expect(camelized).to eq(original)
    end
  end

  describe "constantize compatibility" do
    it "can constantize ruby_llm" do
      expect("ruby_llm".camelize.constantize).to eq(RubyLLM)
    end

    it "can constantize ruby_llm/agents" do
      expect("ruby_llm/agents".camelize.constantize).to eq(RubyLLM::Agents)
    end

    it "can constantize ruby_llm/agents/base" do
      expect("ruby_llm/agents/base".camelize.constantize).to eq(RubyLLM::Agents::Base)
    end
  end

  describe "Zeitwerk inflector configuration" do
    it "maps ruby_llm to RubyLLM in autoloaders" do
      # Check that at least one autoloader has the inflection configured
      inflections_found = Rails.autoloaders.any? do |autoloader|
        autoloader.inflector.camelize("ruby_llm", nil) == "RubyLLM"
      end

      expect(inflections_found).to be true
    end
  end

  describe "view path resolution" do
    it "generates correct view paths for RubyLLM::Agents" do
      path = "RubyLLM::Agents".underscore
      expect(path).to eq("ruby_llm/agents")
    end

    it "generates correct view paths for controllers" do
      path = "RubyLLM::Agents::DashboardController".underscore
      expect(path).to eq("ruby_llm/agents/dashboard_controller")
    end
  end
end
