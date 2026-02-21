# frozen_string_literal: true

# Run with: RUN_EVAL=1 bundle exec rspec spec/evals/

require "rails_helper"

RSpec.describe "SupportRouter eval", if: ENV["RUN_EVAL"] do
  it "meets quality bar" do
    run = Evals::SupportRouterEval.run!

    puts run.summary

    expect(run.score).to be >= 0.9
    expect(run.errors).to be_empty
  end

  it "routes billing messages correctly" do
    run = Evals::SupportRouterEval.run!(only: [
      "billing: double charge",
      "billing: refund request",
      "billing: invoice"
    ])

    expect(run.passed).to eq(run.total_cases)
  end
end
