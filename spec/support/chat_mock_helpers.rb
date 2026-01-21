# frozen_string_literal: true

# Shared mock helpers for RubyLLM::Chat client tests
# Replaces repetitive mock setup with reusable, verified helpers
module ChatMockHelpers

  # Build a mock RubyLLM::Chat client with all standard chainable methods
  #
  # @param response [RubyLLM::Message] The response the mock should return when #ask is called
  # @param streaming [Boolean] If true, #complete method is used instead of #ask
  # @param error [Exception, nil] If set, raises this error when #ask is called
  # @return [RSpec::Mocks::Double] A configured mock chat client
  def build_mock_chat_client(response: nil, streaming: false, error: nil)
    mock_client = double("RubyLLM::Chat")

    # Configure all chainable methods to return self
    allow(mock_client).to receive(:with_model).and_return(mock_client)
    allow(mock_client).to receive(:with_temperature).and_return(mock_client)
    allow(mock_client).to receive(:with_instructions).and_return(mock_client)
    allow(mock_client).to receive(:with_schema).and_return(mock_client)
    allow(mock_client).to receive(:with_tools).and_return(mock_client)
    allow(mock_client).to receive(:with_thinking).and_return(mock_client)
    allow(mock_client).to receive(:add_message).and_return(mock_client)
    allow(mock_client).to receive(:messages).and_return([])

    # Configure response behavior
    if error
      allow(mock_client).to receive(:ask).and_raise(error)
    elsif response
      allow(mock_client).to receive(:ask).and_return(response)
    end

    mock_client
  end

  # Build a mock RubyLLM::Message response
  # Uses a regular double rather than instance_double because RubyLLM::Message
  # may have different method signatures depending on version
  #
  # @param content [String] The response content
  # @param input_tokens [Integer] Number of input tokens
  # @param output_tokens [Integer] Number of output tokens
  # @param model_id [String] The model that generated the response
  # @param tool_calls [Array, nil] Tool calls in the response
  # @param finish_reason [String, nil] The finish reason (stop, tool_calls, length, etc.)
  # @param thinking [String, nil] Thinking content for extended thinking models
  # @return [RSpec::Mocks::Double] A mock response
  def build_mock_response(
    content: "Test response",
    input_tokens: 100,
    output_tokens: 50,
    model_id: "gpt-4",
    tool_calls: nil,
    finish_reason: "stop",
    thinking: nil
  )
    mock = double("RubyLLM::Message")

    allow(mock).to receive(:content).and_return(content)
    allow(mock).to receive(:input_tokens).and_return(input_tokens)
    allow(mock).to receive(:output_tokens).and_return(output_tokens)
    allow(mock).to receive(:model_id).and_return(model_id)
    allow(mock).to receive(:tool_calls).and_return(tool_calls)
    allow(mock).to receive(:tool_call?).and_return(tool_calls.present?)
    allow(mock).to receive(:finish_reason).and_return(finish_reason)
    allow(mock).to receive(:thinking).and_return(thinking)
    allow(mock).to receive(:thinking_content).and_return(thinking)

    mock
  end

  # Build a mock chat client that returns chunks for streaming
  #
  # @param chunks [Array<Hash>] Array of chunk data to stream
  # @param final_response [RubyLLM::Message, nil] Final response after streaming
  # @return [RSpec::Mocks::Double] A configured streaming mock client
  def build_mock_streaming_chat(chunks:, final_response: nil)
    mock_client = build_mock_chat_client

    allow(mock_client).to receive(:ask) do |_, &block|
      chunks.each { |chunk| block.call(chunk) if block }
      final_response || build_mock_response
    end

    mock_client
  end

  # Build a mock chat client that raises an error
  #
  # @param error_class [Class] The exception class to raise
  # @param message [String] The error message
  # @return [RSpec::Mocks::Double] A configured error mock client
  def build_mock_error_chat(error_class:, message:)
    build_mock_chat_client(error: error_class.new(message))
  end

  # Stub RubyLLM.chat to return the provided mock
  #
  # @param mock [RSpec::Mocks::Double] The mock to return
  # @param capture_key_block [Proc, nil] Block to capture the config at execution time
  def stub_ruby_llm_chat(mock, &capture_key_block)
    if capture_key_block
      allow(RubyLLM).to receive(:chat) do
        capture_key_block.call(RubyLLM.config)
        mock
      end
    else
      allow(RubyLLM).to receive(:chat).and_return(mock)
    end
  end

  # Setup common agent configuration mocks
  #
  # @param track_executions [Boolean] Whether to track executions
  # @param async_logging [Boolean] Whether to use async logging
  # @param track_cache_hits [Boolean] Whether to track cache hits
  # @param cache_store [ActiveSupport::Cache::Store, nil] The cache store to use
  def stub_agent_configuration(
    track_executions: true,
    async_logging: false,
    track_cache_hits: true,
    cache_store: nil
  )
    RubyLLM::Agents.reset_configuration!
    config = RubyLLM::Agents.configuration

    allow(config).to receive(:track_executions).and_return(track_executions)
    allow(config).to receive(:async_logging).and_return(async_logging)
    allow(config).to receive(:track_cache_hits).and_return(track_cache_hits)

    if cache_store
      allow(config).to receive(:cache_store).and_return(cache_store)
    end

    config
  end

  # Create a complete mock setup for a basic agent test
  # Returns both the mock client and response for verification
  #
  # @param content [String] Response content
  # @param input_tokens [Integer] Input tokens
  # @param output_tokens [Integer] Output tokens
  # @return [Hash] { client: mock_client, response: mock_response }
  def setup_agent_mocks(content: "Test response", input_tokens: 100, output_tokens: 50)
    response = build_mock_response(
      content: content,
      input_tokens: input_tokens,
      output_tokens: output_tokens
    )
    client = build_mock_chat_client(response: response)
    stub_ruby_llm_chat(client)
    stub_agent_configuration

    { client: client, response: response }
  end
end

RSpec.configure do |config|
  config.include ChatMockHelpers

  # Tag-based automatic setup
  config.before(:each, :chat_client) do
    @mock_setup = setup_agent_mocks
  end
end
