# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Executions CSV export", type: :request do
  let(:export_path) { "/agents/executions/export" }

  it "streams one CSV row per root execution with its error message" do
    create(:execution, :failed, agent_type: "ExportAgent")
    create(:execution, agent_type: "ExportAgent")

    get export_path

    expect(response).to have_http_status(:ok)
    expect(response.headers["Content-Type"]).to include("text/csv")
    rows = CSV.parse(response.body, headers: true)
    expect(rows.size).to eq(2)
    expect(rows.map { |r| r["error_message"] }).to include("Something went wrong")
  end

  # Regression: export preloaded the full detail row (prompts, response JSON)
  # for every execution in each 1000-row batch just to read error_message.
  it "preloads error messages narrowly, one query per batch" do
    create_list(:execution, 3, :failed)

    detail_queries = capture_sql { get export_path }
      .grep(/ruby_llm_agents_execution_details/)

    expect(detail_queries.size).to eq(1)
    expect(detail_queries.first).to include("error_message")
    expect(detail_queries.first).not_to include(".*")
  end
end
