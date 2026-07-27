# frozen_string_literal: true

require "rails_helper"
require "rake"

# Versions before the tenant-API-key fix wrote per-tenant provider keys into
# executions.metadata in plaintext, and the execution page renders that column
# verbatim. The fix stops new rows from being written that way; this task
# scrubs the rows already on disk.
RSpec.describe "ruby_llm_agents:redact_metadata_secrets" do
  before do
    Rake::Task.clear
    Rake.application = Rake::Application.new
    load RubyLLM::Agents::Engine.root.join("lib/tasks/ruby_llm_agents.rake")
    Rake::Task.define_task(:environment)
    RubyLLM::Agents::Execution.delete_all
    ENV.delete("DRY_RUN")
  end

  after { ENV.delete("DRY_RUN") }

  def run_task
    Rake::Task["ruby_llm_agents:redact_metadata_secrets"].tap(&:reenable).invoke
  end

  def execution_with(metadata)
    create(:execution).tap { |e| e.update_column(:metadata, metadata) }
  end

  it "redacts a leaked tenant API key" do
    execution = execution_with({"tenant_api_keys" => {"openai" => "sk-live-SECRET"}})

    expect { run_task }.to output(/Redacted 1 of 1/).to_stdout

    expect(execution.reload.metadata["tenant_api_keys"]).to eq("[REDACTED]")
    expect(execution.read_attribute_before_type_cast(:metadata).to_s).not_to include("SECRET")
  end

  it "leaves legitimate telemetry untouched" do
    execution = execution_with({
      "cached_tokens" => 6016, "llm_request_ms" => 120,
      "response_cache_key" => "k/1", "trace_id" => "abc"
    })

    run_task

    expect(execution.reload.metadata).to eq({
      "cached_tokens" => 6016, "llm_request_ms" => 120,
      "response_cache_key" => "k/1", "trace_id" => "abc"
    })
  end

  it "redacts only the offending keys on a mixed row" do
    execution = execution_with({"openai_api_key" => "sk-x", "cached_tokens" => 42})

    run_task

    expect(execution.reload.metadata).to eq({"openai_api_key" => "[REDACTED]", "cached_tokens" => 42})
  end

  it "changes nothing under DRY_RUN" do
    ENV["DRY_RUN"] = "1"
    execution = execution_with({"tenant_api_keys" => {"openai" => "sk-live-SECRET"}})

    expect { run_task }.to output(/DRY RUN/).to_stdout

    expect(execution.reload.metadata["tenant_api_keys"]).to eq({"openai" => "sk-live-SECRET"})
  end

  it "reports when there is nothing to redact" do
    execution_with({"trace_id" => "abc"})

    expect { run_task }.to output(/Redacted 0 of 1/).to_stdout
  end

  it "tells the operator to rotate what it found" do
    execution_with({"tenant_api_keys" => {"openai" => "sk-live-SECRET"}})

    expect { run_task }.to output(/Rotate any exposed credential/).to_stdout
  end
end
