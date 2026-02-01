# frozen_string_literal: true

# NodeProcessorAgent - Processes nodes in a tree structure
#
# Used in recursive tree processing workflows to handle individual
# nodes and identify children for further processing.
#
# Example usage:
#   result = NodeProcessorAgent.call(
#     node: { id: "1", name: "Root", value: 100 },
#     depth: 0
#   )
#
class NodeProcessorAgent < ApplicationAgent
  description 'Processes tree nodes and identifies children'
  model 'gpt-4o-mini'
  temperature 0.0

  param :node, required: true
  param :depth, default: 0

  def system_prompt
    <<~PROMPT
      You are a tree node processor. Given a node in a tree structure,
      process it and identify any children that need further processing.

      Return a JSON object with:
      - node_id: the node identifier
      - processed_value: the computed/processed value for this node
      - children: array of child nodes (each with id, name, value)
      - is_leaf: boolean indicating if this is a leaf node
      - depth: current depth in the tree
      - metadata: processing metadata
    PROMPT
  end

  def user_prompt
    <<~PROMPT
      Process tree node at depth #{depth}:

      Node: #{node.to_json}
    PROMPT
  end

  def schema
    {
      type: 'object',
      properties: {
        node_id: { type: 'string' },
        processed_value: { type: 'number' },
        children: {
          type: 'array',
          items: {
            type: 'object',
            properties: {
              id: { type: 'string' },
              name: { type: 'string' },
              value: { type: 'number' }
            }
          }
        },
        is_leaf: { type: 'boolean' },
        depth: { type: 'integer' },
        metadata: { type: 'object' }
      },
      required: %w[node_id processed_value children is_leaf depth]
    }
  end
end
