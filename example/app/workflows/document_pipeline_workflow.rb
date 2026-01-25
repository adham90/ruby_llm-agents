# frozen_string_literal: true

# DocumentPipelineWorkflow - Demonstrates Combined Patterns
#
# This workflow shows how to combine iteration with sub-workflows,
# demonstrating:
#   - Iteration + sub-workflows combined
#   - Processing document sections in parallel
#   - Each section triggers a sub-workflow
#   - All advanced features working together
#
# Usage:
#   result = DocumentPipelineWorkflow.call(
#     document: {
#       title: "Annual Report",
#       type: "report",
#       sections: [
#         { title: "Executive Summary", content: "..." },
#         { title: "Financial Overview", content: "..." },
#         { title: "Future Outlook", content: "..." }
#       ]
#     }
#   )
#
#   # Access combined results
#   result.content[:document_summary]
#   result.content[:section_analyses]
#
class DocumentPipelineWorkflow < RubyLLM::Agents::Workflow
  description "Processes documents with sections using combined patterns"
  version "1.0"
  timeout 5.minutes
  max_cost 1.00

  input do
    required :document, Hash
    optional :parallel_analysis, :boolean, default: true
    optional :analysis_depth, String, default: "standard"
  end

  # Validate document structure
  step :validate, ValidatorAgent,
       desc: "Validate document structure",
       input: -> {
         {
           data: {
             title: input.document[:title],
             type: input.document[:type],
             section_count: (input.document[:sections] || []).size
           }
         }
       }

  # Extract document metadata
  step :extract_metadata do
    sections = input.document[:sections] || []

    {
      title: input.document[:title],
      type: input.document[:type] || "unknown",
      section_count: sections.size,
      total_word_count: sections.sum { |s| (s[:content] || "").split.size },
      section_titles: sections.map { |s| s[:title] }
    }
  end

  # Analyze each section in parallel using an agent
  # Demonstrates iteration with parallel execution
  step :analyze_sections, SectionAnalyzerAgent,
       desc: "Analyze document sections in parallel",
       each: -> { input.document[:sections] || [] },
       concurrency: 3,
       continue_on_error: true,
       if: -> { input.parallel_analysis },
       input: -> {
         {
           section: item,
           document_context: {
             type: input.document[:type],
             total_sections: (input.document[:sections] || []).size,
             analysis_depth: input.analysis_depth
           }
         }
       }

  # Sequential analysis fallback
  step :analyze_sections_sequential, SectionAnalyzerAgent,
       desc: "Analyze document sections sequentially",
       each: -> { input.document[:sections] || [] },
       continue_on_error: true,
       unless: -> { input.parallel_analysis },
       input: -> {
         {
           section: item,
           document_context: {
             type: input.document[:type],
             total_sections: (input.document[:sections] || []).size,
             analysis_depth: input.analysis_depth
           }
         }
       }

  # Aggregate section analyses
  step :aggregate_analyses do
    analyses = if input.parallel_analysis
                 analyze_sections&.content || []
               else
                 analyze_sections_sequential&.content || []
               end

    # Compute aggregate metrics
    sentiments = analyses.map { |a| a[:sentiment] || a["sentiment"] }.compact
    sentiment_counts = sentiments.tally

    topics = analyses.flat_map { |a| a[:topics] || a["topics"] || [] }.tally
    top_topics = topics.sort_by { |_, count| -count }.first(5).to_h

    total_word_count = analyses.sum { |a| a[:word_count] || a["word_count"] || 0 }
    avg_readability = analyses.any? ?
      (analyses.sum { |a| a[:readability_score] || a["readability_score"] || 0 } / analyses.size.to_f).round(1) : 0

    {
      section_count: analyses.size,
      sentiment_distribution: sentiment_counts,
      dominant_sentiment: sentiment_counts.max_by { |_, v| v }&.first || "unknown",
      top_topics: top_topics,
      total_word_count: total_word_count,
      average_readability: avg_readability,
      all_entities: analyses.flat_map { |a| a[:entities] || a["entities"] || [] }.uniq,
      recommendations: analyses.flat_map { |a| a[:recommendations] || a["recommendations"] || [] }.uniq
    }
  end

  # Generate final document summary
  step :generate_summary, SummaryAgent,
       desc: "Generate document summary",
       input: -> {
         {
           text: build_summary_input
         }
       }

  # Compile final results
  step :finalize do
    {
      document_summary: {
        title: extract_metadata[:title],
        type: extract_metadata[:type],
        summary: generate_summary&.content || "Summary unavailable"
      },
      section_analyses: aggregate_analyses.to_h,
      metadata: {
        section_count: extract_metadata[:section_count],
        word_count: extract_metadata[:total_word_count],
        analysis_mode: input.parallel_analysis ? "parallel" : "sequential",
        processed_at: Time.current.iso8601,
        workflow_id: workflow_id
      }
    }
  end

  private

  def build_summary_input
    sections = input.document[:sections] || []
    sections.map { |s| "#{s[:title]}: #{s[:content]}" }.join("\n\n")
  end
end
