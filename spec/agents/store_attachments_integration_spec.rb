# frozen_string_literal: true

require "rails_helper"

# End-to-end spec for `store_attachments :active_storage`.
#
# This exercises the full BaseAgent.call → pipeline → attachment flow so
# that a rename of the key BaseAgent#execution_options uses to forward
# `with:` into the context (or any other break in that contract) is
# caught, not silently no-op'd the way earlier middleware-only specs
# allowed.
RSpec.describe "Store attachments integration" do
  let(:file_path) { File.join(Dir.tmpdir, "store_attachments_integration_spec_#{SecureRandom.hex(4)}.txt") }

  before do
    File.write(file_path, "diagram content")

    RubyLLM::Agents.reset_configuration!
    config = RubyLLM::Agents.configuration
    config.track_executions = true
    config.persist_prompts = true
    config.persist_responses = false

    stub_agent_configuration
    response = build_real_response(content: "ok", input_tokens: 10, output_tokens: 5)
    stub_ruby_llm_chat(build_mock_chat_client(response: response))
  end

  after do
    File.delete(file_path) if File.exist?(file_path)
  end

  let(:enabled_agent_class) do
    Class.new(RubyLLM::Agents::Base) do
      def self.name
        "EnabledAttachmentsAgent"
      end

      model "gpt-4o"
      system "You are a test agent."
      user "Process: {query}"
      param :query, required: true

      store_attachments :active_storage
    end
  end

  let(:disabled_agent_class) do
    Class.new(RubyLLM::Agents::Base) do
      def self.name
        "DisabledAttachmentsAgent"
      end

      model "gpt-4o"
      system "You are a test agent."
      user "Process: {query}"
      param :query, required: true
    end
  end

  it "attaches the file passed via with: onto the execution's detail" do
    enabled_agent_class.call(query: "hello", with: file_path)

    execution = RubyLLM::Agents::Execution.last
    expect(execution).to be_present
    expect(execution.status).to eq("success")

    detail = execution.detail
    expect(detail).to be_present
    expect(detail.user_attachments.count).to eq(1)
    expect(detail.user_attachments.first.filename.to_s).to eq(File.basename(file_path))
  end

  it "does not attach when store_attachments is not declared" do
    disabled_agent_class.call(query: "hello", with: file_path)

    execution = RubyLLM::Agents::Execution.last
    expect(execution.detail&.user_attachments&.count.to_i).to eq(0)
  end

  it "does not attach when with: is omitted" do
    enabled_agent_class.call(query: "hello")

    execution = RubyLLM::Agents::Execution.last
    expect(execution.detail&.user_attachments&.count.to_i).to eq(0)
  end
end
