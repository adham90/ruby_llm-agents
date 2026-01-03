# frozen_string_literal: true

# Example Pipeline Workflow
# Processes content through sequential steps: extract -> classify -> format
#
# Usage:
#   result = ContentPipeline.call(text: "Your content here")
#   result.steps[:extract].content   # Extracted data
#   result.steps[:classify].content  # Classification result
#   result.total_cost                # Total cost of all steps
#
class ContentPipeline < RubyLLM::Agents::Workflow::Pipeline
  version "1.0"
  timeout 60.seconds
  max_cost 1.00

  step :extract,  agent: ExtractorAgent
  step :classify, agent: ClassifierAgent
  step :format,   agent: FormatterAgent, optional: true

  # Transform input for the classify step
  def before_classify(context)
    { text: context[:extract].content.to_s }
  end

  # Transform input for the format step
  def before_format(context)
    {
      text: context[:extract].content.to_s,
      category: context[:classify].content
    }
  end
end
