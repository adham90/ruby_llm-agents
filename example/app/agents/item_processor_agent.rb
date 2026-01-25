# frozen_string_literal: true

# ItemProcessorAgent - Processes individual items in a batch
#
# Used in batch processing workflows to handle individual items
# with validation, transformation, and enrichment.
#
# Example usage:
#   result = ItemProcessorAgent.call(
#     item: { id: "123", name: "Widget", price: 29.99 },
#     index: 0,
#     operation: "validate"
#   )
#
class ItemProcessorAgent < ApplicationAgent
  description "Processes individual items with validation and transformation"
  model "gpt-4o-mini"
  temperature 0.0

  param :item, required: true
  param :index, default: 0
  param :operation, default: "process"

  def system_prompt
    <<~PROMPT
      You are an item processor. Given an item and operation type,
      perform the requested processing and return the result.

      Operations:
      - validate: Check item data validity
      - transform: Normalize and clean item data
      - enrich: Add computed fields and metadata
      - process: Full processing (all operations)

      Return a JSON object with:
      - item_id: the item identifier
      - operation: operation performed
      - success: boolean indicating success
      - processed_item: the processed item data
      - errors: array of any validation errors (empty if none)
      - metadata: processing metadata
    PROMPT
  end

  def user_prompt
    <<~PROMPT
      Process item ##{index}:

      Operation: #{operation}
      Item: #{item.to_json}
    PROMPT
  end

  def schema
    {
      type: "object",
      properties: {
        item_id: { type: "string" },
        operation: { type: "string" },
        success: { type: "boolean" },
        processed_item: { type: "object" },
        errors: { type: "array", items: { type: "string" } },
        metadata: {
          type: "object",
          properties: {
            processed_at: { type: "string" },
            processing_time_ms: { type: "integer" }
          }
        }
      },
      required: %w[item_id operation success processed_item errors]
    }
  end
end
