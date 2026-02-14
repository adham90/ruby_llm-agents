# frozen_string_literal: true

require_relative "dsl/base"
require_relative "dsl/reliability"
require_relative "dsl/caching"

module RubyLLM
  module Agents
    # Domain-Specific Language modules for agent configuration.
    #
    # The DSL modules provide a clean, declarative way to configure agents
    # at the class level. Each module focuses on a specific concern:
    #
    # - {DSL::Base} - Core settings (model, description, timeout)
    # - {DSL::Reliability} - Retries, fallbacks, circuit breakers
    # - {DSL::Caching} - Response caching configuration
    #
    # @example Using all DSL modules
    #   class MyAgent < RubyLLM::Agents::BaseAgent
    #     extend DSL::Base
    #     extend DSL::Reliability
    #     extend DSL::Caching
    #
    #     model "gpt-4o"
    #     description "A helpful agent"
    #     timeout 30
    #
    #     reliability do
    #       retries max: 3, backoff: :exponential
    #       fallback_models "gpt-4o-mini"
    #       circuit_breaker errors: 5, within: 60
    #     end
    #
    #     cache_for 1.hour
    #   end
    #
    module DSL
    end
  end
end
