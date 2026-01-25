# frozen_string_literal: true

# TreeProcessorWorkflow - Demonstrates Recursion Support
#
# This workflow shows how to create self-referential workflows
# that can call themselves, demonstrating:
#   - Self-referential workflow calls
#   - `max_recursion_depth` setting
#   - Termination conditions with `if:`
#   - Recursive result aggregation
#
# Usage:
#   result = TreeProcessorWorkflow.call(
#     node: {
#       id: "root",
#       name: "Root Node",
#       value: 100
#     }
#   )
#
#   # Results include aggregated values from all processed nodes
#   result.content[:total_value]  # Sum of all node values
#   result.content[:node_count]   # Total nodes processed
#
class TreeProcessorWorkflow < RubyLLM::Agents::Workflow
  description "Recursively processes tree structures"
  version "1.0"
  timeout 2.minutes
  max_cost 0.50

  # Set maximum recursion depth to prevent infinite loops
  max_recursion_depth 5

  input do
    required :node, Hash
    optional :depth, Integer, default: 0
  end

  # Process the current node
  step :process_node, NodeProcessorAgent,
       desc: "Process the current tree node",
       input: -> {
         {
           node: input.node,
           depth: input.depth
         }
       }

  # Recursively process children using this same workflow
  # This creates self-referential workflow execution
  step :process_children, TreeProcessorWorkflow,
       desc: "Recursively process child nodes",
       each: -> { process_node.children || [] },
       if: -> { (process_node.children || []).any? },
       continue_on_error: true,
       input: -> {
         {
           node: item,
           depth: input.depth + 1
         }
       }

  # Aggregate results from this node and all children
  step :aggregate do
    node_value = process_node.processed_value || 0
    children_results = process_children&.content || []

    # Sum values from children (each child result contains aggregated subtree values)
    children_total = children_results.sum do |child_result|
      if child_result.is_a?(Hash)
        child_result[:total_value] || child_result["total_value"] || 0
      else
        0
      end
    end

    children_count = children_results.sum do |child_result|
      if child_result.is_a?(Hash)
        child_result[:node_count] || child_result["node_count"] || 1
      else
        1
      end
    end

    {
      node_id: process_node.node_id,
      node_value: node_value,
      is_leaf: process_node.is_leaf,
      depth: input.depth,
      children_processed: children_results.size,
      total_value: node_value + children_total,
      node_count: 1 + children_count,
      processed_at: Time.current.iso8601
    }
  end
end
