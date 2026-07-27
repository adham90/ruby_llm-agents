# frozen_string_literal: true

require "rails_helper"

# A routed call with an `agent:` mapping is two LLM calls: classify, then
# delegate. RoutingResult summed the COSTS of both but reported only the
# classification's TOKENS, so cost-per-token was nonsense. It also registered
# itself with the active Tracker on top of the two results it wraps — and since
# its own cost is already the sum of those two, every routed call was reported
# at double its real spend.
RSpec.describe "routing cost accounting" do
  before do
    RubyLLM::Agents.reset_configuration!
    RubyLLM::Agents.configure do |c|
      c.track_executions = true
      c.async_logging = false
    end
    RubyLLM::Agents::Execution.delete_all

    client = double("RubyLLM::Chat")
    %i[with_temperature with_instructions with_schema with_tools with_thinking].each do |m|
      allow(client).to receive(m).and_return(client)
    end
    allow(client).to receive(:messages).and_return([])
    allow(client).to receive(:ask).and_return(
      RubyLLM::Message.new(role: :assistant, content: "billing",
        input_tokens: 100, output_tokens: 50, model_id: "gpt-4.1")
    )
    allow(RubyLLM).to receive(:chat).and_return(client)
  end

  after { RubyLLM::Agents.reset_configuration! }

  let(:billing_agent) do
    Class.new(RubyLLM::Agents::Base) do
      def self.name = "RoutedBillingAgent"

      model "gpt-4.1"
      prompt "handle it"
    end
  end

  let(:router) do
    target = billing_agent
    Class.new(RubyLLM::Agents::Base) do
      include RubyLLM::Agents::Routing

      def self.name = "CostRouter"

      model "gpt-4.1"
      prompt "classify {message}"
      route :billing, "Billing questions", agent: target
      route :other, "Everything else"
    end
  end

  let(:unmapped_router) do
    Class.new(RubyLLM::Agents::Base) do
      include RubyLLM::Agents::Routing

      def self.name = "ClassifyOnlyRouter"

      model "gpt-4.1"
      prompt "classify {message}"
      route :billing, "Billing questions"
      route :other, "Everything else"
    end
  end

  describe "a delegated route" do
    it "counts the tokens of both calls, matching the summed cost" do
      result = router.call(message: "charged twice")

      expect(result).to be_delegated
      expect(result.total_tokens).to eq(300)
      expect(result.input_tokens).to eq(200)
      expect(result.output_tokens).to eq(100)
    end

    it "keeps input_cost + output_cost reconciled with total_cost" do
      result = router.call(message: "charged twice")

      expect(result.input_cost + result.output_cost).to be_within(1e-9).of(result.total_cost)
    end

    it "still exposes the classification step on its own" do
      result = router.call(message: "charged twice")

      expect(result.routing_tokens).to eq(150)
      expect(result.routing_cost).to be_within(1e-9).of(result.total_cost / 2)
    end

    it "reports each call once to the tracker, not the wrapper too" do
      report = RubyLLM::Agents.track { router.call(message: "charged twice") }

      expect(report.call_count).to eq(2)
      expect(report.total_cost).to be_within(1e-9).of(RubyLLM::Agents::Execution.sum(:total_cost).to_f)
      expect(report.total_tokens).to eq(RubyLLM::Agents::Execution.sum(:total_tokens))
    end
  end

  describe "a classification-only route" do
    it "reports just the classification call" do
      result = unmapped_router.call(message: "charged twice")

      expect(result).not_to be_delegated
      expect(result.total_tokens).to eq(150)
      expect(result.total_cost).to be_within(1e-9).of(result.routing_cost)
    end

    it "reports one call to the tracker" do
      report = RubyLLM::Agents.track { unmapped_router.call(message: "charged twice") }

      expect(report.call_count).to eq(1)
      expect(report.total_cost).to be_within(1e-9).of(RubyLLM::Agents::Execution.sum(:total_cost).to_f)
    end
  end

  it "keeps to_h public" do
    expect(router.call(message: "x").to_h).to include(:route, :delegated)
  end
end
