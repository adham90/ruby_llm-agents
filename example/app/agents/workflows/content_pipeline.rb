# frozen_string_literal: true

# ContentPipeline - Sequential pipeline workflow
#
# Demonstrates a sequential workflow where each step runs after the
# previous one completes. Data flows from extract -> classify -> format
# using the `pass` DSL to map outputs to inputs.
#
# This is the simplest workflow pattern — a linear pipeline.
#
# @example Basic usage
#   result = Workflows::ContentPipeline.call(text: "Your content here")
#   result.success?                    # => true
#   result.step(:extract).content      # => { entities: [...], facts: [...] }
#   result.step(:classify).content     # => { category: "technology", ... }
#   result.step(:format).content       # => formatted report
#   result.total_cost                  # => combined cost of all steps
#   result.total_tokens                # => combined tokens of all steps
#
# @example Access final result directly
#   result = Workflows::ContentPipeline.call(text: "Article about AI...")
#   result.content                     # => format step's content (last step)
#   result.duration_ms                 # => total wall-clock time
#
module Workflows
  class ContentPipeline < ApplicationWorkflow
    description "Extract, classify, and format content through a sequential pipeline"

    # Define steps with dependencies
    step :extract, Workflows::ExtractorAgent
    step :classify, Workflows::ClassifierAgent, after: :extract
    step :format, Workflows::FormatterAgent, after: :classify

    # Declare the sequential flow
    flow :extract >> :classify >> :format

    # Map outputs between steps
    pass :extract, to: :classify, as: {entities: :entities, themes: :themes}
    pass :classify, to: :format, as: {category: :category, tags: :tags}
  end
end
