# frozen_string_literal: true

require "rails_helper"

# Prompt-cache usage used to reach the metadata JSON blob but never the
# executions.cached_tokens / execution_details.cache_creation_tokens columns,
# which is what the execution page actually renders — so a call that served
# 6016 tokens from the provider's cache displayed "0 cached".
RSpec.describe "prompt cache accounting" do
  before do
    RubyLLM::Agents.reset_configuration!
    RubyLLM::Agents.configure do |c|
      c.track_executions = true
      c.async_logging = false
    end
  end

  after { RubyLLM::Agents.reset_configuration! }

  let(:agent_class) do
    Class.new(RubyLLM::Agents::Base) do
      def self.name = "PromptCacheAgent"

      model "claude-sonnet-4-5-20250929"
      prompt "hi"
    end
  end

  def run_with(response)
    client = double("RubyLLM::Chat")
    %i[with_temperature with_instructions with_schema with_tools with_thinking].each do |m|
      allow(client).to receive(m).and_return(client)
    end
    allow(client).to receive(:messages).and_return([])
    allow(client).to receive(:ask).and_return(response)
    allow(RubyLLM).to receive(:chat).and_return(client)

    agent_class.call
    RubyLLM::Agents::Execution.order(:id).last
  end

  it "persists cache reads to the executions.cached_tokens column" do
    execution = run_with(RubyLLM::Message.new(
      role: :assistant, content: "ok",
      input_tokens: 1096, output_tokens: 50,
      cached_tokens: 6016, cache_creation_tokens: 0,
      model_id: "claude-sonnet-4-5-20250929"
    ))

    expect(execution.cached_tokens).to eq(6016)
  end

  it "persists cache writes to execution_details.cache_creation_tokens" do
    execution = run_with(RubyLLM::Message.new(
      role: :assistant, content: "ok",
      input_tokens: 1096, output_tokens: 50,
      cached_tokens: 0, cache_creation_tokens: 2048,
      model_id: "claude-sonnet-4-5-20250929"
    ))

    expect(execution.detail.cache_creation_tokens).to eq(2048)
  end

  it "records zero when the provider reported no cache activity" do
    execution = run_with(RubyLLM::Message.new(
      role: :assistant, content: "ok",
      input_tokens: 1096, output_tokens: 50,
      model_id: "claude-sonnet-4-5-20250929"
    ))

    expect(execution.cached_tokens).to eq(0)
  end
end
