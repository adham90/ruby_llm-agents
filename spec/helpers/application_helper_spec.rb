# frozen_string_literal: true

require "rails_helper"

RSpec.describe RubyLLM::Agents::ApplicationHelper, type: :helper do
  describe "#highlight_json" do
    it "returns highlighted HTML for valid JSON" do
      json = { "key" => "value" }
      result = helper.highlight_json(json)
      expect(result).to include("key")
      expect(result).to include("value")
    end

    it "handles nested JSON" do
      json = { "outer" => { "inner" => "value" } }
      result = helper.highlight_json(json)
      expect(result).to include("outer")
      expect(result).to include("inner")
    end

    it "handles arrays" do
      json = { "items" => [1, 2, 3] }
      result = helper.highlight_json(json)
      expect(result).to include("items")
    end

    it "handles nil values" do
      json = { "key" => nil }
      result = helper.highlight_json(json)
      expect(result).to include("null")
    end

    it "handles boolean values" do
      json = { "flag" => true, "other" => false }
      result = helper.highlight_json(json)
      expect(result).to include("true")
      expect(result).to include("false")
    end

    it "escapes HTML in string values" do
      json = { "key" => "<script>alert('xss')</script>" }
      result = helper.highlight_json(json)
      expect(result).not_to include("<script>")
      expect(result).to include("&lt;script&gt;")
    end

    it "returns html_safe string" do
      json = { "key" => "value" }
      result = helper.highlight_json(json)
      expect(result).to be_html_safe
    end

    context "with nil input" do
      it "returns empty pre tag" do
        result = helper.highlight_json(nil)
        expect(result).to eq("<pre></pre>")
      end
    end

    context "with empty hash" do
      it "returns formatted empty object" do
        result = helper.highlight_json({})
        expect(result).to include("{}")
      end
    end
  end
end
