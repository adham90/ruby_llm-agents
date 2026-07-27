# frozen_string_literal: true

module RubyLLM
  module Agents
    # Aggregated read-only report returned by RubyLLM::Agents.track.
    #
    # Provides totals and breakdowns across all agent calls made
    # inside the tracked block.
    #
    # @example
    #   report = RubyLLM::Agents.track do
    #     TranscribeAgent.call(with: audio_path)
    #     ChatAgent.call(message: "hello")
    #   end
    #   report.total_cost   # => 0.0078
    #   report.call_count   # => 2
    #
    # @api public
    class TrackReport
      attr_reader :value, :error, :results, :request_id
      attr_reader :started_at, :completed_at

      def initialize(value:, error:, results:, request_id:, started_at:, completed_at:)
        @value = value
        @error = error
        @results = results.freeze
        @request_id = request_id
        @started_at = started_at
        @completed_at = completed_at
      end

      def successful?
        @error.nil?
      end

      def failed?
        !successful?
      end

      # Every agent call made in the block, including ones served from cache.
      def call_count
        @results.size
      end

      # Calls served from the response cache — no API call, no spend.
      def cached_count
        cached_results.size
      end

      # Calls that actually hit a provider.
      def billable_count
        billable_results.size
      end

      # Costs and token counts cover only the calls that actually hit a
      # provider. A cached result replays the ORIGINAL call's figures, so
      # including them would report spend that was never incurred — the
      # execution records for cache hits are written with zero cost, and these
      # totals reconcile with them.
      def total_cost
        billable_results.sum { |r| r.total_cost || 0 }
      end

      def input_cost
        billable_results.sum { |r| r.input_cost || 0 }
      end

      def output_cost
        billable_results.sum { |r| r.output_cost || 0 }
      end

      def total_tokens
        billable_results.sum { |r| r.total_tokens || 0 }
      end

      def input_tokens
        billable_results.sum { |r| r.input_tokens || 0 }
      end

      def output_tokens
        billable_results.sum { |r| r.output_tokens || 0 }
      end

      # What the cached calls would have cost at the original calls' prices.
      def cache_savings
        cached_results.sum { |r| r.total_cost || 0 }
      end

      # Results that hit a provider (everything except cache replays).
      def billable_results
        @billable_results ||= @results.reject { |r| cached_result?(r) }
      end

      # Results replayed from the response cache.
      def cached_results
        @cached_results ||= @results.select { |r| cached_result?(r) }
      end

      def duration_ms
        return nil unless @started_at && @completed_at
        ((@completed_at - @started_at) * 1000).to_i
      end

      def all_successful?
        @results.all?(&:success?)
      end

      def any_errors?
        @results.any?(&:error?)
      end

      def errors
        @results.select(&:error?)
      end

      def successful
        @results.select(&:success?)
      end

      def models_used
        @results.filter_map(&:chosen_model_id).uniq
      end

      def cost_breakdown
        @results.map do |r|
          {
            agent: r.respond_to?(:agent_class_name) ? r.agent_class_name : nil,
            model: r.chosen_model_id,
            cost: cached_result?(r) ? 0 : (r.total_cost || 0),
            tokens: cached_result?(r) ? 0 : (r.total_tokens || 0),
            cached: cached_result?(r),
            duration_ms: r.duration_ms
          }
        end
      end

      def to_h
        {
          successful: successful?,
          value: value,
          error: error&.message,
          request_id: request_id,
          call_count: call_count,
          cached_count: cached_count,
          billable_count: billable_count,
          total_cost: total_cost,
          cache_savings: cache_savings,
          input_cost: input_cost,
          output_cost: output_cost,
          total_tokens: total_tokens,
          input_tokens: input_tokens,
          output_tokens: output_tokens,
          duration_ms: duration_ms,
          started_at: started_at,
          completed_at: completed_at,
          models_used: models_used,
          cost_breakdown: cost_breakdown
        }
      end

      private

      # Older result types may predate #cached?; treat those as billable.
      def cached_result?(result)
        result.respond_to?(:cached?) && result.cached?
      end
    end
  end
end
