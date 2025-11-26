# frozen_string_literal: true

module RubyLLM
  module Agents
    module Filterable
      extend ActiveSupport::Concern

      VALID_STATUSES = %w[running success error timeout].freeze

      private

      def parse_array_param(key)
        value = params[key]
        return [] if value.blank?

        (value.is_a?(Array) ? value : value.to_s.split(",")).select(&:present?)
      end

      def parse_days_param
        return nil unless params[:days].present?

        days = params[:days].to_i
        days.positive? ? days : nil
      end

      def validate_statuses(statuses)
        statuses.select { |s| VALID_STATUSES.include?(s) }
      end

      def apply_status_filter(scope, statuses)
        valid_statuses = validate_statuses(statuses)
        valid_statuses.any? ? scope.where(status: valid_statuses) : scope
      end

      def apply_time_filter(scope, days)
        days.present? && days.positive? ? scope.where("created_at >= ?", days.days.ago) : scope
      end
    end
  end
end
