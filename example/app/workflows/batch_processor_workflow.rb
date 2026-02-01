# frozen_string_literal: true

# BatchProcessorWorkflow - Demonstrates Iteration/Loop Support
#
# This workflow shows how to process collections using the `each:` option,
# demonstrating:
#   - Sequential iteration with `each:`
#   - Parallel iteration with `concurrency:`
#   - `fail_fast:` behavior
#   - `continue_on_error:` behavior
#   - Agent-based iteration
#   - Block-based iteration
#
# Usage:
#   result = BatchProcessorWorkflow.call(
#     items: [
#       { id: "1", name: "Item 1", price: 10 },
#       { id: "2", name: "Item 2", price: 20 },
#       { id: "3", name: "Item 3", price: 30 }
#     ],
#     operation: "validate",
#     batch_size: 5
#   )
#
#   # Access iteration results
#   result.steps[:process_items].content          # Array of processed items
#   result.steps[:process_items].successful_count # Count of successful items
#   result.steps[:process_items].failed_count     # Count of failed items
#
class BatchProcessorWorkflow < RubyLLM::Agents::Workflow
  description 'Processes batches of items with iteration support'
  version '1.0'
  timeout 5.minutes
  max_cost 1.00

  input do
    required :items, Array
    optional :operation, String, default: 'process'
    optional :batch_size, Integer, default: 10
    optional :parallel, :boolean, default: true
  end

  # Validate the batch input
  step :validate_batch do
    skip!(reason: 'No items to process', default: { valid: true, count: 0 }) if input.items.empty?

    {
      valid: true,
      count: input.items.size,
      operation: input.operation
    }
  end

  # Sequential iteration example with agent
  # Each item is processed one at a time
  step :process_items_sequential, ItemProcessorAgent,
       desc: 'Process items sequentially',
       each: -> { input.items },
       continue_on_error: true,
       if: -> { !input.parallel },
       input: lambda {
         {
           item: item,
           index: index,
           operation: input.operation
         }
       }

  # Parallel iteration example with agent
  # Items are processed concurrently with configurable concurrency
  step :process_items, ItemProcessorAgent,
       desc: 'Process items in parallel',
       each: -> { input.items },
       concurrency: 5,
       fail_fast: false,
       continue_on_error: true,
       if: -> { input.parallel },
       input: lambda {
         {
           item: item,
           index: index,
           operation: input.operation
         }
       }

  # Block-based iteration example
  # Demonstrates custom processing logic per item
  step :enrich_items,
       desc: 'Enrich processed items with metadata',
       each: -> { select_processed_items } do |item|
    # Access the current item being processed
    processed = item.is_a?(Hash) ? item : item.content

    {
      original_id: processed[:item_id] || processed['item_id'],
      enriched: true,
      processed_at: Time.current.iso8601,
      batch_id: workflow_id
    }
  end

  # Aggregate results
  step :aggregate do
    processed = input.parallel ? process_items : process_items_sequential

    successful = processed&.successful_count || 0
    failed = processed&.failed_count || 0

    {
      batch_summary: {
        total_items: input.items.size,
        successful: successful,
        failed: failed,
        success_rate: input.items.size.positive? ? (successful.to_f / input.items.size * 100).round(2) : 0
      },
      enriched_count: enrich_items&.content&.size || 0,
      operation: input.operation,
      parallel_mode: input.parallel,
      completed_at: Time.current.iso8601
    }
  end

  private

  # Helper method to select successfully processed items
  def select_processed_items
    result = input.parallel ? step_result(:process_items) : step_result(:process_items_sequential)
    return [] unless result.respond_to?(:item_results)

    result.item_results.select do |r|
      !r.respond_to?(:error?) || !r.error?
    end.map(&:content)
  end
end
