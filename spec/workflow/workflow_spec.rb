# frozen_string_literal: true

require "rails_helper"

RSpec.describe RubyLLM::Agents::Workflow do
  describe "DSL class methods" do
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

    describe ".timeout" do
      it "sets and gets timeout" do
        klass = Class.new(described_class) do
          timeout 30
        end
        expect(klass.timeout).to eq(30)
      end

      it "converts ActiveSupport::Duration to integer" do
        klass = Class.new(described_class) do
          timeout 1.minute
        end
        expect(klass.timeout).to eq(60)
      end

      it "defaults to nil" do
        klass = Class.new(described_class)
        expect(klass.timeout).to be_nil
      end
    end

    describe ".max_cost" do
      it "sets and gets max_cost" do
        klass = Class.new(described_class) do
          max_cost 0.50
        end
        expect(klass.max_cost).to eq(0.50)
      end

      it "converts to float" do
        klass = Class.new(described_class) do
          max_cost "1"
        end
        expect(klass.max_cost).to eq(1.0)
      end

      it "defaults to nil" do
        klass = Class.new(described_class)
        expect(klass.max_cost).to be_nil
      end
    end
  end

  describe "instance initialization" do
    let(:workflow_class) { Class.new(described_class) }

    it "generates a unique workflow_id" do
      workflow1 = workflow_class.new(input: "test")
      workflow2 = workflow_class.new(input: "test")
      expect(workflow1.workflow_id).not_to eq(workflow2.workflow_id)
    end

    it "stores options" do
      workflow = workflow_class.new(key: "value", another: 123)
      expect(workflow.options).to eq(key: "value", another: 123)
    end
  end

  describe "#call" do
    it "raises NotImplementedError for base class" do
      workflow_class = Class.new(described_class)
      workflow = workflow_class.new(input: "test")
      expect { workflow.call }.to raise_error(NotImplementedError)
    end
  end
end
