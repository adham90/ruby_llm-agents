# frozen_string_literal: true

module RubyLLM
  module Agents
    # Controller concern for pagination
    #
    # Provides simple offset-based pagination with consistent return format.
    #
    # @example Using in a controller
    #   stats = scope.totals
    #   result = paginate(scope, total_count: stats[:total_count])
    #   @executions = result[:records]
    #   @pagination = result[:pagination]
    #
    # @api private
    module Paginatable
      extend ActiveSupport::Concern

      private

      # Paginates a scope with optional ordering
      #
      # Counting every row a filter matches is the expensive half of
      # pagination on a large table, so the count is the caller's to supply
      # (usually from an aggregate it needed anyway). Without one the page is
      # still served: one extra row is fetched to learn whether a next page
      # exists, and the view falls back to prev/next links.
      #
      # @param scope [ActiveRecord::Relation] The scope to paginate
      # @param ordered [Boolean] Whether to apply default descending order (default: true)
      # @param sort_params [Hash, nil] Optional custom sort parameters with :column and :direction
      # @param total_count [Integer, nil] Total rows in the scope, when known
      # @return [Hash] Contains :records and :pagination keys
      # @option return [Array, ActiveRecord::Relation] :records The loaded page
      # @option return [Hash] :pagination Pagination metadata
      #   - :current_page [Integer] Current page number
      #   - :per_page [Integer] Records per page
      #   - :total_count [Integer, nil] Total record count, nil when unknown
      #   - :total_pages [Integer, nil] Total page count, nil when unknown
      #   - :next_page [Boolean] Whether a later page exists
      def paginate(scope, ordered: true, sort_params: nil, total_count: nil)
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

        # Loaded eagerly: the views call `records.empty?` before iterating,
        # which on an unloaded relation costs a second SELECT.
        if total_count
          records = scope.offset(offset).limit(per_page).load
          total_pages = (total_count.to_f / per_page).ceil
          next_page = page < total_pages
        else
          records = scope.offset(offset).limit(per_page + 1).to_a
          next_page = records.size > per_page
          records = records.first(per_page)
        end

        {
          records: records,
          pagination: {
            current_page: page,
            per_page: per_page,
            total_count: total_count,
            total_pages: total_pages,
            next_page: next_page
          }
        }
      end
    end
  end
end
