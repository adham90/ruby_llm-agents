# frozen_string_literal: true

require "rails_helper"
require "generators/ruby_llm_agents/doctor_generator"

RSpec.describe RubyLlmAgents::DoctorGenerator, type: :generator do
  describe "check_api_keys" do
    it "passes when at least one API key is configured" do
      allow(RubyLLM.config).to receive(:openai_api_key).and_return("sk-test-key")

      output = capture_generator_output
      expect(output).to include("OK")
      expect(output).to include("OpenAI API key configured")
    end

    it "fails when no API keys are configured" do
      if defined?(RubyLLM::Agents::FORWARDED_KEY_ATTRIBUTES)
        RubyLLM::Agents::FORWARDED_KEY_ATTRIBUTES.each do |attr|
          allow(RubyLLM.config).to receive(attr).and_return(nil)
        end
      end

      output = capture_generator_output
      expect(output).to include("API Keys")
    end
  end

  describe "check_migrations" do
    it "passes when required tables exist" do
      output = capture_generator_output
      expect(output).to include("ruby_llm_agents_executions")
    end
  end

  describe "check_routes" do
    context "when engine is mounted" do
      before do
        # Write routes file with engine mount
        FileUtils.mkdir_p(File.join(destination_root, "config"))
        File.write(
          File.join(destination_root, "config/routes.rb"),
          "Rails.application.routes.draw do\n  mount RubyLLM::Agents::Engine => \"/agents\"\nend\n"
        )
      end

      it "passes" do
        output = capture_generator_output
        expect(output).to include("Dashboard engine mounted")
      end
    end

    context "when engine is not mounted" do
      it "warns" do
        output = capture_generator_output
        expect(output).to include("WARN")
      end
    end
  end

  describe "check_agents" do
    context "when no agents exist" do
      it "warns about missing agents" do
        output = capture_generator_output
        expect(output).to include("WARN")
      end
    end

    context "when agents exist" do
      before do
        FileUtils.mkdir_p(File.join(destination_root, "app/agents"))
        File.write(
          File.join(destination_root, "app/agents/hello_agent.rb"),
          "class HelloAgent < ApplicationAgent; end"
        )
      end

      it "passes" do
        output = capture_generator_output
        expect(output).to include("Found 1 agent")
      end
    end
  end

  describe "summary" do
    it "shows pass/fail/warn counts" do
      output = capture_generator_output
      expect(output).to match(/\d+ passed, \d+ failed, \d+ warnings/)
    end
  end

  private

  def capture_generator_output
    output = StringIO.new
    generator = described_class.new([], {}, destination_root: destination_root)
    # Capture Thor output
    allow(generator).to receive(:say) { |msg, *| output.puts(msg.to_s) }
    generator.invoke_all
    output.string
  end
end
