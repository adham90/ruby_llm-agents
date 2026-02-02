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
      allow(view).to receive(:execution_path).and_return("/executions/1")
      allow(view).to receive(:executions_path).and_return("/executions")
    end

    # Stub controller context for documentation_url helper
    allow(view).to receive(:controller_name).and_return("executions")
    allow(view).to receive(:action_name).and_return("show")
  end

  describe "tool calls section" do
    context "when execution has no tool calls" do
      let(:execution) { create(:execution, tool_calls_count: 0) }

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

    context "with enhanced tool calls (new format)" do
      let(:execution) { create(:execution, :with_enhanced_tool_calls) }

      it "shows tool name" do
        render

        expect(rendered).to include("weather_lookup")
        expect(rendered).to include("database_query")
      end

      it "shows status badge" do
        render

        # Should show status badge with 'success' - check for the badge with success text
        expect(rendered).to match(/rounded.*text-xs.*font-medium.*>[\s\n]*success[\s\n]*<\/span>/m)
      end

      it "shows duration badge" do
        render

        expect(rendered).to include("245ms")
        expect(rendered).to include("89ms")
      end

      it "shows timestamp" do
        render

        # Should display formatted time from called_at
        expect(rendered).to include("10:30:45")
      end

      it "shows tool result" do
        render

        expect(rendered).to include("Result")
        expect(rendered).to include("15°C, partly cloudy")
      end

      it "shows arguments" do
        render

        expect(rendered).to include("city")
        expect(rendered).to include("Paris")
      end
    end

    context "with enhanced tool call error" do
      let(:execution) { create(:execution, :with_enhanced_tool_call_error) }

      it "shows error status badge" do
        render

        # Should show status badge with 'error' - check for the badge with error text
        expect(rendered).to match(/rounded.*text-xs.*font-medium.*>[\s\n]*error[\s\n]*<\/span>/m)
      end

      it "shows error message section" do
        render

        expect(rendered).to include("Error")
        expect(rendered).to include("ConnectionError")
        expect(rendered).to include("Failed to connect to API")
      end

      it "has error styling" do
        render

        # Should have red-themed error section
        expect(rendered).to match(/border-red-100.*Error/m)
      end
    end

    context "backward compatibility with legacy tool calls" do
      let(:execution) { create(:execution, :with_legacy_tool_calls) }

      it "shows tool name" do
        render

        expect(rendered).to include("old_tool")
      end

      it "shows unknown status for missing status field" do
        render

        # Should show 'unknown' status for legacy tool calls without status
        expect(rendered).to match(/rounded.*text-xs.*font-medium.*>[\s\n]*unknown[\s\n]*<\/span>/m)
      end

      it "does not show duration badge when missing" do
        render

        # Should not crash and should not show ms duration in header for this tool
        # The duration badge would show Xms near the tool name
        expect(rendered).not_to match(/old_tool.*\d+ms\s*<\/span>/m)
      end

      it "does not show result section when result is missing" do
        render

        # The Result section header should not appear after Arguments for old_tool
        # since the legacy format doesn't include result
        expect(rendered).not_to match(/>old_tool<.*>Result</m)
      end

      it "shows arguments correctly" do
        render

        expect(rendered).to include("param")
        expect(rendered).to include("value")
      end
    end
  end
end
