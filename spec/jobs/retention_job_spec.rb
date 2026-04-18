# frozen_string_literal: true

require "rails_helper"

RSpec.describe RubyLLM::Agents::RetentionJob, type: :job do
  include ActiveJob::TestHelper

  around do |example|
    original_soft = RubyLLM::Agents.configuration.soft_purge_after
    original_hard = RubyLLM::Agents.configuration.hard_purge_after
    example.run
    # Restore in opposite order to respect soft < hard validation
    RubyLLM::Agents.configuration.soft_purge_after = nil
    RubyLLM::Agents.configuration.hard_purge_after = original_hard
    RubyLLM::Agents.configuration.soft_purge_after = original_soft
  end

  def create_execution(created_at:, **overrides)
    create(:execution, created_at: created_at, started_at: created_at, **overrides)
  end

  describe "#perform" do
    context "soft purge pass" do
      before do
        RubyLLM::Agents.configuration.hard_purge_after = 10.years
        RubyLLM::Agents.configuration.soft_purge_after = 30.days
      end

      it "destroys details and tool_executions for executions older than the window" do
        old_exec = create_execution(created_at: 40.days.ago)
        old_exec.tool_executions.create!(tool_name: "search", started_at: 40.days.ago, status: "success")

        expect {
          described_class.new.perform
        }.to change { RubyLLM::Agents::ExecutionDetail.count }.by(-1)
          .and change { RubyLLM::Agents::ToolExecution.count }.by(-1)
          .and change { RubyLLM::Agents::Execution.count }.by(0)

        expect(old_exec.reload.detail).to be_nil
      end

      it "stamps soft_purged_at into metadata" do
        old_exec = create_execution(created_at: 40.days.ago)

        described_class.new.perform

        expect(old_exec.reload.soft_purged?).to be true
        expect(old_exec.soft_purged_at).to be_within(5.seconds).of(Time.current)
      end

      it "preserves a truncated error_message in metadata" do
        old_exec = create_execution(created_at: 40.days.ago, status: "error", error_class: "StandardError")
        old_exec.detail.update!(error_message: "boom! " * 200)

        described_class.new.perform

        preserved = old_exec.reload.metadata["error_message"]
        expect(preserved).to be_present
        expect(preserved.length).to be <= 500
        expect(old_exec.error_message).to eq(preserved)
      end

      it "does not touch executions inside the window" do
        fresh_exec = create_execution(created_at: 5.days.ago)

        described_class.new.perform

        expect(fresh_exec.reload.detail).to be_present
        expect(fresh_exec.soft_purged?).to be false
      end

      it "is idempotent — rerunning does not re-stamp or re-count" do
        create_execution(created_at: 40.days.ago)

        first_run = described_class.new.perform
        second_run = described_class.new.perform

        expect(first_run[:soft_purged]).to eq(1)
        expect(second_run[:soft_purged]).to eq(0)
      end

      it "returns the count of executions soft-purged this run" do
        create_execution(created_at: 40.days.ago)
        create_execution(created_at: 35.days.ago)

        result = described_class.new.perform
        expect(result[:soft_purged]).to eq(2)
      end

      it "skips the pass when soft_purge_after is nil" do
        RubyLLM::Agents.configuration.soft_purge_after = nil
        old_exec = create_execution(created_at: 40.days.ago)

        result = described_class.new.perform

        expect(result[:soft_purged]).to eq(0)
        expect(old_exec.reload.detail).to be_present
      end
    end

    context "hard purge pass" do
      before do
        RubyLLM::Agents.configuration.soft_purge_after = 30.days
        RubyLLM::Agents.configuration.hard_purge_after = 365.days
      end

      it "destroys executions older than the hard window" do
        ancient_exec = create_execution(created_at: 400.days.ago)

        expect {
          described_class.new.perform
        }.to change { RubyLLM::Agents::Execution.where(id: ancient_exec.id).count }.from(1).to(0)
      end

      it "cascades through to dependent rows" do
        ancient_exec = create_execution(created_at: 400.days.ago)
        ancient_exec.tool_executions.create!(tool_name: "t", started_at: 400.days.ago, status: "success")

        expect {
          described_class.new.perform
        }.to change { RubyLLM::Agents::ExecutionDetail.count }.by(-1)
          .and change { RubyLLM::Agents::ToolExecution.count }.by(-1)
      end

      it "does not touch executions inside the hard window" do
        recent_exec = create_execution(created_at: 100.days.ago)

        described_class.new.perform

        expect(RubyLLM::Agents::Execution.where(id: recent_exec.id)).to exist
      end

      it "returns the count of executions hard-purged" do
        create_execution(created_at: 400.days.ago)
        create_execution(created_at: 500.days.ago)

        result = described_class.new.perform
        expect(result[:hard_purged]).to eq(2)
      end

      it "skips the pass when hard_purge_after is nil" do
        RubyLLM::Agents.configuration.soft_purge_after = nil
        RubyLLM::Agents.configuration.hard_purge_after = nil
        ancient_exec = create_execution(created_at: 400.days.ago)

        result = described_class.new.perform

        expect(result[:hard_purged]).to eq(0)
        expect(RubyLLM::Agents::Execution.where(id: ancient_exec.id)).to exist
      end
    end

    it "runs both passes in one invocation" do
      RubyLLM::Agents.configuration.soft_purge_after = 30.days
      RubyLLM::Agents.configuration.hard_purge_after = 365.days

      create_execution(created_at: 40.days.ago)
      create_execution(created_at: 400.days.ago)

      result = described_class.new.perform

      # Both executions are older than soft_purge_after (30 days), so both
      # are soft-purged. Only one is older than hard_purge_after (365 days).
      expect(result[:soft_purged]).to eq(2)
      expect(result[:hard_purged]).to eq(1)
    end
  end
end
