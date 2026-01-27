# frozen_string_literal: true

require "rails_helper"

RSpec.describe "RubyLLM::Agents::VERSION" do
  it "is defined" do
    expect(defined?(RubyLLM::Agents::VERSION)).to be_truthy
  end

  it "is a string" do
    expect(RubyLLM::Agents::VERSION).to be_a(String)
  end

  it "follows semantic versioning format" do
    # Matches x.y.z or x.y.z-suffix patterns
    expect(RubyLLM::Agents::VERSION).to match(/\A\d+\.\d+\.\d+(-[\w.]+)?\z/)
  end

  it "is not empty" do
    expect(RubyLLM::Agents::VERSION).not_to be_empty
  end
end
