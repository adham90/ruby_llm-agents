# frozen_string_literal: true

module RubyLLM
  module Agents
    module Paginatable
      extend ActiveSupport::Concern

      private

      def paginate(scope, ordered: true)
        page = [(params[:page] || 1).to_i, 1].max
        per_page = RubyLLM::Agents.configuration.per_page
        offset = (page - 1) * per_page

        scope = scope.order(created_at: :desc) if ordered
        total_count = scope.count

        {
          records: scope.offset(offset).limit(per_page),
          pagination: {
            current_page: page,
            per_page: per_page,
            total_count: total_count,
            total_pages: (total_count.to_f / per_page).ceil
          }
        }
      end
    end
  end
end
