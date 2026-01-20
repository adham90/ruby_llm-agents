# frozen_string_literal: true

require "rails_helper"

RSpec.describe RubyLLM::Agents::Pipeline::Executor do
  let(:agent_class) do
    Class.new do
      def self.name
        "TestAgent"
      end

      def self.agent_type
        :embedding
      end

      def self.model
        "test-model"
      end
    end
  end

  describe "#call" do
    it "calls the agent's execute method with context" do
      agent = double("agent")
      context = RubyLLM::Agents::Pipeline::Context.new(
        input: "test",
        agent_class: agent_class
      )

      expect(agent).to receive(:execute).with(context) do |ctx|
        ctx.output = "result"
      end

      executor = described_class.new(agent)
      result = executor.call(context)

      expect(result).to eq(context)
      expect(result.output).to eq("result")
    end

    it "returns the context" do
      agent = double("agent", execute: nil)
      context = RubyLLM::Agents::Pipeline::Context.new(
        input: "test",
        agent_class: agent_class
      )

      executor = described_class.new(agent)
      result = executor.call(context)

      expect(result).to be(context)
    end

    it "propagates errors from execute" do
      agent = double("agent")
      allow(agent).to receive(:execute).and_raise(RuntimeError, "Agent error")

      context = RubyLLM::Agents::Pipeline::Context.new(
        input: "test",
        agent_class: agent_class
      )

      executor = described_class.new(agent)

      expect { executor.call(context) }.to raise_error(RuntimeError, "Agent error")
    end
  end
end

RSpec.describe RubyLLM::Agents::Pipeline::LambdaExecutor do
  let(:agent_class) do
    Class.new do
      def self.name
        "TestAgent"
      end

      def self.agent_type
        :embedding
      end

      def self.model
        "test-model"
      end
    end
  end

  describe "#call" do
    it "calls the lambda with context" do
      called_with = nil
      callable = lambda do |ctx|
        called_with = ctx
        ctx.output = "lambda result"
      end

      context = RubyLLM::Agents::Pipeline::Context.new(
        input: "test",
        agent_class: agent_class
      )

      executor = described_class.new(callable)
      result = executor.call(context)

      expect(called_with).to be(context)
      expect(result.output).to eq("lambda result")
    end

    it "returns the context" do
      callable = ->(ctx) { ctx.output = "done" }
      context = RubyLLM::Agents::Pipeline::Context.new(
        input: "test",
        agent_class: agent_class
      )

      executor = described_class.new(callable)
      result = executor.call(context)

      expect(result).to be(context)
    end

    it "works with procs" do
      proc_callable = proc do |ctx|
        ctx.output = "proc result"
      end

      context = RubyLLM::Agents::Pipeline::Context.new(
        input: "test",
        agent_class: agent_class
      )

      executor = described_class.new(proc_callable)
      result = executor.call(context)

      expect(result.output).to eq("proc result")
    end

    it "propagates errors from lambda" do
      callable = ->(_ctx) { raise "Lambda error" }
      context = RubyLLM::Agents::Pipeline::Context.new(
        input: "test",
        agent_class: agent_class
      )

      executor = described_class.new(callable)

      expect { executor.call(context) }.to raise_error(RuntimeError, "Lambda error")
    end
  end
end
