# frozen_string_literal: true

require "ostruct"
require_relative "dsl/step_config"
require_relative "dsl/route_builder"
require_relative "dsl/parallel_group"
require_relative "dsl/input_schema"
require_relative "dsl/step_executor"
require_relative "dsl/iteration_executor"
require_relative "dsl/wait_config"
require_relative "dsl/wait_executor"
require_relative "dsl/schedule_helpers"

module RubyLLM
  module Agents
    class Workflow
      # Refined DSL for declarative workflow definition
      #
      # This module provides a clean, expressive syntax for defining workflows
      # with minimal boilerplate for common patterns while maintaining full
      # flexibility for complex scenarios.
      #
      # @example Minimal workflow
      #   class SimpleWorkflow < RubyLLM::Agents::Workflow
      #     step :fetch, FetcherAgent
      #     step :process, ProcessorAgent
      #     step :save, SaverAgent
      #   end
      #
      # @example Full-featured workflow
      #   class OrderWorkflow < RubyLLM::Agents::Workflow
      #     description "Process customer orders end-to-end"
      #
      #     input do
      #       required :order_id, String
      #       optional :priority, String, default: "normal"
      #     end
      #
      #     step :fetch, FetcherAgent, timeout: 1.minute
      #     step :validate, ValidatorAgent
      #
      #     step :process, on: -> { validate.tier } do |route|
      #       route.premium  PremiumAgent
      #       route.standard StandardAgent
      #       route.default  DefaultAgent
      #     end
      #
      #     parallel do
      #       step :analyze, AnalyzerAgent
      #       step :summarize, SummarizerAgent
      #     end
      #
      #     step :notify, NotifierAgent, if: :should_notify?
      #
      #     private
      #
      #     def should_notify?
      #       input.callback_url.present?
      #     end
      #   end
      #
      # @api public
      module DSL
        def self.included(base)
          base.extend(ClassMethods)
          base.include(InstanceMethods)
        end

        # Class-level DSL methods
        module ClassMethods
          # Returns the ordered list of steps/groups
          #
          # @return [Array<Symbol, ParallelGroup>]
          def step_order
            @step_order ||= []
          end

          # Returns step configurations
          #
          # @return [Hash<Symbol, StepConfig>]
          def step_configs
            @step_configs ||= {}
          end

          # Returns parallel groups
          #
          # @return [Array<ParallelGroup>]
          def parallel_groups
            @parallel_groups ||= []
          end

          # Returns wait step configurations
          #
          # @return [Array<WaitConfig>]
          def wait_configs
            @wait_configs ||= []
          end

          # Returns the input schema
          #
          # @return [InputSchema, nil]
          def input_schema
            @input_schema
          end

          # Returns the output schema
          #
          # @return [OutputSchema, nil]
          def output_schema
            @output_schema
          end

          # Inherits DSL configuration from parent class
          def inherited(subclass)
            super
            subclass.instance_variable_set(:@step_order, step_order.dup)
            subclass.instance_variable_set(:@step_configs, step_configs.dup)
            subclass.instance_variable_set(:@parallel_groups, parallel_groups.dup)
            subclass.instance_variable_set(:@wait_configs, wait_configs.dup)
            subclass.instance_variable_set(:@input_schema, input_schema&.dup)
            subclass.instance_variable_set(:@output_schema, output_schema&.dup)
            subclass.instance_variable_set(:@lifecycle_hooks, @lifecycle_hooks&.dup || {})
          end

          # Defines a workflow step
          #
          # @param name [Symbol] Step identifier
          # @param agent [Class, nil] Agent class to execute (optional if using block)
          # @param desc [String, nil] Human-readable description
          # @param options [Hash] Step options (timeout, retry, if, unless, etc.)
          # @yield [route] Block for routing or custom logic
          # @return [void]
          #
          # @example Minimal step
          #   step :validate, ValidatorAgent
          #
          # @example With options
          #   step :fetch, FetcherAgent, timeout: 30.seconds, retry: 3
          #
          # @example With routing
          #   step :process, on: -> { classify.type } do |r|
          #     r.typeA AgentA
          #     r.typeB AgentB
          #     r.default DefaultAgent
          #   end
          #
          # @example With custom block
          #   step :custom do
          #     skip! "No data" if input.data.empty?
          #     agent CustomAgent, data: transform(input.data)
          #   end
          def step(name, agent = nil, desc = nil, **options, &block)
            # Handle positional description
            description = desc.is_a?(String) ? desc : nil
            if desc.is_a?(Hash)
              options = desc.merge(options)
            end

            config = StepConfig.new(
              name: name,
              agent: agent,
              description: description,
              options: options,
              block: block
            )

            step_configs[name] = config

            # Add to order if not in a parallel block
            unless @_defining_parallel
              step_order << name
            end
          end

          # Defines a group of steps that execute in parallel
          #
          # @param name [Symbol, nil] Optional name for the group
          # @param options [Hash] Group options (fail_fast, concurrency, timeout)
          # @yield Block defining the parallel steps
          # @return [void]
          #
          # @example Unnamed parallel group
          #   parallel do
          #     step :sentiment, SentimentAgent
          #     step :keywords, KeywordAgent
          #   end
          #
          # @example Named parallel group
          #   parallel :analysis do
          #     step :sentiment, SentimentAgent
          #     step :keywords, KeywordAgent
          #   end
          def parallel(name = nil, **options, &block)
            @_defining_parallel = true
            previous_step_count = step_configs.size

            # Execute the block to collect step definitions
            instance_eval(&block)

            # Find newly added steps
            new_steps = step_configs.keys.last(step_configs.size - previous_step_count)

            group = ParallelGroup.new(
              name: name,
              step_names: new_steps,
              options: options
            )

            parallel_groups << group
            step_order << group

            @_defining_parallel = false
          end

          # Defines a simple delay wait step
          #
          # @param duration [ActiveSupport::Duration, Integer, Float] Duration to wait
          # @param options [Hash] Wait options (if:, unless:)
          # @return [void]
          #
          # @example Simple delay
          #   wait 5.seconds
          #
          # @example Conditional delay
          #   wait 5.seconds, if: :needs_cooldown?
          def wait(duration, **options)
            config = WaitConfig.new(type: :delay, duration: duration, **options)
            wait_configs << config
            step_order << config
          end

          # Defines a conditional wait step that polls until a condition is met
          #
          # @param condition [Proc, nil] Lambda that returns true when ready to proceed
          # @param time [Proc, Time, nil] Time to wait until (for scheduled waits)
          # @param options [Hash] Wait options (poll_interval:, timeout:, on_timeout:, backoff:)
          # @yield Block as condition (alternative to condition param)
          # @return [void]
          #
          # @example Wait until condition
          #   wait_until -> { payment.confirmed? }, poll_interval: 5.seconds, timeout: 10.minutes
          #
          # @example With block
          #   wait_until(poll_interval: 1.second) { order.ready? }
          #
          # @example Wait until specific time
          #   wait_until time: -> { next_weekday_at(9, 0) }
          def wait_until(condition = nil, time: nil, **options, &block)
            condition ||= block

            if time
              config = WaitConfig.new(type: :schedule, condition: time, **options)
            else
              config = WaitConfig.new(type: :until, condition: condition, **options)
            end

            wait_configs << config
            step_order << config
          end

          # Defines a human-in-the-loop approval wait step
          #
          # @param name [Symbol] Identifier for the approval point
          # @param options [Hash] Approval options (notify:, message:, timeout:, approvers:, etc.)
          # @return [void]
          #
          # @example Simple approval
          #   wait_for :manager_approval
          #
          # @example With notifications and timeout
          #   wait_for :review,
          #     notify: [:email, :slack],
          #     message: -> { "Please review: #{draft.title}" },
          #     timeout: 24.hours,
          #     reminder_after: 4.hours
          def wait_for(name, **options)
            config = WaitConfig.new(type: :approval, name: name, **options)
            wait_configs << config
            step_order << config
          end

          # Defines the input schema
          #
          # @yield Block defining required and optional fields
          # @return [void]
          #
          # @example
          #   input do
          #     required :order_id, String
          #     optional :priority, String, default: "normal"
          #   end
          def input(&block)
            @input_schema = InputSchema.new
            @input_schema.instance_eval(&block)
          end

          # Defines the output schema
          #
          # @yield Block defining required and optional fields
          # @return [void]
          def output(&block)
            @output_schema = OutputSchema.new
            @output_schema.instance_eval(&block)
          end

          # Registers a lifecycle hook
          #
          # @param hook_name [Symbol] Hook type
          # @param step_name [Symbol, nil] Specific step (nil for all)
          # @param method_name [Symbol, nil] Method to call
          # @yield Block to execute
          # @return [void]
          def register_hook(hook_name, step_name = nil, method_name = nil, &block)
            @lifecycle_hooks ||= {}
            @lifecycle_hooks[hook_name] ||= []
            @lifecycle_hooks[hook_name] << {
              step: step_name,
              method: method_name,
              block: block
            }
          end

          # Hooks that run before the workflow starts
          def before_workflow(method_name = nil, &block)
            register_hook(:before_workflow, nil, method_name, &block)
          end

          # Hooks that run after the workflow completes
          def after_workflow(method_name = nil, &block)
            register_hook(:after_workflow, nil, method_name, &block)
          end

          # Hooks that run before each step
          def before_step(step_name = nil, method_name = nil, &block)
            register_hook(:before_step, step_name, method_name, &block)
          end

          # Hooks that run after each step
          def after_step(step_name = nil, method_name = nil, &block)
            register_hook(:after_step, step_name, method_name, &block)
          end

          # Hooks that run when a step fails
          def on_step_failure(step_name = nil, method_name = nil, &block)
            register_hook(:on_step_failure, step_name, method_name, &block)
          end

          # Hooks that run when a step starts
          def on_step_start(method_name = nil, &block)
            register_hook(:on_step_start, nil, method_name, &block)
          end

          # Hooks that run when a step completes
          def on_step_complete(method_name = nil, &block)
            register_hook(:on_step_complete, nil, method_name, &block)
          end

          # Hooks that run when a step errors
          def on_step_error(method_name = nil, &block)
            register_hook(:on_step_error, nil, method_name, &block)
          end

          # Returns lifecycle hooks
          #
          # @return [Hash]
          def lifecycle_hooks
            @lifecycle_hooks ||= {}
          end

          # Returns step metadata for UI display
          #
          # @return [Array<Hash>]
          def step_metadata
            step_order.flat_map do |item|
              case item
              when Symbol
                config = step_configs[item]
                [{
                  name: item,
                  agent: config.agent&.name,
                  description: config.description,
                  ui_label: config.ui_label || item.to_s.humanize,
                  optional: config.optional?,
                  timeout: config.timeout,
                  routing: config.routing?,
                  parallel: false,
                  workflow: config.workflow?,
                  iteration: config.iteration?,
                  iteration_concurrency: config.iteration_concurrency,
                  throttle: config.throttle,
                  rate_limit: config.rate_limit
                }.compact]
              when ParallelGroup
                item.step_names.map do |step_name|
                  config = step_configs[step_name]
                  {
                    name: step_name,
                    agent: config.agent&.name,
                    description: config.description,
                    ui_label: config.ui_label || step_name.to_s.humanize,
                    optional: config.optional?,
                    timeout: config.timeout,
                    routing: config.routing?,
                    parallel: true,
                    parallel_group: item.name,
                    workflow: config.workflow?,
                    iteration: config.iteration?,
                    iteration_concurrency: config.iteration_concurrency,
                    throttle: config.throttle,
                    rate_limit: config.rate_limit
                  }.compact
                end
              when WaitConfig
                [{
                  name: item.name || "wait_#{item.type}",
                  type: :wait,
                  wait_type: item.type,
                  ui_label: item.ui_label,
                  timeout: item.timeout,
                  parallel: false,
                  duration: item.duration,
                  poll_interval: item.poll_interval,
                  on_timeout: item.on_timeout,
                  notify: item.notify_channels,
                  approvers: item.approvers
                }.compact]
              end
            end
          end

          # Returns the total number of steps
          #
          # @return [Integer]
          def total_steps
            step_configs.size
          end

          # Validates workflow configuration
          #
          # @return [Array<String>] Validation errors
          def validate_configuration
            errors = []

            step_configs.each do |name, config|
              if config.agent.nil? && !config.custom_block? && !config.routing?
                errors << "Step :#{name} has no agent defined"
              end

              if config.routing?
                builder = RouteBuilder.new
                config.block.call(builder)
                if builder.routes.empty? && builder.default.nil?
                  errors << "Step :#{name} has no routes defined"
                end
              end
            end

            errors
          end
        end

        # Instance-level DSL methods
        module InstanceMethods
          # Returns the validated input
          #
          # @return [OpenStruct] Input with accessor methods
          def input
            @validated_input ||= begin
              schema = self.class.input_schema
              validated = schema ? schema.validate!(options) : options
              OpenStruct.new(validated)
            end
          end

          # Returns a step result by name
          #
          # @param name [Symbol] Step name
          # @return [Result, nil]
          def step_result(name)
            @step_results[name]
          end

          # Returns all step results
          #
          # @return [Hash<Symbol, Result>]
          attr_reader :step_results

          # Provides dynamic access to step results
          #
          # Allows accessing step results as methods:
          #   validate.content  # Returns the :validate step result's content
          #
          def method_missing(name, *args, &block)
            if @step_results&.key?(name)
              result = @step_results[name]
              # Return a proxy that allows accessing content
              StepResultProxy.new(result)
            else
              super
            end
          end

          def respond_to_missing?(name, include_private = false)
            @step_results&.key?(name) || super
          end

          protected

          # Executes lifecycle hooks
          #
          # @param hook_name [Symbol] Hook type
          # @param step_name [Symbol, nil] Current step name
          # @param args [Array] Arguments to pass to hooks
          def run_hooks(hook_name, step_name = nil, *args)
            hooks = self.class.lifecycle_hooks[hook_name] || []

            hooks.each do |hook|
              # Skip if hook is for a specific step and this isn't it
              next if hook[:step] && hook[:step] != step_name

              if hook[:method]
                send(hook[:method], *args)
              elsif hook[:block]
                instance_exec(*args, &hook[:block])
              end
            end
          end
        end

        # Proxy for accessing step results
        #
        # Provides convenient access to step result content and methods.
        #
        # @api private
        class StepResultProxy
          def initialize(result)
            @result = result
          end

          # Delegate content access
          def content
            @result&.content
          end

          # Allow hash-like access to content
          def [](key)
            content&.[](key)
          end

          # Allow method access to content hash keys
          def method_missing(name, *args, &block)
            if @result.respond_to?(name)
              @result.send(name, *args, &block)
            elsif content.is_a?(Hash) && content.key?(name)
              content[name]
            elsif content.is_a?(Hash) && content.key?(name.to_s)
              content[name.to_s]
            else
              super
            end
          end

          def respond_to_missing?(name, include_private = false)
            @result.respond_to?(name) ||
              (content.is_a?(Hash) && (content.key?(name) || content.key?(name.to_s))) ||
              super
          end

          def to_h
            content.is_a?(Hash) ? content : { value: content }
          end
        end
      end
    end
  end
end
