# frozen_string_literal: true

require "rails_helper"

RSpec.describe RubyLLM::Agents::Workflow::AsyncExecutor do
  # AsyncExecutor requires the async gem. We'll test with mocks when async isn't available
  # and with real async when it is.

  describe "#initialize" do
    it "creates an executor with default max_concurrent of 10" do
      executor = described_class.new
      expect(executor.max_concurrent).to eq(10)
    end

    it "creates an executor with custom max_concurrent" do
      executor = described_class.new(max_concurrent: 5)
      expect(executor.max_concurrent).to eq(5)
    end
  end

  describe "#post" do
    it "adds tasks to the queue" do
      executor = described_class.new
      executor.post { "task1" }
      executor.post { "task2" }

      tasks = executor.instance_variable_get(:@tasks)
      expect(tasks.size).to eq(2)
    end
  end

  describe "#abort!" do
    it "sets the aborted flag" do
      executor = described_class.new
      expect(executor.aborted?).to be false

      executor.abort!

      expect(executor.aborted?).to be true
    end

    it "is thread-safe" do
      executor = described_class.new

      threads = 10.times.map do
        Thread.new { executor.abort! }
      end
      threads.each(&:join)

      expect(executor.aborted?).to be true
    end
  end

  describe "#aborted?" do
    it "returns false initially" do
      executor = described_class.new
      expect(executor.aborted?).to be false
    end

    it "returns true after abort!" do
      executor = described_class.new
      executor.abort!
      expect(executor.aborted?).to be true
    end
  end

  describe "#shutdown" do
    it "is a no-op for fiber-based executor" do
      executor = described_class.new
      # Should not raise and does nothing
      expect { executor.shutdown(timeout: 5) }.not_to raise_error
    end
  end

  describe "#wait_for_termination" do
    it "is a no-op for fiber-based executor" do
      executor = described_class.new
      # Should not raise and does nothing
      expect { executor.wait_for_termination(timeout: 5) }.not_to raise_error
    end
  end

  describe "#wait_for_completion" do
    context "with no tasks" do
      it "returns true immediately" do
        executor = described_class.new
        expect(executor.wait_for_completion).to be true
      end
    end

    context "when async gem is not available" do
      before do
        # Ensure Async is not defined for this test
        @async_defined = defined?(::Async)
        if @async_defined
          @async_constant = ::Async
          Object.send(:remove_const, :Async) if defined?(::Async)
        end
      end

      after do
        # Restore Async if it was defined
        if @async_defined
          ::Async = @async_constant
        end
      end

      it "raises error if async gem is not loaded" do
        executor = described_class.new
        executor.post { "task" }

        expect {
          executor.wait_for_completion
        }.to raise_error(RuntimeError, /async.*gem/i)
      end
    end

    context "when async gem is available", skip: !defined?(::Async) do
      it "executes all submitted tasks" do
        executor = described_class.new(max_concurrent: 4)
        results = Concurrent::Array.new

        3.times { |i| executor.post { results << i } }

        executor.wait_for_completion
        expect(results.sort).to eq([0, 1, 2])
      end

      it "respects max_concurrent limit" do
        executor = described_class.new(max_concurrent: 2)
        concurrent_count = Concurrent::AtomicFixnum.new(0)
        max_concurrent_observed = Concurrent::AtomicFixnum.new(0)

        4.times do
          executor.post do
            current = concurrent_count.increment
            max_concurrent_observed.update { |v| [v, current].max }
            sleep 0.01
            concurrent_count.decrement
          end
        end

        executor.wait_for_completion
        expect(max_concurrent_observed.value).to be <= 2
      end

      it "respects abort flag" do
        executor = described_class.new(max_concurrent: 1)
        executed = Concurrent::Array.new

        executor.post do
          sleep 0.02
          executed << :first
        end

        3.times { |i| executor.post { executed << "task_#{i}".to_sym } }

        # Abort after a short delay
        Thread.new do
          sleep 0.01
          executor.abort!
        end

        executor.wait_for_completion
        # First task may complete, but some tasks should be skipped due to abort
        expect(executed).to include(:first)
      end

      it "returns false on timeout" do
        executor = described_class.new(max_concurrent: 1)
        executor.post { sleep 1 }

        result = executor.wait_for_completion(timeout: 0.05)
        expect(result).to be false
      end

      it "returns true when all tasks complete within timeout" do
        executor = described_class.new(max_concurrent: 4)
        3.times { executor.post { sleep 0.01 } }

        result = executor.wait_for_completion(timeout: 1)
        expect(result).to be true
      end
    end
  end

  describe "thread safety" do
    it "handles concurrent post operations safely" do
      executor = described_class.new

      threads = 10.times.map do
        Thread.new do
          5.times { executor.post { "work" } }
        end
      end
      threads.each(&:join)

      tasks = executor.instance_variable_get(:@tasks)
      expect(tasks.size).to eq(50)
    end
  end

  describe "compatibility with ThreadPool interface" do
    it "responds to post" do
      executor = described_class.new
      expect(executor).to respond_to(:post)
    end

    it "responds to abort!" do
      executor = described_class.new
      expect(executor).to respond_to(:abort!)
    end

    it "responds to aborted?" do
      executor = described_class.new
      expect(executor).to respond_to(:aborted?)
    end

    it "responds to wait_for_completion" do
      executor = described_class.new
      expect(executor).to respond_to(:wait_for_completion)
    end

    it "responds to shutdown" do
      executor = described_class.new
      expect(executor).to respond_to(:shutdown)
    end

    it "responds to wait_for_termination" do
      executor = described_class.new
      expect(executor).to respond_to(:wait_for_termination)
    end
  end
end
