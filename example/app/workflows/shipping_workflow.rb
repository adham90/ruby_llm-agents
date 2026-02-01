# frozen_string_literal: true

# ShippingWorkflow - Handles shipping calculation and reservation
#
# A simple workflow used as a sub-workflow in OrderProcessingWorkflow.
# Demonstrates a self-contained workflow that can be composed into
# larger workflows.
#
# Usage:
#   result = ShippingWorkflow.call(
#     address: { city: "San Francisco", state: "CA", zip: "94102" },
#     items: [{ sku: "ITEM-001", weight: 2.5 }],
#     shipping_speed: "express"
#   )
#
class ShippingWorkflow < RubyLLM::Agents::Workflow
  description 'Calculates and reserves shipping for an order'
  version '1.0'
  timeout 30.seconds

  input do
    required :address, Hash
    required :items, Array
    optional :shipping_speed, String, default: 'standard'
  end

  # Calculate shipping costs and options
  step :calculate, ShippingCalculatorAgent,
       desc: 'Calculate shipping cost and delivery time',
       input: lambda {
         {
           address: input.address,
           items: input.items,
           shipping_speed: input.shipping_speed
         }
       }

  # Reserve shipping with the carrier
  step :reserve, ShippingReserveAgent,
       desc: 'Reserve shipping capacity and get tracking',
       input: lambda {
         {
           carrier: calculate.carrier,
           shipping_cost: calculate.cost,
           address: input.address,
           items: input.items
         }
       }

  # Final step to compile shipping details
  step :finalize do
    {
      shipping: {
        carrier: calculate.carrier,
        cost: calculate.cost,
        delivery_days: calculate.delivery_days,
        tracking_number: reserve.tracking_number,
        label_url: reserve.label_url,
        estimated_ship_date: reserve.estimated_ship_date
      }
    }
  end
end
