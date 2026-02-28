# frozen_string_literal: true

require "spec_helper"

# Minimal agent for track integration tests
class TrackTestAgent < RubyLLM::Agents::BaseAgent
  model "gpt-4o"
  param :query, required: true

  user "Answer: {query}"
end

RSpec.describe "RubyLLM::Agents.track" do
  before { setup_agent_mocks(content: "response", input_tokens: 100, output_tokens: 50) }

  describe "basic tracking" do
    it "collects results from agent calls" do
      report = RubyLLM::Agents.track do
        TrackTestAgent.call(query: "hello")
        TrackTestAgent.call(query: "world")
      end

      expect(report).to be_a(RubyLLM::Agents::TrackReport)
      expect(report.call_count).to eq(2)
      expect(report.results.size).to eq(2)
    end

    it "captures block return value" do
      report = RubyLLM::Agents.track do
        r = TrackTestAgent.call(query: "hello")
        {answer: r.content}
      end

      expect(report.value).to eq({answer: "response"})
    end

    it "returns successful report for successful block" do
      report = RubyLLM::Agents.track do
        TrackTestAgent.call(query: "hello")
      end

      expect(report).to be_successful
      expect(report).not_to be_failed
    end

    it "generates a request_id when not provided" do
      report = RubyLLM::Agents.track do
        TrackTestAgent.call(query: "hello")
      end

      expect(report.request_id).to start_with("track_")
    end

    it "uses provided request_id" do
      report = RubyLLM::Agents.track(request_id: "req_abc") do
        TrackTestAgent.call(query: "hello")
      end

      expect(report.request_id).to eq("req_abc")
    end
  end

  describe "shared defaults" do
    it "injects shared tenant into agent options" do
      tenant_hash = {id: "tenant_1", object: nil}

      report = RubyLLM::Agents.track(tenant: tenant_hash) do
        TrackTestAgent.call(query: "hello")
      end

      expect(report.call_count).to eq(1)
      expect(report).to be_successful
    end

    it "allows explicit options to override shared defaults" do
      report = RubyLLM::Agents.track(tenant: {id: "tenant_a"}) do
        TrackTestAgent.call(query: "default")
        TrackTestAgent.call(query: "override", tenant: {id: "tenant_b"})
      end

      expect(report.call_count).to eq(2)
    end
  end

  describe "error handling" do
    it "captures errors without raising" do
      report = RubyLLM::Agents.track do
        TrackTestAgent.call(query: "hello")
        raise "boom"
      end

      expect(report).to be_failed
      expect(report.error).to be_a(RuntimeError)
      expect(report.error.message).to eq("boom")
      expect(report.call_count).to eq(1)
    end

    it "sets value to nil on error" do
      report = RubyLLM::Agents.track do
        TrackTestAgent.call(query: "hello")
        raise "boom"
      end

      expect(report.value).to be_nil
    end

    it "captures partial results before error" do
      report = RubyLLM::Agents.track do
        TrackTestAgent.call(query: "first")
        TrackTestAgent.call(query: "second")
        raise "boom"
      end

      expect(report.call_count).to eq(2)
      expect(report).to be_failed
    end
  end

  describe "nesting" do
    it "supports nested track blocks" do
      outer = RubyLLM::Agents.track do
        TrackTestAgent.call(query: "outer")

        inner = RubyLLM::Agents.track do
          TrackTestAgent.call(query: "inner")
        end

        expect(inner.call_count).to eq(1)
        "outer_done"
      end

      expect(outer.call_count).to eq(2) # both outer and inner calls
      expect(outer.value).to eq("outer_done")
    end

    it "inner block has its own report" do
      inner_report = nil

      RubyLLM::Agents.track do
        inner_report = RubyLLM::Agents.track do
          TrackTestAgent.call(query: "inner_only")
        end
      end

      expect(inner_report.call_count).to eq(1)
    end

    it "inner results bubble to outer tracker" do
      outer = RubyLLM::Agents.track do
        RubyLLM::Agents.track do
          TrackTestAgent.call(query: "inner1")
          TrackTestAgent.call(query: "inner2")
        end
        TrackTestAgent.call(query: "outer1")
      end

      expect(outer.call_count).to eq(3)
    end
  end

  describe "edge cases" do
    it "handles empty block" do
      report = RubyLLM::Agents.track {}
      expect(report.call_count).to eq(0)
      expect(report.total_cost).to eq(0)
      expect(report.value).to be_nil
    end

    it "handles block with no agent calls" do
      report = RubyLLM::Agents.track { 1 + 1 }
      expect(report.call_count).to eq(0)
      expect(report.value).to eq(2)
    end

    it "cleans up thread-local on normal completion" do
      RubyLLM::Agents.track { TrackTestAgent.call(query: "hello") }
      expect(Thread.current[:ruby_llm_agents_tracker]).to be_nil
    end

    it "cleans up thread-local on exception in block" do
      RubyLLM::Agents.track { raise "boom" }
      expect(Thread.current[:ruby_llm_agents_tracker]).to be_nil
    end

    it "restores previous tracker after nested block" do
      outer_tracker = nil

      RubyLLM::Agents.track do
        outer_tracker = Thread.current[:ruby_llm_agents_tracker]

        RubyLLM::Agents.track do
          # inner block
        end

        # After inner block, outer tracker should be restored
        expect(Thread.current[:ruby_llm_agents_tracker]).to eq(outer_tracker)
      end
    end
  end

  describe "tracker defaults merging" do
    it "stores track request_id and tags on agent instance" do
      report = RubyLLM::Agents.track(
        request_id: "req_xyz",
        tags: {feature: "test"}
      ) do
        TrackTestAgent.call(query: "hello")
      end

      expect(report.request_id).to eq("req_xyz")
      expect(report).to be_successful
    end
  end
end
