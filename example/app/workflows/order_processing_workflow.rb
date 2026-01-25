# frozen_string_literal: true

# OrderProcessingWorkflow - Demonstrates Sub-workflow Composition
#
# This workflow shows how to call other workflows as steps,
# demonstrating:
#   - Calling workflows as steps with `step :name, SomeWorkflow`
#   - Input transformation for sub-workflows
#   - Budget inheritance (timeout, cost)
#   - Accessing nested step results from sub-workflows
#
# Usage:
#   result = OrderProcessingWorkflow.call(
#     order_id: "ORD-12345",
#     customer: { name: "John Doe", email: "john@example.com" },
#     shipping_address: { city: "San Francisco", state: "CA", zip: "94102" },
#     items: [
#       { sku: "ITEM-001", name: "Widget", quantity: 2, price: 29.99 },
#       { sku: "ITEM-002", name: "Gadget", quantity: 1, price: 49.99 }
#     ]
#   )
#
#   # Access sub-workflow results
#   result.steps[:shipping].content[:shipping][:tracking_number]
#   result.steps[:shipping].steps[:calculate].content
#
class OrderProcessingWorkflow < RubyLLM::Agents::Workflow
  description "Processes orders with sub-workflow composition"
  version "1.0"
  timeout 2.minutes
  max_cost 0.50

  input do
    required :order_id, String
    required :customer, Hash
    required :shipping_address, Hash
    required :items, Array
    optional :priority, String, default: "normal"
  end

  # Validate the order
  step :validate, ValidatorAgent,
       desc: "Validate order data",
       input: -> {
         {
           data: {
             order_id: input.order_id,
             customer: input.customer,
             items: input.items
           }
         }
       }

  # Calculate item totals
  step :calculate_totals do
    subtotal = input.items.sum { |item| item[:quantity] * item[:price] }
    tax = subtotal * 0.0875 # 8.75% tax
    {
      subtotal: subtotal.round(2),
      tax: tax.round(2),
      total: (subtotal + tax).round(2),
      item_count: input.items.sum { |item| item[:quantity] }
    }
  end

  # Execute shipping workflow as a sub-workflow
  # This demonstrates calling another Workflow class as a step
  step :shipping, ShippingWorkflow,
       desc: "Handle shipping calculation and reservation",
       input: -> {
         {
           address: input.shipping_address,
           items: input.items.map do |item|
             { sku: item[:sku], weight: item[:weight] || 1.0 }
           end,
           shipping_speed: input.priority == "express" ? "express" : "standard"
         }
       }

  # Compile final order confirmation
  step :confirmation do
    {
      order_id: input.order_id,
      status: "confirmed",
      customer: input.customer,
      totals: {
        subtotal: calculate_totals[:subtotal],
        tax: calculate_totals[:tax],
        shipping: shipping.content[:shipping][:cost],
        total: (calculate_totals[:total] + shipping.content[:shipping][:cost]).round(2)
      },
      shipping: {
        carrier: shipping.content[:shipping][:carrier],
        tracking_number: shipping.content[:shipping][:tracking_number],
        estimated_delivery: "#{shipping.content[:shipping][:delivery_days]} business days"
      },
      confirmed_at: Time.current.iso8601
    }
  end
end
