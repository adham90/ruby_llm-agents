# frozen_string_literal: true

require "rails_helper"

RSpec.describe RubyLLM::Agents::Workflow::Parallel do
  # Mock agent classes for testing
  let(:mock_result) do
    ->(content, cost: 0.001) do
      RubyLLM::Agents::Result.new(
        content: content,
        input_tokens: 100,
        output_tokens: 50,
        total_cost: cost,
        model_id: "gpt-4o"
      )
    end
  end

  let(:sentiment_agent) do
    result_builder = mock_result
    Class.new(RubyLLM::Agents::Base) do
      model "gpt-4o"
      param :text, required: false

      define_method(:call) do |&_block|
        sleep(0.01) # Simulate API call
        result_builder.call("positive", cost: 0.002)
      end

      def user_prompt
        "analyze sentiment"
      end
    end
  end

  let(:summary_agent) do
    result_builder = mock_result
    Class.new(RubyLLM::Agents::Base) do
      model "gpt-4o"
      param :text, required: false

      define_method(:call) do |&_block|
        sleep(0.01) # Simulate API call
        result_builder.call("A brief summary", cost: 0.003)
      end

      def user_prompt
        "summarize"
      end
    end
  end

  let(:category_agent) do
    result_builder = mock_result
    Class.new(RubyLLM::Agents::Base) do
      model "gpt-4o"
      param :text, required: false

      define_method(:call) do |&_block|
        sleep(0.01) # Simulate API call
        result_builder.call(["tech", "review"], cost: 0.001)
      end

      def user_prompt
        "categorize"
      end
    end
  end

  describe "DSL class methods" do
    describe ".branch" do
      it "defines branches" do
        agent = sentiment_agent
        klass = Class.new(described_class) do
          branch :sentiment, agent: agent
        end
        expect(klass.branches.keys).to eq([:sentiment])
      end

      it "stores agent class" do
        agent = sentiment_agent
        klass = Class.new(described_class) do
          branch :sentiment, agent: agent
        end
        expect(klass.branches[:sentiment][:agent]).to eq(agent)
      end

      it "supports optional flag" do
        agent = sentiment_agent
        klass = Class.new(described_class) do
          branch :sentiment, agent: agent, optional: true
        end
        expect(klass.branches[:sentiment][:optional]).to be true
      end

      it "supports custom input transformation" do
        agent = sentiment_agent
        input_proc = ->(opts) { { text: opts[:content] } }
        klass = Class.new(described_class) do
          branch :sentiment, agent: agent, input: input_proc
        end
        expect(klass.branches[:sentiment][:input]).to eq(input_proc)
      end
    end

    describe ".fail_fast" do
      it "sets fail_fast mode" do
        klass = Class.new(described_class) do
          fail_fast true
        end
        expect(klass.fail_fast?).to be true
      end

      it "defaults to false" do
        klass = Class.new(described_class)
        expect(klass.fail_fast?).to be false
      end
    end

    describe ".concurrency" do
      it "sets concurrency limit" do
        klass = Class.new(described_class) do
          concurrency 2
        end
        expect(klass.concurrency).to eq(2)
      end

      it "defaults to nil (unlimited)" do
        klass = Class.new(described_class)
        expect(klass.concurrency).to be_nil
      end
    end

    describe "inheritance" do
      it "inherits branches from parent" do
        agent = sentiment_agent
        parent = Class.new(described_class) do
          branch :sentiment, agent: agent
        end
        child = Class.new(parent)
        expect(child.branches.keys).to eq([:sentiment])
      end

      it "inherits fail_fast from parent" do
        parent = Class.new(described_class) do
          fail_fast true
        end
        child = Class.new(parent)
        expect(child.fail_fast?).to be true
      end
    end
  end

  describe "#call" do
    it "executes all branches" do
      sent = sentiment_agent
      summ = summary_agent
      cat = category_agent

      parallel = Class.new(described_class) do
        branch :sentiment, agent: sent
        branch :summary, agent: summ
        branch :categories, agent: cat
      end

      result = parallel.call(text: "Great product!")

      expect(result.branches.keys).to contain_exactly(:sentiment, :summary, :categories)
    end

    it "returns WorkflowResult with aggregate metrics" do
      sent = sentiment_agent
      summ = summary_agent

      parallel = Class.new(described_class) do
        branch :sentiment, agent: sent
        branch :summary, agent: summ
      end

      result = parallel.call(text: "test")

      expect(result.total_cost).to eq(0.005) # 0.002 + 0.003
      expect(result.total_tokens).to eq(300) # 150 * 2
      expect(result.workflow_id).to be_present
    end

    it "aggregates results using default aggregate method" do
      sent = sentiment_agent
      summ = summary_agent

      parallel = Class.new(described_class) do
        branch :sentiment, agent: sent
        branch :summary, agent: summ
      end

      result = parallel.call(text: "test")

      expect(result.content[:sentiment]).to eq("positive")
      expect(result.content[:summary]).to eq("A brief summary")
    end

    it "uses custom aggregate method" do
      sent = sentiment_agent
      summ = summary_agent

      parallel = Class.new(described_class) do
        branch :sentiment, agent: sent
        branch :summary, agent: summ

        def aggregate(results)
          {
            mood: results[:sentiment]&.content,
            tldr: results[:summary]&.content,
            combined: true
          }
        end
      end

      result = parallel.call(text: "test")

      expect(result.content[:mood]).to eq("positive")
      expect(result.content[:tldr]).to eq("A brief summary")
      expect(result.content[:combined]).to be true
    end

    it "sets status to success when all branches succeed" do
      sent = sentiment_agent

      parallel = Class.new(described_class) do
        branch :sentiment, agent: sent
      end

      result = parallel.call(text: "test")

      expect(result.status).to eq("success")
      expect(result.success?).to be true
    end

    it "executes branches concurrently" do
      # Create agents with known delays
      slow_agent = Class.new(RubyLLM::Agents::Base) do
        model "gpt-4o"

        define_method(:call) do |&_block|
          sleep(0.1)
          RubyLLM::Agents::Result.new(
            content: "slow",
            input_tokens: 10,
            output_tokens: 10,
            total_cost: 0.001
          )
        end

        def user_prompt
          "slow"
        end
      end

      parallel = Class.new(described_class) do
        branch :a, agent: slow_agent
        branch :b, agent: slow_agent
        branch :c, agent: slow_agent
      end

      start_time = Time.current
      result = parallel.call(text: "test")
      elapsed = Time.current - start_time

      # Should be ~100ms, not 300ms
      expect(elapsed).to be < 0.25
      expect(result.branches.keys).to contain_exactly(:a, :b, :c)
    end
  end

  describe "error handling" do
    let(:failing_agent) do
      Class.new(RubyLLM::Agents::Base) do
        model "gpt-4o"

        def call(&_block)
          raise StandardError, "Branch failed"
        end

        def user_prompt
          "fail"
        end
      end
    end

    it "sets status to error when required branch fails" do
      sent = sentiment_agent
      fail_agent = failing_agent

      parallel = Class.new(described_class) do
        branch :sentiment, agent: sent
        branch :fail, agent: fail_agent
      end

      result = parallel.call(text: "test")

      expect(result.status).to eq("error")
      expect(result.error?).to be true
      expect(result.failed_branches).to include(:fail)
    end

    it "sets status to partial when optional branch fails" do
      sent = sentiment_agent
      fail_agent = failing_agent

      parallel = Class.new(described_class) do
        branch :sentiment, agent: sent
        branch :fail, agent: fail_agent, optional: true
      end

      result = parallel.call(text: "test")

      expect(result.status).to eq("partial")
      expect(result.partial?).to be true
      expect(result.branches[:sentiment]).to be_present
    end

    it "records errors in errors hash" do
      fail_agent = failing_agent

      parallel = Class.new(described_class) do
        branch :fail, agent: fail_agent, optional: true
      end

      result = parallel.call(text: "test")

      expect(result.errors[:fail]).to be_a(StandardError)
      expect(result.errors[:fail].message).to eq("Branch failed")
    end
  end

  describe "fail_fast mode" do
    it "stops other branches on first failure when enabled" do
      slow_agent = Class.new(RubyLLM::Agents::Base) do
        model "gpt-4o"

        define_method(:call) do |&_block|
          sleep(0.2)
          RubyLLM::Agents::Result.new(content: "done", input_tokens: 10, output_tokens: 10, total_cost: 0.001)
        end

        def user_prompt
          "slow"
        end
      end

      fast_fail_agent = Class.new(RubyLLM::Agents::Base) do
        model "gpt-4o"

        def call(&_block)
          sleep(0.01)
          raise StandardError, "Fast fail"
        end

        def user_prompt
          "fail"
        end
      end

      parallel = Class.new(described_class) do
        fail_fast true

        branch :slow, agent: slow_agent
        branch :fail, agent: fast_fail_agent
      end

      result = parallel.call(text: "test")

      expect(result.error?).to be true
      # The slow branch may or may not complete depending on timing
    end
  end

  describe "branch input transformation" do
    it "uses custom input proc" do
      received_input = nil

      capturing_agent = Class.new(RubyLLM::Agents::Base) do
        model "gpt-4o"
        param :custom_key, required: false

        define_method(:call) do |&_block|
          received_input = @options
          RubyLLM::Agents::Result.new(content: "done", input_tokens: 10, output_tokens: 10, total_cost: 0.001)
        end

        def user_prompt
          "test"
        end
      end

      parallel = Class.new(described_class) do
        branch :capture, agent: capturing_agent, input: ->(opts) { { custom_key: opts[:original] } }
      end

      parallel.call(original: "value")

      expect(received_input[:custom_key]).to eq("value")
    end

    it "uses before_<branch> method if defined" do
      received_input = nil

      capturing_agent = Class.new(RubyLLM::Agents::Base) do
        model "gpt-4o"
        param :transformed, required: false

        define_method(:call) do |&_block|
          received_input = @options
          RubyLLM::Agents::Result.new(content: "done", input_tokens: 10, output_tokens: 10, total_cost: 0.001)
        end

        def user_prompt
          "test"
        end
      end

      parallel = Class.new(described_class) do
        branch :capture, agent: capturing_agent

        def before_capture(options)
          { transformed: options[:original].upcase }
        end
      end

      parallel.call(original: "hello")

      expect(received_input[:transformed]).to eq("HELLO")
    end
  end
end
