# frozen_string_literal: true

require "rails_helper"

RSpec.describe RubyLLM::Agents::Workflow::DSL::InputSchema do
  describe "field definition" do
    describe "#required" do
      it "defines a required field" do
        schema = described_class.new
        schema.required :order_id, String

        expect(schema.fields[:order_id]).to be_present
        expect(schema.fields[:order_id].required?).to be true
      end

      it "defines required field without type" do
        schema = described_class.new
        schema.required :order_id

        expect(schema.fields[:order_id].required?).to be true
      end

      it "accepts options" do
        schema = described_class.new
        schema.required :status, String, in: %w[active inactive]

        expect(schema.fields[:status].options[:in]).to eq(%w[active inactive])
      end
    end

    describe "#optional" do
      it "defines an optional field" do
        schema = described_class.new
        schema.optional :priority, String

        expect(schema.fields[:priority].optional?).to be true
      end

      it "accepts default value" do
        schema = described_class.new
        schema.optional :priority, String, default: "normal"

        expect(schema.fields[:priority].default).to eq("normal")
      end

      it "accepts default as false" do
        schema = described_class.new
        schema.optional :active, :boolean, default: false

        expect(schema.fields[:active].default).to eq(false)
        expect(schema.fields[:active].has_default?).to be true
      end
    end
  end

  describe "#required_fields and #optional_fields" do
    it "returns lists of field names" do
      schema = described_class.new
      schema.required :id, Integer
      schema.required :name, String
      schema.optional :priority, String

      expect(schema.required_fields).to eq([:id, :name])
      expect(schema.optional_fields).to eq([:priority])
    end
  end

  describe "#validate!" do
    let(:schema) do
      s = described_class.new
      s.required :order_id, String
      s.required :user_id, Integer
      s.optional :priority, String, default: "normal"
      s
    end

    it "passes with valid input" do
      result = schema.validate!(order_id: "ORD-123", user_id: 42)

      expect(result[:order_id]).to eq("ORD-123")
      expect(result[:user_id]).to eq(42)
      expect(result[:priority]).to eq("normal")
    end

    it "raises error for missing required fields" do
      expect {
        schema.validate!(user_id: 42)
      }.to raise_error(
        RubyLLM::Agents::Workflow::DSL::InputSchema::ValidationError,
        /order_id is required/
      )
    end

    it "raises error for wrong type" do
      expect {
        schema.validate!(order_id: "ORD-123", user_id: "not-an-int")
      }.to raise_error(
        RubyLLM::Agents::Workflow::DSL::InputSchema::ValidationError,
        /user_id must be a Integer/
      )
    end

    it "validates enum constraints" do
      schema = described_class.new
      schema.required :status, String, in: %w[active inactive]

      expect {
        schema.validate!(status: "unknown")
      }.to raise_error(
        RubyLLM::Agents::Workflow::DSL::InputSchema::ValidationError,
        /status must be one of/
      )
    end

    it "applies custom validation" do
      schema = described_class.new
      schema.required :email, String, validate: ->(v) { v.include?("@") }

      expect {
        schema.validate!(email: "invalid")
      }.to raise_error(
        RubyLLM::Agents::Workflow::DSL::InputSchema::ValidationError,
        /failed custom validation/
      )
    end

    it "validates boolean type" do
      schema = described_class.new
      schema.required :active, :boolean

      expect(schema.validate!(active: true)[:active]).to eq(true)
      expect(schema.validate!(active: false)[:active]).to eq(false)

      expect {
        schema.validate!(active: "yes")
      }.to raise_error(
        RubyLLM::Agents::Workflow::DSL::InputSchema::ValidationError,
        /active must be a Boolean/
      )
    end

    it "allows extra fields not in schema" do
      result = schema.validate!(order_id: "ORD-123", user_id: 42, extra: "value")
      expect(result[:extra]).to eq("value")
    end

    it "provides errors array in exception" do
      begin
        schema.validate!({})
      rescue RubyLLM::Agents::Workflow::DSL::InputSchema::ValidationError => e
        expect(e.errors).to include("order_id is required")
        expect(e.errors).to include("user_id is required")
      end
    end
  end

  describe "#apply_defaults" do
    it "applies defaults without validation" do
      schema = described_class.new
      schema.required :id, Integer
      schema.optional :priority, String, default: "normal"

      result = schema.apply_defaults(id: 1)

      expect(result[:id]).to eq(1)
      expect(result[:priority]).to eq("normal")
    end

    it "preserves existing values" do
      schema = described_class.new
      schema.optional :priority, String, default: "normal"

      result = schema.apply_defaults(priority: "high")

      expect(result[:priority]).to eq("high")
    end
  end

  describe "#to_h" do
    it "serializes the schema" do
      schema = described_class.new
      schema.required :id, Integer
      schema.optional :name, String, default: "unnamed"

      hash = schema.to_h

      expect(hash[:fields][:id][:type]).to eq("Integer")
      expect(hash[:fields][:id][:required]).to be true
      expect(hash[:fields][:name][:default]).to eq("unnamed")
      expect(hash[:fields][:name][:required]).to be false
    end
  end

  describe "#empty?" do
    it "returns true when no fields defined" do
      expect(described_class.new.empty?).to be true
    end

    it "returns false when fields defined" do
      schema = described_class.new
      schema.required :id, Integer
      expect(schema.empty?).to be false
    end
  end
end

RSpec.describe RubyLLM::Agents::Workflow::DSL::OutputSchema do
  it "inherits from InputSchema" do
    expect(described_class).to be < RubyLLM::Agents::Workflow::DSL::InputSchema
  end

  describe "#validate!" do
    it "wraps non-hash output" do
      schema = described_class.new
      schema.optional :result

      result = schema.validate!("string output")
      expect(result[:result]).to eq("string output")
    end

    it "validates hash output directly" do
      schema = described_class.new
      schema.required :status, String

      result = schema.validate!(status: "success")
      expect(result[:status]).to eq("success")
    end
  end
end
