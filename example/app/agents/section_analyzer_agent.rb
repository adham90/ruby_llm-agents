# frozen_string_literal: true

# SectionAnalyzerAgent - Analyzes document sections
#
# Used in document pipeline workflows to analyze individual
# sections of a document for content, structure, and insights.
#
# Example usage:
#   result = SectionAnalyzerAgent.call(
#     section: { title: "Introduction", content: "..." },
#     document_context: { type: "report", total_sections: 5 }
#   )
#
class SectionAnalyzerAgent < ApplicationAgent
  description 'Analyzes document sections for content and structure'
  model 'gpt-4o-mini'
  temperature 0.3

  param :section, required: true
  param :document_context, default: {}

  def system_prompt
    <<~PROMPT
      You are a document section analyzer. Given a section of a document,
      analyze its content, structure, and extract key insights.

      Return a JSON object with:
      - section_id: identifier for the section
      - title: section title
      - summary: brief summary of the section
      - key_points: array of key points
      - word_count: number of words
      - sentiment: overall sentiment (positive, negative, neutral)
      - topics: array of main topics discussed
      - entities: array of named entities found
      - readability_score: score from 0-100
      - recommendations: array of improvement suggestions
    PROMPT
  end

  def user_prompt
    section_content = section.is_a?(Hash) ? section : { content: section }

    <<~PROMPT
      Analyze document section:

      Title: #{section_content[:title] || 'Untitled'}
      Content: #{section_content[:content] || section_content.to_s}

      Document Context: #{document_context.to_json}
    PROMPT
  end

  def schema
    {
      type: 'object',
      properties: {
        section_id: { type: 'string' },
        title: { type: 'string' },
        summary: { type: 'string' },
        key_points: { type: 'array', items: { type: 'string' } },
        word_count: { type: 'integer' },
        sentiment: { type: 'string', enum: %w[positive negative neutral] },
        topics: { type: 'array', items: { type: 'string' } },
        entities: { type: 'array', items: { type: 'string' } },
        readability_score: { type: 'integer' },
        recommendations: { type: 'array', items: { type: 'string' } }
      },
      required: %w[section_id title summary key_points word_count sentiment]
    }
  end
end
