# frozen_string_literal: true

require "rails_helper"

RSpec.describe "ruby_llm/agents/shared/_filter_dropdown", type: :view do
  helper RubyLLM::Agents::ApplicationHelper

  let(:options) do
    [
      {value: "a", label: "Acme"},
      {value: "b", label: "Beta"},
      {value: "c", label: "Gamma"}
    ]
  end

  def render_dropdown(**overrides)
    render partial: "ruby_llm/agents/shared/filter_dropdown", locals: {
      name: "tenant_ids[]",
      filter_id: "tenant_ids",
      label: "Tenants",
      all_label: "All Tenants",
      options: options,
      selected: []
    }.merge(overrides)
  end

  it "does not render a search input by default" do
    render_dropdown
    expect(rendered).not_to include('placeholder="Search…"')
    expect(rendered).not_to include("x-model=\"query\"")
  end

  context "when searchable: true" do
    it "renders a search input" do
      render_dropdown(searchable: true)
      expect(rendered).to include('placeholder="Search…"')
      expect(rendered).to include("x-model=\"query\"")
    end

    it "adds an x-show filter to each option" do
      render_dropdown(searchable: true)
      expect(rendered).to include("'acme'.includes(query.toLowerCase())")
      expect(rendered).to include("'beta'.includes(query.toLowerCase())")
    end
  end

  it "renders each option's label and value" do
    render_dropdown
    expect(rendered).to include('value="a"')
    expect(rendered).to include("Acme")
    expect(rendered).to include("Gamma")
  end

  it "marks selected options as checked" do
    render_dropdown(selected: ["b"])
    expect(rendered).to match(/value="b"[^>]*checked/m)
    expect(rendered).not_to match(/value="a"[^>]*checked/m)
  end

  describe "checkbox vs label click behavior" do
    it "option checkbox @change only marks dirty (no requestSubmit)" do
      render_dropdown
      expect(rendered).to include('@change="dirty = true"')
    end

    it "'All' checkbox @change marks dirty without requestSubmit" do
      render_dropdown
      # The "All" checkbox handler clears other checkboxes then marks dirty
      expect(rendered).to match(/@change="\s*\$el\.closest\('\[data-filter\]'\)\.querySelectorAll\('\.filter-cb'\)\.forEach[^"]+dirty = true;\s*"/m)
    end

    it "no checkbox handler triggers requestSubmit directly" do
      render_dropdown
      change_handlers = rendered.scan(/@change="[^"]*"/m)
      expect(change_handlers).not_to be_empty
      change_handlers.each do |handler|
        expect(handler).not_to include("requestSubmit"), "checkbox @change should not submit: #{handler}"
      end
    end

    it "submits immediately on label click (single-select + close)" do
      render_dropdown
      label_click_block = rendered[/@click\.prevent="[^"]+"/m]
      expect(label_click_block).to include("open = false")
      expect(label_click_block).to include("requestSubmit")
    end

    it "applies pending changes when the dropdown is closed via outside click" do
      render_dropdown
      expect(rendered).to include('@click.outside="closeAndApply()"')
    end

    it "closes and applies on Escape" do
      render_dropdown
      expect(rendered).to include('@keydown.escape.window="if (open) closeAndApply()"')
    end

    it "defines closeAndApply() that submits only when dirty" do
      render_dropdown
      expect(rendered).to include("closeAndApply()")
      expect(rendered).to include("if (this.dirty)")
      expect(rendered).to include("this.$el.closest('form').requestSubmit()")
    end
  end
end
