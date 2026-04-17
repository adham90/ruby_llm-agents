# frozen_string_literal: true

require "rails_helper"

RSpec.describe RubyLLM::Agents::Pipeline::Middleware::AttachmentPersistence do
  let(:enabled_agent_class) do
    Class.new do
      extend RubyLLM::Agents::DSL::Attachments
      store_attachments :active_storage

      def self.name
        "EnabledAgent"
      end
    end
  end

  let(:disabled_agent_class) do
    Class.new do
      extend RubyLLM::Agents::DSL::Attachments

      def self.name
        "DisabledAgent"
      end
    end
  end

  let(:file_path) { File.join(Dir.tmpdir, "attachment_persistence_spec_#{SecureRandom.hex(4)}.txt") }

  before do
    File.write(file_path, "hello world")
  end

  after do
    File.delete(file_path) if File.exist?(file_path)
  end

  def build_execution
    RubyLLM::Agents::Execution.create!(
      agent_type: "EnabledAgent",
      execution_type: "chat",
      model_id: "test-model",
      status: "success",
      started_at: Time.current
    )
  end

  def build_context(agent_class:, execution_id: nil, with: nil, error: nil)
    ctx = RubyLLM::Agents::Pipeline::Context.new(
      input: "test",
      agent_class: agent_class,
      with: with
    )
    ctx.execution_id = execution_id
    ctx.error = error
    ctx
  end

  let(:downstream_app) { ->(ctx) { ctx } }

  describe "#call" do
    context "when the agent enables store_attachments :active_storage" do
      it "attaches the file at the given path to the execution's detail" do
        execution = build_execution
        context = build_context(agent_class: enabled_agent_class, execution_id: execution.id, with: file_path)

        described_class.new(downstream_app, enabled_agent_class).call(context)

        detail = execution.reload.detail
        expect(detail).not_to be_nil
        expect(detail.user_attachments.count).to eq(1)
        expect(detail.user_attachments.first.filename.to_s).to eq(File.basename(file_path))
      end

      it "accepts an array of file paths" do
        other_path = File.join(Dir.tmpdir, "attachment_spec_other_#{SecureRandom.hex(4)}.txt")
        File.write(other_path, "more content")
        execution = build_execution
        context = build_context(agent_class: enabled_agent_class, execution_id: execution.id, with: [file_path, other_path])

        described_class.new(downstream_app, enabled_agent_class).call(context)

        expect(execution.reload.detail.user_attachments.count).to eq(2)
      ensure
        File.delete(other_path) if other_path && File.exist?(other_path)
      end

      it "skips URL inputs" do
        execution = build_execution
        context = build_context(agent_class: enabled_agent_class, execution_id: execution.id, with: "https://example.com/image.png")

        described_class.new(downstream_app, enabled_agent_class).call(context)

        expect(execution.reload.detail&.user_attachments&.count.to_i).to eq(0)
      end

      it "does not persist when execution failed" do
        execution = build_execution
        context = build_context(
          agent_class: enabled_agent_class,
          execution_id: execution.id,
          with: file_path,
          error: StandardError.new("boom")
        )

        described_class.new(downstream_app, enabled_agent_class).call(context)

        expect(execution.reload.detail&.user_attachments&.count.to_i).to eq(0)
      end

      it "is a no-op when `with:` is missing" do
        execution = build_execution
        context = build_context(agent_class: enabled_agent_class, execution_id: execution.id, with: nil)

        described_class.new(downstream_app, enabled_agent_class).call(context)

        expect(execution.reload.detail&.user_attachments&.count.to_i).to eq(0)
      end
    end

    context "when the agent does not enable store_attachments" do
      it "is a no-op even when `with:` is provided" do
        execution = build_execution
        context = build_context(agent_class: disabled_agent_class, execution_id: execution.id, with: file_path)

        described_class.new(downstream_app, disabled_agent_class).call(context)

        expect(execution.reload.detail&.user_attachments&.count.to_i).to eq(0)
      end
    end

    context "when the downstream app raises" do
      it "re-raises and does not attach" do
        execution = build_execution
        context = build_context(agent_class: enabled_agent_class, execution_id: execution.id, with: file_path)
        raising_app = ->(_ctx) { raise StandardError, "boom" }

        expect {
          described_class.new(raising_app, enabled_agent_class).call(context)
        }.to raise_error(StandardError, "boom")

        expect(execution.reload.detail&.user_attachments&.count.to_i).to eq(0)
      end
    end
  end
end
