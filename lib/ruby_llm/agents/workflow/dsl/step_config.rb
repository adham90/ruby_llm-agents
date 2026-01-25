# frozen_string_literal: true

module RubyLLM
  module Agents
    class Workflow
      module DSL
        # Configuration object for a workflow step
        #
        # Holds all the configuration options for a step including the agent,
        # input mapping, conditions, retry settings, error handling, and metadata.
        #
        # @example Basic step config
        #   StepConfig.new(name: :validate, agent: ValidatorAgent)
        #
        # @example Full configuration
        #   StepConfig.new(
        #     name: :process,
        #     agent: ProcessorAgent,
        #     description: "Process the order",
        #     timeout: 30,
        #     retry_config: { max: 3, on: [Timeout::Error] },
        #     critical: true
        #   )
        #
        # @api private
        class StepConfig
          attr_reader :name, :agent, :description, :options, :block

          # @param name [Symbol] Step identifier
          # @param agent [Class, nil] Agent class to execute
          # @param description [String, nil] Human-readable description
          # @param options [Hash] Step configuration options
          # @param block [Proc, nil] Block for routing or custom logic
          def initialize(name:, agent: nil, description: nil, options: {}, block: nil)
            @name = name
            @agent = agent
            @options = normalize_options(options)
            # description can come from direct param or from :desc option
            @description = description || @options[:description]
            @block = block
          end

          # Returns whether this step uses routing
          #
          # @return [Boolean]
          def routing?
            options[:on].present? && block.present?
          end

          # Returns whether this step has a custom block
          #
          # @return [Boolean]
          def custom_block?
            block.present? && !routing?
          end

          # Returns whether this step is optional (continues on failure)
          #
          # @return [Boolean]
          def optional?
            options[:optional] == true
          end

          # Returns whether this step executes a sub-workflow
          #
          # @return [Boolean]
          def workflow?
            return false unless agent.present?
            return false unless agent.is_a?(Class)

            # agent < Workflow returns nil if agent is not a subclass
            (agent < RubyLLM::Agents::Workflow) == true
          rescue TypeError, ArgumentError
            # agent < Workflow raises TypeError/ArgumentError if agent is not a valid Class
            false
          end

          # Returns whether this step uses iteration
          #
          # @return [Boolean]
          def iteration?
            options[:each].present?
          end

          # Returns the source for iteration items
          #
          # @return [Proc, nil]
          def each_source
            options[:each]
          end

          # Returns the concurrency level for iteration
          #
          # @return [Integer, nil]
          def iteration_concurrency
            options[:concurrency]
          end

          # Returns whether iteration should fail fast on first error
          #
          # @return [Boolean]
          def iteration_fail_fast?
            options[:fail_fast] == true
          end

          # Returns whether iteration should continue on individual item errors
          #
          # @return [Boolean]
          def continue_on_error?
            options[:continue_on_error] == true
          end

          # Returns whether this step is critical (fails workflow on error)
          #
          # @return [Boolean]
          def critical?
            options[:critical] != false && !optional?
          end

          # Returns the timeout for this step
          #
          # @return [Integer, nil] Timeout in seconds
          def timeout
            value = options[:timeout]
            return nil unless value
            value.respond_to?(:to_i) ? value.to_i : value
          end

          # Returns retry configuration
          #
          # @return [Hash] Retry settings
          def retry_config
            @retry_config ||= normalize_retry_config
          end

          # Returns the fallback agent(s)
          #
          # @return [Array<Class>] Fallback agents
          def fallbacks
            @fallbacks ||= Array(options[:fallback]).compact
          end

          # Returns the condition for step execution
          #
          # @return [Symbol, Proc, nil]
          def if_condition
            options[:if]
          end

          # Returns the negative condition for step execution
          #
          # @return [Symbol, Proc, nil]
          def unless_condition
            options[:unless]
          end

          # Returns the input mapper (lambda or pick config)
          #
          # @return [Proc, nil]
          def input_mapper
            options[:input]
          end

          # Returns fields to pick from previous step
          #
          # @return [Array<Symbol>, nil]
          def pick_fields
            options[:pick]
          end

          # Returns the source step for pick operation
          #
          # @return [Symbol, nil]
          def pick_from
            options[:from]
          end

          # Returns the default value when step is skipped or fails (optional)
          #
          # @return [Object, nil]
          def default_value
            options[:default]
          end

          # Returns the error handler
          #
          # @return [Symbol, Proc, nil]
          def error_handler
            options[:on_error]
          end

          # Returns UI-friendly label
          #
          # @return [String, nil]
          def ui_label
            options[:ui_label]
          end

          # Returns tags for the step
          #
          # @return [Array<Symbol>]
          def tags
            Array(options[:tags])
          end

          # Resolves the input for this step
          #
          # @param workflow [Workflow] The workflow instance
          # @param previous_result [Result, nil] Previous step result
          # @return [Hash] Input for the agent
          def resolve_input(workflow, previous_result)
            if input_mapper
              workflow.instance_exec(&input_mapper)
            elsif pick_fields
              source = pick_from ? workflow.step_result(pick_from) : previous_result
              source_hash = extract_content_hash(source)
              source_hash.slice(*pick_fields)
            else
              # Default: merge original input with previous step output
              base = workflow.input.to_h
              previous_hash = extract_content_hash(previous_result)
              base.merge(previous_hash)
            end
          end

          # Resolves the route for routing steps
          #
          # @param workflow [Workflow] The workflow instance
          # @return [Hash] Route configuration with :agent and :options
          def resolve_route(workflow)
            raise "Not a routing step" unless routing?

            value = workflow.instance_exec(&options[:on])
            builder = RouteBuilder.new
            block.call(builder)
            builder.resolve(value)
          end

          # Evaluates whether the step should execute
          #
          # @param workflow [Workflow] The workflow instance
          # @return [Boolean]
          def should_execute?(workflow)
            passes_if = if_condition.nil? || evaluate_condition(workflow, if_condition)
            passes_unless = unless_condition.nil? || !evaluate_condition(workflow, unless_condition)
            passes_if && passes_unless
          end

          # Converts to hash for serialization
          #
          # @return [Hash]
          def to_h
            {
              name: name,
              agent: agent&.name,
              description: description,
              timeout: timeout,
              optional: optional?,
              critical: critical?,
              retry_config: retry_config,
              fallbacks: fallbacks.map(&:name),
              tags: tags,
              ui_label: ui_label,
              workflow: workflow?,
              iteration: iteration?,
              iteration_concurrency: iteration_concurrency,
              iteration_fail_fast: iteration_fail_fast?
            }.compact
          end

          private

          def normalize_options(opts)
            # Handle desc as alias for description
            opts[:description] ||= opts.delete(:desc)
            opts
          end

          def normalize_retry_config
            retry_opt = options[:retry]
            on_opt = options[:on]

            case retry_opt
            when Integer
              {
                max: retry_opt,
                on: normalize_error_classes(on_opt) || [StandardError],
                backoff: :none,
                delay: 1
              }
            when Hash
              {
                max: retry_opt[:max] || 3,
                on: normalize_error_classes(retry_opt[:on] || on_opt) || [StandardError],
                backoff: retry_opt[:backoff] || :none,
                delay: retry_opt[:delay] || 1
              }
            else
              { max: 0, on: [], backoff: :none, delay: 1 }
            end
          end

          def normalize_error_classes(classes)
            return nil if classes.nil?
            Array(classes)
          end

          def evaluate_condition(workflow, condition)
            case condition
            when Symbol then workflow.send(condition)
            when Proc then workflow.instance_exec(&condition)
            else condition
            end
          end

          def extract_content_hash(result)
            return {} if result.nil?

            content = result.respond_to?(:content) ? result.content : result
            content.is_a?(Hash) ? content : {}
          end
        end
      end
    end
  end
end
