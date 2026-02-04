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

    context "with block DSL (RubyLLM::Schema)" do
      it "sets schema from a block" do
        test_class.schema do
          string :name, description: "A name"
        end
        expect(test_class.schema).to be_present
        expect(test_class.schema.properties).to include(:name)
      end

      it "produces a RubyLLM::Schema subclass" do
        test_class.schema do
          string :name
        end
        expect(test_class.schema.ancestors).to include(RubyLLM::Schema)
      end

      it "supports multiple property types" do
        test_class.schema do
          string :name, description: "Full name"
          integer :age, description: "Age in years"
          number :score, description: "Score"
          boolean :active, required: false
        end

        schema = test_class.schema
        expect(schema.properties.keys).to contain_exactly(:name, :age, :score, :active)
        expect(schema.required_properties).to include(:name, :age, :score)
        expect(schema.required_properties).not_to include(:active)
      end

      it "supports arrays" do
        test_class.schema do
          array :tags, of: :string, description: "Tags"
        end
        expect(test_class.schema.properties).to include(:tags)
      end

      it "supports nested objects" do
        test_class.schema do
          object :address do
            string :city
            string :zip
          end
        end
        expect(test_class.schema.properties).to include(:address)
      end

      it "returns the same schema on subsequent calls without arguments" do
        test_class.schema do
          string :name
        end
        first_call = test_class.schema
        second_call = test_class.schema
        expect(first_call).to equal(second_call)
      end
    end

    context "with hash value" do
      it "sets and returns schema from a hash" do
        hash_schema = { type: "object", properties: { name: { type: "string" } } }
        test_class.schema(hash_schema)
        expect(test_class.schema).to eq(hash_schema)
      end
    end

    context "inheritance" do
      it "inherits schema from parent class" do
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
        expect(child_class.schema.properties).not_to include(:name)
      end

      it "does not affect parent when child overrides" do
        test_class.schema do
          string :name
        end

        Class.new(test_class) do
          schema do
            integer :age
          end
        end

        expect(test_class.schema.properties).to include(:name)
        expect(test_class.schema.properties).not_to include(:age)
      end

      it "supports grandchild inheritance" do
        test_class.schema do
          string :name
        end

        child_class = Class.new(test_class)
        grandchild_class = Class.new(child_class)

        expect(grandchild_class.schema).to eq(test_class.schema)
      end

      it "grandchild can override without affecting ancestors" do
        test_class.schema do
          string :name
        end

        child_class = Class.new(test_class)
        grandchild_class = Class.new(child_class) do
          schema do
            boolean :active
          end
        end

        expect(grandchild_class.schema.properties).to include(:active)
        expect(child_class.schema.properties).to include(:name)
        expect(test_class.schema.properties).to include(:name)
      end
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
