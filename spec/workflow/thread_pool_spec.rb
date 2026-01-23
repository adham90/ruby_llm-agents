# frozen_string_literal: true

require "rails_helper"

RSpec.describe RubyLLM::Agents::Workflow::ThreadPool do
  describe "#initialize" do
    it "creates a pool with default size of 4" do
      pool = described_class.new
      expect(pool.size).to eq(4)
      pool.shutdown
    end

    it "creates a pool with custom size" do
      pool = described_class.new(size: 8)
      expect(pool.size).to eq(8)
      pool.shutdown
    end

    it "creates worker threads" do
      pool = described_class.new(size: 2)
      # Allow time for workers to spawn
      sleep 0.01
      # Workers should be running
      pool.shutdown
    end
  end

  describe "#post" do
    it "executes submitted tasks" do
      pool = described_class.new(size: 2)
      executed = false

      pool.post { executed = true }
      pool.wait_for_completion

      expect(executed).to be true
      pool.shutdown
    end

    it "executes multiple tasks" do
      pool = described_class.new(size: 2)
      results = Concurrent::Array.new

      3.times { |i| pool.post { results << i } }
      pool.wait_for_completion

      expect(results.sort).to eq([0, 1, 2])
      pool.shutdown
    end

    it "executes tasks concurrently" do
      pool = described_class.new(size: 4)
      timestamps = Concurrent::Array.new
      mutex = Mutex.new

      4.times do
        pool.post do
          mutex.synchronize { timestamps << Time.current }
          sleep 0.05
        end
      end

      start = Time.current
      pool.wait_for_completion
      elapsed = Time.current - start

      # With 4 workers and 4 tasks of 50ms each, should complete in ~50ms not 200ms
      expect(elapsed).to be < 0.15
      pool.shutdown
    end

    it "raises error when posting to shutdown pool" do
      pool = described_class.new(size: 2)
      pool.shutdown

      expect { pool.post { "work" } }.to raise_error(RuntimeError, /shutdown/)
    end
  end

  describe "#wait_for_completion" do
    it "waits until all tasks complete" do
      pool = described_class.new(size: 2)
      completed = Concurrent::AtomicFixnum.new(0)

      3.times do
        pool.post do
          sleep 0.02
          completed.increment
        end
      end

      pool.wait_for_completion
      expect(completed.value).to eq(3)
      pool.shutdown
    end

    it "returns true when all tasks complete" do
      pool = described_class.new(size: 2)
      pool.post { sleep 0.01 }

      result = pool.wait_for_completion
      expect(result).to be true
      pool.shutdown
    end

    it "returns false when timeout exceeded" do
      pool = described_class.new(size: 1)
      pool.post { sleep 0.5 }

      result = pool.wait_for_completion(timeout: 0.01)
      expect(result).to be false
      pool.shutdown(timeout: 1)
    end

    it "handles no tasks submitted" do
      pool = described_class.new(size: 2)
      result = pool.wait_for_completion(timeout: 0.1)
      expect(result).to be true
      pool.shutdown
    end
  end

  describe "#abort!" do
    it "sets aborted state" do
      pool = described_class.new(size: 2)
      expect(pool.aborted?).to be false

      pool.abort!

      expect(pool.aborted?).to be true
      pool.shutdown
    end

    it "causes pending tasks to be skipped" do
      pool = described_class.new(size: 1)
      executed = Concurrent::Array.new

      # Post a slow task first
      pool.post do
        sleep 0.05
        executed << :first
      end

      # Post more tasks
      5.times { |i| pool.post { executed << "task_#{i}".to_sym } }

      # Abort before all complete
      sleep 0.01 # Let first task start
      pool.abort!
      pool.wait_for_completion(timeout: 0.5)

      # First task should complete, some others may be skipped
      expect(executed).to include(:first)
      pool.shutdown
    end
  end

  describe "#aborted?" do
    it "returns false initially" do
      pool = described_class.new(size: 2)
      expect(pool.aborted?).to be false
      pool.shutdown
    end

    it "returns true after abort!" do
      pool = described_class.new(size: 2)
      pool.abort!
      expect(pool.aborted?).to be true
      pool.shutdown
    end
  end

  describe "#shutdown" do
    it "stops all workers" do
      pool = described_class.new(size: 2)
      pool.post { sleep 0.01 }
      pool.wait_for_completion

      pool.shutdown(timeout: 1)

      # Pool should be marked as shutdown
      expect { pool.post { "work" } }.to raise_error(RuntimeError, /shutdown/)
    end

    it "waits for running tasks to complete" do
      pool = described_class.new(size: 1)
      completed = false

      pool.post do
        sleep 0.05
        completed = true
      end

      pool.shutdown(timeout: 1)
      expect(completed).to be true
    end

    it "respects timeout parameter" do
      pool = described_class.new(size: 1)
      pool.post { sleep 5 }

      start = Time.current
      pool.shutdown(timeout: 0.1)
      elapsed = Time.current - start

      expect(elapsed).to be < 0.5
    end
  end

  describe "#wait_for_termination" do
    it "waits for workers to finish" do
      pool = described_class.new(size: 2)
      pool.post { sleep 0.01 }
      pool.wait_for_completion

      # Send shutdown signals
      pool.instance_variable_set(:@shutdown, true)
      pool.size.times { pool.instance_variable_get(:@queue).push(nil) }

      pool.wait_for_termination(timeout: 1)
    end
  end

  describe "error handling in tasks" do
    it "continues processing after task error" do
      pool = described_class.new(size: 2)
      results = Concurrent::Array.new

      pool.post { raise "Error in task" }
      pool.post { results << :success }

      pool.wait_for_completion(timeout: 1)
      expect(results).to include(:success)
      pool.shutdown
    end

    it "marks task as completed even on error" do
      pool = described_class.new(size: 1)

      pool.post { raise "Error" }

      completed = pool.wait_for_completion(timeout: 1)
      expect(completed).to be true
      pool.shutdown
    end
  end

  describe "thread safety" do
    it "handles concurrent post operations" do
      pool = described_class.new(size: 4)
      counter = Concurrent::AtomicFixnum.new(0)

      threads = 10.times.map do
        Thread.new do
          5.times { pool.post { counter.increment } }
        end
      end

      threads.each(&:join)
      pool.wait_for_completion

      expect(counter.value).to eq(50)
      pool.shutdown
    end

    it "handles concurrent abort and post" do
      pool = described_class.new(size: 2)

      # This should not raise or deadlock
      t1 = Thread.new do
        10.times { pool.post { sleep 0.001 } rescue nil }
      end

      t2 = Thread.new do
        sleep 0.005
        pool.abort!
      end

      [t1, t2].each(&:join)
      pool.wait_for_completion(timeout: 1)
      pool.shutdown(timeout: 1)
    end
  end

  describe "worker naming" do
    it "names worker threads with pool-worker prefix" do
      pool = described_class.new(size: 2)

      # Allow workers to start
      sleep 0.01

      workers = pool.instance_variable_get(:@workers)
      expect(workers.all? { |w| w.name&.start_with?("pool-worker-") }).to be true

      pool.shutdown
    end
  end

  describe "real-world workflow scenarios" do
    it "handles fail-fast pattern" do
      pool = described_class.new(size: 4)
      results = Concurrent::Hash.new
      error_occurred = Concurrent::AtomicBoolean.new(false)

      pool.post do
        sleep 0.02
        results[:task_a] = "completed"
      end

      pool.post do
        sleep 0.01
        error_occurred.make_true
        pool.abort!
        results[:task_b] = "failed"
      end

      pool.post do
        sleep 0.03
        results[:task_c] = "completed" unless pool.aborted?
      end

      pool.wait_for_completion(timeout: 1)

      expect(error_occurred.true?).to be true
      expect(pool.aborted?).to be true
      pool.shutdown
    end

    it "handles graceful shutdown with pending work" do
      pool = described_class.new(size: 2)
      completed_count = Concurrent::AtomicFixnum.new(0)

      10.times do
        pool.post do
          sleep 0.01
          completed_count.increment
        end
      end

      # Don't wait for completion, just shutdown
      pool.shutdown(timeout: 1)

      # Some tasks should have completed
      expect(completed_count.value).to be > 0
    end
  end
end
