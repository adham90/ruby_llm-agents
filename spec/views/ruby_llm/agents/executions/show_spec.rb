# frozen_string_literal: true

require "rails_helper"

RSpec.describe "ruby_llm/agents/executions/show", type: :view do
  # Include the application helper module for view rendering
  helper RubyLLM::Agents::ApplicationHelper

  let(:execution) { create(:execution) }

  before do
    assign(:execution, execution)

    # Set up engine routes for the view
    without_partial_double_verification do
      allow(view).to receive(:rerun_execution_path).and_return("/executions/1/rerun")
      allow(view).to receive(:execution_path).and_return("/executions/1")
      allow(view).to receive(:executions_path).and_return("/executions")
    end

    # Stub controller context for documentation_url helper
    allow(view).to receive(:controller_name).and_return("executions")
    allow(view).to receive(:action_name).and_return("show")
  end

  describe "tool calls section" do
    context "when execution has no tool calls" do
      let(:execution) { create(:execution, tool_calls: [], tool_calls_count: 0) }

      it "shows 'No tool calls' message" do
        render

        expect(rendered).to include("No tool calls")
      end

      it "shows count badge with 0" do
        render

        # The badge is immediately after "Tool Calls" h3, with classes including "rounded-full"
        expect(rendered).to match(/>Tool Calls<\/h3>\s*<span[^>]*rounded-full[^>]*>\s*0\s*<\/span>/m)
      end
    end

    context "when execution has 1-3 tool calls (auto-expanded)" do
      let(:execution) { create(:execution, :with_tool_calls) }

      it "shows tool names" do
        render

        expect(rendered).to include("search_database")
        expect(rendered).to include("format_response")
      end

      it "shows tool IDs" do
        render

        expect(rendered).to include("call_abc123")
        expect(rendered).to include("call_def456")
      end

      it "shows tool arguments" do
        render

        expect(rendered).to include("query")
        expect(rendered).to include("test")
      end

      it "initializes with expanded: true" do
        render

        expect(rendered).to include("expanded: true")
      end

      it "has x-cloak attribute" do
        render

        expect(rendered).to match(/x-show="expanded"\s+x-cloak/)
      end

      it "shows count badge with 2 for correct tool count" do
        render

        # Verify the tool calls count badge shows the correct count
        expect(rendered).to match(/>Tool Calls<\/h3>\s*<span[^>]*rounded-full[^>]*>\s*2\s*<\/span>/m)
      end
    end

    context "when execution has 4+ tool calls (collapsed by default)" do
      let(:execution) { create(:execution, :with_many_tool_calls) }

      it "initializes with expanded: false" do
        render

        expect(rendered).to include("expanded: false")
      end

      it "shows Expand button" do
        render

        expect(rendered).to include('x-text="expanded ? \'Collapse\' : \'Expand\'"')
      end

      it "has x-cloak attribute" do
        render

        expect(rendered).to match(/x-show="expanded"\s+x-cloak/)
      end

      it "shows count badge with correct number" do
        render

        # The badge is immediately after "Tool Calls" h3
        expect(rendered).to match(/>Tool Calls<\/h3>\s*<span[^>]*rounded-full[^>]*>\s*5\s*<\/span>/m)
      end
    end

    context "when tool call has empty arguments" do
      let(:execution) { create(:execution, :with_tool_calls_no_args) }

      it "shows 'No arguments' message" do
        render

        expect(rendered).to include("No arguments")
      end
    end

    context "when tool calls have symbol keys" do
      let(:execution) { create(:execution, :with_symbol_key_tool_calls) }

      it "renders tool name correctly" do
        render

        expect(rendered).to include("symbol_tool")
      end

      it "renders tool ID correctly" do
        render

        expect(rendered).to include("call_sym_123")
      end

      it "renders arguments correctly" do
        render

        expect(rendered).to include("key")
        expect(rendered).to include("value")
      end
    end

    context "with single tool call" do
      let(:execution) { create(:execution, :with_single_tool_call) }

      it "shows the tool call" do
        render

        expect(rendered).to include("single_tool")
      end

      it "shows count badge with 1" do
        render

        # The badge is immediately after "Tool Calls" h3
        expect(rendered).to match(/>Tool Calls<\/h3>\s*<span[^>]*rounded-full[^>]*>\s*1\s*<\/span>/m)
      end

      it "initializes with expanded: true" do
        render

        expect(rendered).to include("expanded: true")
      end
    end
  end
end
