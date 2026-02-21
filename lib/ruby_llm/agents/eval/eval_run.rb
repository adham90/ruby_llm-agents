# frozen_string_literal: true

module RubyLLM
  module Agents
    module Eval
      # Aggregate results from running an eval suite.
      #
      # Provides score calculation, pass/fail counts, failure details,
      # and a formatted summary string.
      class EvalRun
        attr_reader :suite, :results, :model, :pass_threshold,
          :started_at, :completed_at

        def initialize(suite:, results:, model:, pass_threshold:, started_at:, completed_at:)
          @suite = suite
          @results = results
          @model = model
          @pass_threshold = pass_threshold
          @started_at = started_at
          @completed_at = completed_at
        end

        def agent_class
          suite.respond_to?(:agent_class) ? suite.agent_class : suite
        end

        # Average score across all test cases (0.0 to 1.0)
        def score
          return 0.0 if results.empty?

          results.sum { |r| r.score.value } / results.size.to_f
        end

        def score_pct
          (score * 100).round(1)
        end

        def total_cases
          results.size
        end

        def passed
          results.count { |r| r.passed?(pass_threshold) }
        end

        def failed
          results.count { |r| r.failed?(pass_threshold) }
        end

        def failures
          results.select { |r| r.failed?(pass_threshold) }
        end

        def errors
          results.select(&:errored?)
        end

        def total_cost
          results.sum do |r|
            next 0 unless r.execution_id

            if defined?(Execution)
              Execution.find_by(id: r.execution_id)&.total_cost || 0
            else
              0
            end
          end
        rescue
          0
        end

        def duration_ms
          return 0 unless started_at && completed_at

          ((completed_at - started_at) * 1000).to_i
        end

        def summary
          agent_name = agent_class.respond_to?(:name) ? agent_class.name : agent_class.to_s
          lines = ["#{agent_name} Eval — #{started_at.strftime("%Y-%m-%d %H:%M")}"]
          lines << "Model: #{model} | Score: #{score_pct}% | #{passed}/#{total_cases} passed"
          lines << "Cost: $#{"%.4f" % total_cost} | Duration: #{(duration_ms / 1000.0).round(1)}s"

          if failures.any?
            lines << ""
            lines << "Failures:"
            failures.each do |r|
              lines << "  - #{r.test_case_name}: expected #{r.expected.inspect}, got #{r.actual.inspect} (#{r.score.reason})"
            end
          end

          if errors.any?
            lines << ""
            lines << "Errors:"
            errors.each do |r|
              lines << "  - #{r.test_case_name}: #{r.error.message}"
            end
          end

          lines.join("\n")
        end

        def to_h
          {
            agent: agent_class.respond_to?(:name) ? agent_class.name : agent_class.to_s,
            model: model,
            score: score,
            score_pct: score_pct,
            total_cases: total_cases,
            passed: passed,
            failed: failed,
            total_cost: total_cost,
            duration_ms: duration_ms,
            results: results.map(&:to_h)
          }
        end

        def to_json(*args)
          to_h.to_json(*args)
        end
      end
    end
  end
end
