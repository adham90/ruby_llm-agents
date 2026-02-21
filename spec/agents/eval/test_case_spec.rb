# frozen_string_literal: true

require "rails_helper"

RSpec.describe RubyLLM::Agents::Eval::TestCase do
  describe "#resolve_input" do
    it "returns static hash input as-is" do
      tc = described_class.new(
        name: "test",
        input: {query: "hello"},
        expected: nil,
        scorer: nil,
        options: {}
      )
      expect(tc.resolve_input).to eq({query: "hello"})
    end

    it "calls proc input and returns the result" do
      tc = described_class.new(
        name: "test",
        input: -> { {query: "from proc"} },
        expected: nil,
        scorer: nil,
        options: {}
      )
      expect(tc.resolve_input).to eq({query: "from proc"})
    end

    it "evaluates proc each time it is called" do
      counter = 0
      tc = described_class.new(
        name: "test",
        input: -> {
          counter += 1
          {run: counter}
        },
        expected: nil,
        scorer: nil,
        options: {}
      )

      expect(tc.resolve_input).to eq({run: 1})
      expect(tc.resolve_input).to eq({run: 2})
    end
  end

  describe "attributes" do
    it "stores all fields" do
      tc = described_class.new(
        name: "billing case",
        input: {message: "charge"},
        expected: {route: :billing},
        scorer: :contains,
        options: {criteria: "be helpful"}
      )

      expect(tc.name).to eq("billing case")
      expect(tc.input).to eq({message: "charge"})
      expect(tc.expected).to eq({route: :billing})
      expect(tc.scorer).to eq(:contains)
      expect(tc.options).to eq({criteria: "be helpful"})
    end
  end
end
