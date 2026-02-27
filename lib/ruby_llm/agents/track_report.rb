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

      def call_count
        @results.size
      end

      def total_cost
        @results.sum { |r| r.total_cost || 0 }
      end

      def input_cost
        @results.sum { |r| r.input_cost || 0 }
      end

      def output_cost
        @results.sum { |r| r.output_cost || 0 }
      end

      def total_tokens
        @results.sum { |r| r.total_tokens }
      end

      def input_tokens
        @results.sum { |r| r.input_tokens || 0 }
      end

      def output_tokens
        @results.sum { |r| r.output_tokens || 0 }
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
            cost: r.total_cost || 0,
            tokens: r.total_tokens,
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
          total_cost: total_cost,
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
    end
  end
end
