# frozen_string_literal: true

module RubyLLM
  module Agents
    module Eval
      # Holds the result of evaluating a single test case.
      #
      # Contains the test case definition, the agent's result, the score,
      # and any error that occurred during execution.
      class EvalResult
        attr_reader :test_case, :agent_result, :score, :execution_id, :error

        def initialize(test_case:, agent_result:, score:, execution_id: nil, error: nil)
          @test_case = test_case
          @agent_result = agent_result
          @score = score
          @execution_id = execution_id
          @error = error
        end

        def test_case_name
          test_case.name
        end

        def input
          test_case.input
        end

        def expected
          test_case.expected
        end

        def passed?(threshold = 0.5)
          score.passed?(threshold)
        end

        def failed?(threshold = 0.5)
          score.failed?(threshold)
        end

        def errored?
          !error.nil?
        end

        def actual
          return nil unless agent_result

          if agent_result.respond_to?(:route)
            {route: agent_result.route}
          elsif agent_result.respond_to?(:content)
            agent_result.content
          else
            agent_result
          end
        end

        def to_h
          {
            name: test_case_name,
            score: score.value,
            reason: score.reason,
            passed: passed?,
            input: input,
            expected: expected,
            actual: actual,
            execution_id: execution_id,
            error: error&.message
          }
        end
      end
    end
  end
end
