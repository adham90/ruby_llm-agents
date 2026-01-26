# frozen_string_literal: true

require "rails_helper"

RSpec.describe RubyLLM::Agents::Concerns::ImageOperationDSL do
  let(:test_class) do
    Class.new do
      extend RubyLLM::Agents::Concerns::ImageOperationDSL

      def self.name
        "TestImageOperation"
      end
    end
  end

  before do
    RubyLLM::Agents.reset_configuration!
    RubyLLM::Agents.configure do |c|
      c.default_image_model = "default-image-model"
    end
  end

  describe "#model" do
    it "sets and gets the model" do
      test_class.model "custom-model"
      expect(test_class.model).to eq("custom-model")
    end

    it "falls back to default_model when not set" do
      expect(test_class.model).to eq("default-image-model")
    end
  end

  describe "#version" do
    it "sets and gets the version" do
      test_class.version "v2"
      expect(test_class.version).to eq("v2")
    end

    it "defaults to 'v1'" do
      expect(test_class.version).to eq("v1")
    end
  end

  describe "#description" do
    it "sets and gets the description" do
      test_class.description "Test operation"
      expect(test_class.description).to eq("Test operation")
    end

    it "returns nil by default" do
      expect(test_class.description).to be_nil
    end
  end

  describe "#cache_for" do
    it "sets the cache TTL" do
      test_class.cache_for(3600)
      expect(test_class.cache_ttl).to eq(3600)
    end
  end

  describe "#cache_ttl" do
    it "returns the cache TTL" do
      test_class.cache_for(7200)
      expect(test_class.cache_ttl).to eq(7200)
    end

    it "returns nil when not set" do
      expect(test_class.cache_ttl).to be_nil
    end
  end

  describe "#cache_enabled?" do
    it "returns true when cache_ttl is set" do
      test_class.cache_for(3600)
      expect(test_class.cache_enabled?).to be true
    end

    it "returns false when cache_ttl is not set" do
      expect(test_class.cache_enabled?).to be false
    end
  end

  describe "inheritance" do
    let(:parent_class) do
      Class.new do
        extend RubyLLM::Agents::Concerns::ImageOperationDSL

        def self.name
          "ParentOperation"
        end

        model "parent-model"
        version "v2"
        description "Parent description"
        cache_for 3600
      end
    end

    let(:child_class) do
      Class.new(parent_class) do
        def self.name
          "ChildOperation"
        end
      end
    end

    it "inherits model from parent" do
      expect(child_class.model).to eq("parent-model")
    end

    it "inherits version from parent" do
      expect(child_class.version).to eq("v2")
    end

    it "inherits description from parent" do
      expect(child_class.description).to eq("Parent description")
    end

    it "inherits cache_ttl from parent" do
      expect(child_class.cache_ttl).to eq(3600)
    end

    it "allows child to override parent settings" do
      child_class.model "child-model"
      expect(child_class.model).to eq("child-model")
      expect(parent_class.model).to eq("parent-model")
    end
  end
end
