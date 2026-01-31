# frozen_string_literal: true

require "rails_helper"

RSpec.describe RubyLLM::Agents::DSL::Base do
  let(:test_class) do
    Class.new do
      extend RubyLLM::Agents::DSL::Base

      def self.name
        "TestAgent"
      end
    end
  end

  let(:config) { double("config") }

  before do
    allow(RubyLLM::Agents).to receive(:configuration).and_return(config)
    allow(config).to receive(:default_model).and_return("gpt-4o")
    allow(config).to receive(:default_timeout).and_return(120)
  end

  describe "#model" do
    it "returns default model when not set" do
      expect(test_class.model).to eq("gpt-4o")
    end

    it "sets and returns the model" do
      test_class.model("claude-3-opus")
      expect(test_class.model).to eq("claude-3-opus")
    end

    it "inherits from parent class" do
      test_class.model("gpt-4o-mini")

      child_class = Class.new(test_class)
      expect(child_class.model).to eq("gpt-4o-mini")
    end

    it "allows child class to override parent" do
      test_class.model("gpt-4o-mini")

      child_class = Class.new(test_class) do
        model "claude-3-sonnet"
      end
      expect(child_class.model).to eq("claude-3-sonnet")
    end
  end

  describe "#version" do
    it "returns default version when not set" do
      expect(test_class.version).to eq("1.0")
    end

    it "sets and returns the version" do
      test_class.version("2.5")
      expect(test_class.version).to eq("2.5")
    end

    it "inherits from parent class" do
      test_class.version("3.0")

      child_class = Class.new(test_class)
      expect(child_class.version).to eq("3.0")
    end
  end

  describe "#description" do
    it "returns nil when not set" do
      expect(test_class.description).to be_nil
    end

    it "sets and returns the description" do
      test_class.description("A helpful assistant")
      expect(test_class.description).to eq("A helpful assistant")
    end

    it "inherits from parent class" do
      test_class.description("Parent description")

      child_class = Class.new(test_class)
      expect(child_class.description).to eq("Parent description")
    end
  end

  describe "#timeout" do
    it "returns default timeout when not set" do
      expect(test_class.timeout).to eq(120)
    end

    it "sets and returns the timeout" do
      test_class.timeout(60)
      expect(test_class.timeout).to eq(60)
    end

    it "inherits from parent class" do
      test_class.timeout(30)

      child_class = Class.new(test_class)
      expect(child_class.timeout).to eq(30)
    end
  end

  describe "#schema" do
    it "returns nil when not set" do
      expect(test_class.schema).to be_nil
    end

    it "sets schema from a block using RubyLLM::Schema DSL" do
      test_class.schema do
        string :name, description: "A name"
      end
      expect(test_class.schema).to be_present
      expect(test_class.schema.properties).to include(:name)
    end

    it "sets schema from a hash" do
      hash_schema = { type: "object", properties: { name: { type: "string" } } }
      test_class.schema(hash_schema)
      expect(test_class.schema).to eq(hash_schema)
    end

    it "inherits from parent class" do
      test_class.schema do
        string :name, description: "A name"
      end

      child_class = Class.new(test_class)
      expect(child_class.schema).to eq(test_class.schema)
    end

    it "allows child class to override parent schema" do
      test_class.schema do
        string :name, description: "A name"
      end

      child_class = Class.new(test_class) do
        schema do
          integer :age, description: "An age"
        end
      end

      expect(child_class.schema).not_to eq(test_class.schema)
      expect(child_class.schema.properties).to include(:age)
    end
  end

  describe "configuration fallback" do
    it "falls back to hardcoded defaults if configuration fails" do
      allow(RubyLLM::Agents).to receive(:configuration).and_raise(StandardError)

      fresh_class = Class.new do
        extend RubyLLM::Agents::DSL::Base
      end

      expect(fresh_class.model).to eq("gpt-4o")
      expect(fresh_class.timeout).to eq(120)
    end
  end
end
