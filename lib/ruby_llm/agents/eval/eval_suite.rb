# frozen_string_literal: true

module RubyLLM
  module Agents
    module Eval
      # Score value object — returned by every scorer
      Score = Struct.new(:value, :reason, keyword_init: true) do
        def initialize(value:, reason: nil)
          super(value: value.to_f.clamp(0.0, 1.0), reason: reason)
        end

        def passed?(threshold = 0.5)
          value >= threshold
        end

        def failed?(threshold = 0.5)
          !passed?(threshold)
        end
      end

      # A single test case definition
      TestCase = Struct.new(:name, :input, :expected, :scorer, :options, keyword_init: true) do
        def resolve_input
          input.is_a?(Proc) ? input.call : input
        end
      end

      # Defines test cases for an agent, runs them, scores results.
      #
      # @example
      #   class SupportRouter::Eval < RubyLLM::Agents::EvalSuite
      #     agent SupportRouter
      #     test_case "billing", input: { message: "charged twice" }, expected: { route: :billing }
      #   end
      #
      #   run = SupportRouter::Eval.run!
      #   puts run.summary
      class EvalSuite
        class << self
          attr_reader :agent_class, :test_cases, :eval_options

          def inherited(subclass)
            super
            subclass.instance_variable_set(:@test_cases, [])
            subclass.instance_variable_set(:@eval_options, {})
          end

          # --- DSL ---

          def agent(klass)
            @agent_class = klass
          end

          def test_case(name, input:, expected: nil, score: nil, **options)
            @test_cases << TestCase.new(
              name: name,
              input: input,
              expected: expected,
              scorer: score,
              options: options
            )
          end

          def dataset(path)
            full_path = path.start_with?("/") ? path : Rails.root.join(path).to_s
            cases = YAML.safe_load_file(full_path, symbolize_names: true)
            cases.each do |tc|
              test_case(
                tc[:name],
                input: tc[:input],
                expected: tc[:expected],
                score: tc[:score]&.to_sym,
                **tc.except(:name, :input, :expected, :score)
              )
            end
          end

          def eval_model(value)
            @eval_options[:model] = value
          end

          def eval_temperature(value)
            @eval_options[:temperature] = value
          end

          # --- Running ---

          def run!(model: nil, only: nil, pass_threshold: 0.5, overrides: {}, **options)
            validate!
            cases = only ? @test_cases.select { |tc| Array(only).include?(tc.name) } : @test_cases
            resolved_model = model || @eval_options[:model]
            temperature = @eval_options[:temperature]
            started_at = Time.current

            results = cases.map do |tc|
              run_single(tc, model: resolved_model, temperature: temperature, overrides: overrides)
            end

            EvalRun.new(
              suite: self,
              results: results,
              model: resolved_model || (agent_class.respond_to?(:model) ? agent_class.model : nil),
              pass_threshold: pass_threshold,
              started_at: started_at,
              completed_at: Time.current
            )
          end

          def validate!
            raise ConfigurationError, "No agent class set" unless @agent_class
            raise ConfigurationError, "No test cases defined" if @test_cases.empty?

            @test_cases.each do |tc|
              next if tc.input.is_a?(Proc)
              next unless @agent_class.respond_to?(:params)

              agent_params = @agent_class.params
              required = agent_params.select { |_, v| v[:required] }.keys
              missing = required - tc.input.keys
              if missing.any?
                raise ConfigurationError,
                  "Test case '#{tc.name}' missing required params: #{missing.join(", ")}"
              end
            end
            true
          end

          def for(agent_klass, &block)
            suite = Class.new(self)
            suite.agent(agent_klass)
            suite.instance_eval(&block) if block
            suite
          end

          private

          def run_single(tc, model:, temperature:, overrides:)
            input = tc.resolve_input
            call_options = input.dup
            call_options.merge!(overrides) if overrides.any?
            call_options[:model] = model if model
            call_options[:temperature] = temperature if temperature

            agent_result = agent_class.call(**call_options)
            score = evaluate(tc, agent_result)

            EvalResult.new(
              test_case: tc,
              agent_result: agent_result,
              score: score,
              execution_id: agent_result.respond_to?(:execution_id) ? agent_result.execution_id : nil
            )
          rescue => e
            EvalResult.new(
              test_case: tc,
              agent_result: nil,
              score: Score.new(value: 0.0, reason: "Error: #{e.class}: #{e.message}"),
              error: e
            )
          end

          def evaluate(tc, agent_result)
            case tc.scorer
            when Proc
              coerce_score(tc.scorer.call(agent_result, tc.expected))
            when :contains
              score_contains(agent_result, tc.expected)
            when :llm_judge
              score_llm_judge(agent_result, tc)
            when :exact_match, nil
              score_exact_match(agent_result, tc.expected)
            else
              raise ArgumentError, "Unknown scorer: #{tc.scorer}"
            end
          end

          def coerce_score(value)
            case value
            when Score then value
            when Numeric then Score.new(value: value)
            when true then Score.new(value: 1.0)
            when false then Score.new(value: 0.0)
            else Score.new(value: 0.0, reason: "Scorer returned #{value.class}")
            end
          end

          # --- Built-in scorers ---

          def score_exact_match(result, expected)
            actual = extract_comparable(result)
            expected_val = normalize_expected(expected)

            if actual == expected_val
              Score.new(value: 1.0)
            else
              Score.new(value: 0.0, reason: "Expected #{expected_val.inspect}, got #{actual.inspect}")
            end
          end

          def score_contains(result, expected)
            content = result.respond_to?(:content) ? result.content.to_s : result.to_s
            targets = Array(expected)
            missing = targets.reject { |e| content.downcase.include?(e.to_s.downcase) }

            if missing.empty?
              Score.new(value: 1.0)
            else
              Score.new(value: 0.0, reason: "Missing: #{missing.join(", ")}")
            end
          end

          def score_llm_judge(result, tc)
            content = result.respond_to?(:content) ? result.content.to_s : result.to_s
            criteria = tc.options[:criteria]
            judge_model = tc.options[:judge_model] || "gpt-4o-mini"

            prompt = <<~PROMPT
              You are evaluating an AI agent's response. Score it from 0 to 10.

              ## Input
              #{tc.input.inspect}

              ## Agent Response
              #{content}

              ## Criteria
              #{criteria}

              Respond with ONLY a JSON object:
              {"score": <0-10>, "reason": "<brief explanation>"}
            PROMPT

            chat = RubyLLM.chat(model: judge_model)
            parsed = JSON.parse(chat.ask(prompt).content)
            Score.new(value: parsed["score"].to_f / 10.0, reason: parsed["reason"])
          rescue => e
            Score.new(value: 0.0, reason: "Judge error: #{e.message}")
          end

          def extract_comparable(result)
            if result.respond_to?(:route)
              {route: result.route}
            elsif result.respond_to?(:content)
              content = result.content
              content.is_a?(Hash) ? content.transform_keys(&:to_sym) : content.to_s.strip
            else
              result
            end
          end

          def normalize_expected(expected)
            case expected
            when Hash then expected.transform_keys(&:to_sym)
            when String then expected.strip
            else expected
            end
          end
        end
      end
    end
  end
end
