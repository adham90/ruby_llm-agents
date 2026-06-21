# frozen_string_literal: true

require "rails_helper"

RSpec.describe RubyLLM::Agents::ExecutionDetail do
  describe "user_attachments" do
    it "supports attaching multiple files via Active Storage" do
      execution = RubyLLM::Agents::Execution.create!(
        agent_type: "TestAgent",
        execution_type: "chat",
        model_id: "test-model",
        status: "success",
        started_at: Time.current
      )
      detail = execution.create_detail!

      detail.user_attachments.attach(
        io: StringIO.new("first"),
        filename: "first.txt",
        content_type: "text/plain"
      )
      detail.user_attachments.attach(
        io: StringIO.new("second"),
        filename: "second.txt",
        content_type: "text/plain"
      )

      expect(detail.reload.user_attachments.count).to eq(2)
      expect(detail.user_attachments.map { |a| a.filename.to_s }).to match_array(%w[first.txt second.txt])
    end
  end
end
