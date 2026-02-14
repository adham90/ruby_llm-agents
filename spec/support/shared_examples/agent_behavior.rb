# frozen_string_literal: true

# Shared examples for testing agent behavior
# Include in specs using it_behaves_like "a valid agent class"

RSpec.shared_examples "a valid agent class" do
  it "responds to .call" do
    expect(described_class).to respond_to(:call)
  end

  it "responds to .stream" do
    expect(described_class).to respond_to(:stream)
  end

  it "has a model configured" do
    expect(described_class.model).to be_present
  end

  it "returns :conversation for agent_type" do
    expect(described_class.agent_type).to eq(:conversation)
  end
end

RSpec.shared_examples "an agent with caching" do |cache_duration:|
  it "has caching enabled" do
    expect(described_class.cache_enabled?).to be true
  end

  it "has correct cache TTL" do
    expect(described_class.cache_ttl).to eq(cache_duration)
  end

  describe "cache key generation" do
    let(:agent) { described_class.new(**required_params) }

    it "generates a unique cache key" do
      expect(agent.agent_cache_key).to match(/^ruby_llm_agent\//)
    end

    it "includes agent class name in cache key" do
      expect(agent.agent_cache_key).to include(described_class.name)
    end
  end
end

RSpec.shared_examples "an agent that tracks executions" do
  let(:mock_response) { build_mock_response(content: "test", input_tokens: 100, output_tokens: 50) }
  let(:mock_chat) { build_mock_chat_client(response: mock_response) }

  before do
    stub_ruby_llm_chat(mock_chat)
    stub_agent_configuration(track_executions: true)
  end

  it "creates an execution record" do
    expect {
      described_class.call(**required_params)
    }.to change(RubyLLM::Agents::Execution, :count).by(1)
  end

  it "records the correct agent type" do
    described_class.call(**required_params)
    execution = RubyLLM::Agents::Execution.last
    expect(execution.agent_type).to eq(described_class.name)
  end

  it "records token usage" do
    described_class.call(**required_params)
    execution = RubyLLM::Agents::Execution.last
    expect(execution.input_tokens).to be_present
    expect(execution.output_tokens).to be_present
  end

  it "records status as success" do
    described_class.call(**required_params)
    execution = RubyLLM::Agents::Execution.last
    expect(execution.status).to eq("success")
  end
end

RSpec.shared_examples "an agent with required parameters" do |params:|
  params.each do |param_name|
    it "requires #{param_name} parameter" do
      incomplete_params = required_params.except(param_name)
      expect {
        described_class.new(**incomplete_params)
      }.to raise_error(ArgumentError, /missing required param: #{param_name}/)
    end
  end
end

RSpec.shared_examples "an agent with thinking enabled" do
  it "has thinking configuration" do
    expect(described_class.thinking_config).to be_present
  end

  it "includes thinking in execution options" do
    agent = described_class.new(**required_params)
    expect(agent.resolved_thinking).to be_present
  end
end

RSpec.shared_examples "an agent with reliability" do
  it "has retries configured" do
    expect(described_class.retries_config[:max]).to be > 0
  end
end

RSpec.shared_examples "an agent with fallback models" do
  it "has fallback models configured" do
    expect(described_class.fallback_models).not_to be_empty
  end
end

RSpec.shared_examples "an agent with tools" do
  it "has tools configured" do
    expect(described_class.tools).not_to be_empty
  end
end

RSpec.shared_examples "a dry run response" do
  let(:result) { described_class.call(**required_params, dry_run: true) }

  it "returns a Result object" do
    expect(result).to be_a(RubyLLM::Agents::Result)
  end

  it "includes dry_run flag" do
    expect(result.content[:dry_run]).to be true
  end

  it "includes agent name" do
    expect(result.content[:agent]).to eq(described_class.name)
  end

  it "includes model" do
    expect(result.content[:model]).to eq(described_class.model)
  end

  it "includes user_prompt" do
    expect(result.content[:user_prompt]).to be_present
  end
end

RSpec.shared_examples "an agent execution result" do
  let(:mock_response) { build_mock_response(content: expected_content, input_tokens: 100, output_tokens: 50) }
  let(:mock_chat) { build_mock_chat_client(response: mock_response) }

  before do
    stub_ruby_llm_chat(mock_chat)
    stub_agent_configuration
  end

  let(:result) { described_class.call(**required_params) }

  it "returns a Result object" do
    expect(result).to be_a(RubyLLM::Agents::Result)
  end

  it "has content" do
    expect(result.content).to be_present
  end

  it "tracks token usage" do
    expect(result.input_tokens).to eq(100)
    expect(result.output_tokens).to eq(50)
  end

  it "includes model information" do
    expect(result.model_id).to eq(described_class.model)
  end
end

# Specialized shared examples for embedders
RSpec.shared_examples "an embedder" do
  it "returns :embedding for agent_type" do
    expect(described_class.agent_type).to eq(:embedding)
  end
end

# Specialized shared examples for image generators
RSpec.shared_examples "an image generator" do
  it "returns :image_generation for agent_type" do
    expect(described_class.agent_type).to eq(:image_generation)
  end
end

# Specialized shared examples for speakers (TTS)
RSpec.shared_examples "a speaker" do
  it "returns :speech for agent_type" do
    expect(described_class.agent_type).to eq(:speech)
  end
end

# Specialized shared examples for transcribers
RSpec.shared_examples "a transcriber" do
  it "returns :transcription for agent_type" do
    expect(described_class.agent_type).to eq(:transcription)
  end
end

# Specialized shared examples for moderators
RSpec.shared_examples "a moderator" do
  it "returns :moderation for agent_type" do
    expect(described_class.agent_type).to eq(:moderation)
  end
end
