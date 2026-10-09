# frozen_string_literal: true

require "rails_helper"

RSpec.describe "ruby_llm/agents/shared/_pagination", type: :view do
  def render_pagination(pagination, shown: nil)
    locals = {pagination: pagination}
    locals[:shown] = shown if shown
    render partial: "ruby_llm/agents/shared/pagination", locals: locals
  end

  # View specs have no route for the page being paginated, so the page links
  # are given somewhere to point.
  before do
    allow(view).to receive(:url_for) { |target| target.is_a?(Hash) ? "/list?page=#{target[:page]}" : target }
  end

  context "when the total is known" do
    let(:pagination) { {current_page: 2, per_page: 25, total_count: 1234, total_pages: 50, next_page: true} }

    it "shows the range out of the total" do
      render_pagination(pagination)

      expect(rendered).to match(/26-50\s+of\s+1,234/)
    end

    it "links numbered pages around the current one, and the last" do
      render_pagination(pagination)

      expect(rendered).to include("/list?page=1", "/list?page=3", "/list?page=4", "/list?page=50")
      expect(rendered).not_to include("/list?page=10")
      expect(rendered).to include('aria-current="page">2<')
    end

    it "clamps the range on the last page and disables next" do
      render_pagination(pagination.merge(current_page: 50, next_page: false))

      expect(rendered).to match(/1226-1234\s+of\s+1,234/)
      expect(rendered).not_to include("/list?page=51")
    end

    it "renders nothing for a single page" do
      render_pagination({current_page: 1, per_page: 25, total_count: 3, total_pages: 1, next_page: false})

      expect(rendered.strip).to be_empty
    end

    it "renders nothing for an empty list" do
      render_pagination({current_page: 1, per_page: 10, total_count: 0, total_pages: 0})

      expect(rendered.strip).to be_empty
    end
  end

  context "when the total is unknown" do
    let(:pagination) { {current_page: 3, per_page: 25, total_count: nil, total_pages: nil, next_page: true} }

    it "shows the range without a total" do
      render_pagination(pagination, shown: 25)

      expect(rendered).to include("51-75")
      expect(rendered).not_to include(" of ")
    end

    it "links only prev and next" do
      render_pagination(pagination, shown: 25)

      expect(rendered).to include("/list?page=2", "/list?page=4")
      expect(rendered).not_to include("/list?page=1\"", "/list?page=5")
      expect(rendered).to include('aria-current="page">3<')
    end

    it "uses the rows actually shown on a short last page" do
      render_pagination(pagination.merge(next_page: false), shown: 7)

      expect(rendered).to include("51-57")
      expect(rendered).not_to include("/list?page=4")
    end

    it "renders nothing when the first page is also the last" do
      render_pagination({current_page: 1, per_page: 25, total_count: nil, total_pages: nil, next_page: false}, shown: 4)

      expect(rendered.strip).to be_empty
    end
  end
end
