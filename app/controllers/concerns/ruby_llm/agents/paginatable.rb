# frozen_string_literal: true

module RubyLLM
  module Agents
    # Controller concern for pagination
    #
    # Provides simple offset-based pagination with consistent return format.
    #
    # @example Using in a controller
    #   result = paginate(Execution.all)
    #   @executions = result[:records]
    #   @pagination = result[:pagination]
    #
    # @api private
    module Paginatable
      extend ActiveSupport::Concern

      private

      # Paginates a scope with optional ordering
      #
      # @param scope [ActiveRecord::Relation] The scope to paginate
      # @param ordered [Boolean] Whether to apply default descending order (default: true)
      # @param sort_params [Hash, nil] Optional custom sort parameters with :column and :direction
      # @return [Hash] Contains :records and :pagination keys
      # @option return [ActiveRecord::Relation] :records Paginated records
      # @option return [Hash] :pagination Pagination metadata
      #   - :current_page [Integer] Current page number
      #   - :per_page [Integer] Records per page
      #   - :total_count [Integer] Total record count
      #   - :total_pages [Integer] Total page count
      def paginate(scope, ordered: true, sort_params: nil)
        page = [(params[:page] || 1).to_i, 1].max
        per_page = RubyLLM::Agents.configuration.per_page
        offset = (page - 1) * per_page

        # Apply sorting - use custom sort_params if provided, otherwise default
        table_name = scope.model.table_name
        if sort_params.present?
          scope = scope.order("#{table_name}.#{sort_params[:column]} #{sort_params[:direction].upcase}")
        elsif ordered
          scope = scope.order("#{table_name}.created_at DESC")
        end
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
