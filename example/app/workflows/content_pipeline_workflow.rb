# frozen_string_literal: true

# Example Sequential Workflow using the new DSL
# Processes content through sequential steps: extract -> classify -> format
#
# Usage:
#   result = ContentPipelineWorkflow.call(text: "Your content here")
#   result.steps[:extract].content   # Extracted data
#   result.steps[:classify].content  # Classification result
#   result.steps[:format].content    # Formatted output
#   result.total_cost                # Total cost of all steps
#
class ContentPipelineWorkflow < RubyLLM::Agents::Workflow
  description "Processes content through sequential steps: extraction, classification, and formatting"
  version "1.0"
  timeout 60.seconds
  max_cost 1.00

  input do
    required :text, String
  end

  step :extract, ExtractorAgent
  step :classify, ClassifierAgent
  step :format, FormatterAgent, optional: true
end
