# frozen_string_literal: true

module RubyLLM
  module Agents
    # Controller concern for parsing and applying filters
    #
    # Provides methods for parsing filter parameters from requests
    # and applying them to ActiveRecord scopes.
    #
    # @example Including in a controller
    #   class ExecutionsController < ApplicationController
    #     include Filterable
    #
    #     def index
    #       statuses = parse_array_param(:statuses)
    #       @scope = apply_status_filter(Execution.all, statuses)
    #     end
    #   end
    #
    # @api private
    module Filterable
      extend ActiveSupport::Concern

      # Valid status values for filtering
      VALID_STATUSES = %w[running success error timeout].freeze

      private

      # Parses an array parameter from the request
      #
      # Handles both array format (?key[]=a&key[]=b) and
      # comma-separated format (?key=a,b).
      #
      # @param key [Symbol] The parameter key
      # @return [Array<String>] Parsed values (empty if blank)
      def parse_array_param(key)
        value = params[key]
        return [] if value.blank?

        (value.is_a?(Array) ? value : value.to_s.split(",")).select(&:present?)
      end

      # Parses the days parameter for time filtering
      #
      # @return [Integer, nil] Number of days or nil if invalid/missing
      def parse_days_param
        return nil unless params[:days].present?

        days = params[:days].to_i
        days.positive? ? days : nil
      end

      # Filters status values to only valid ones
      #
      # @param statuses [Array<String>] Status values to validate
      # @return [Array<String>] Valid status values only
      def validate_statuses(statuses)
        statuses.select { |s| VALID_STATUSES.include?(s) }
      end

      # Applies status filter to a scope
      #
      # @param scope [ActiveRecord::Relation] The base scope
      # @param statuses [Array<String>] Status values to filter by
      # @return [ActiveRecord::Relation] Filtered scope
      def apply_status_filter(scope, statuses)
        valid_statuses = validate_statuses(statuses)
        valid_statuses.any? ? scope.where(status: valid_statuses) : scope
      end

      # Applies time filter to a scope
      #
      # @param scope [ActiveRecord::Relation] The base scope
      # @param days [Integer, nil] Number of days to filter by
      # @return [ActiveRecord::Relation] Filtered scope
      def apply_time_filter(scope, days)
        return scope unless days.present? && days.positive?

        # Qualify column name to avoid ambiguity when joins are present
        table_name = scope.model.table_name
        scope.where("#{table_name}.created_at >= ?", days.days.ago)
      end
    end
  end
end
