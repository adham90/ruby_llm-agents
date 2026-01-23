# frozen_string_literal: true

module RubyLLM
  module Agents
    # Controller concern for sorting
    #
    # Provides secure column sorting with whitelisted columns and direction validation.
    # Prevents SQL injection by only allowing predefined sort columns.
    #
    # @example Using in a controller
    #   include Sortable
    #   @sort_params = parse_sort_params
    #   result = paginate(scope, sort_params: @sort_params)
    #
    # @api private
    module Sortable
      extend ActiveSupport::Concern

      # Whitelist of allowed sort columns mapped to their database column names
      # Keys are the URL parameter values, values are the actual column names
      SORTABLE_COLUMNS = {
        "agent_type" => "agent_type",
        "status" => "status",
        "agent_version" => "agent_version",
        "total_tokens" => "total_tokens",
        "total_cost" => "total_cost",
        "duration_ms" => "duration_ms",
        "created_at" => "created_at"
      }.freeze

      SORT_DIRECTIONS = %w[asc desc].freeze
      DEFAULT_SORT_COLUMN = "created_at"
      DEFAULT_SORT_DIRECTION = "desc"

      private

      # Parses and validates sort parameters from the request
      #
      # Returns validated sort column and direction, falling back to defaults
      # if invalid values are provided. This prevents SQL injection by only
      # allowing whitelisted column names.
      #
      # @return [Hash] Contains :column and :direction keys
      # @option return [String] :column The validated database column name
      # @option return [String] :direction Either 'asc' or 'desc'
      def parse_sort_params
        column = params[:sort].to_s
        direction = params[:direction].to_s.downcase

        {
          column: SORTABLE_COLUMNS[column] || DEFAULT_SORT_COLUMN,
          direction: SORT_DIRECTIONS.include?(direction) ? direction : DEFAULT_SORT_DIRECTION
        }
      end
    end
  end
end
