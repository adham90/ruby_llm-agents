# frozen_string_literal: true

# ShippingReserveAgent - Reserves shipping capacity with carrier
#
# Used in order processing workflows to reserve shipping slots
# and generate tracking information.
#
# Example usage:
#   result = ShippingReserveAgent.call(
#     carrier: "UPS",
#     shipping_cost: 12.99,
#     address: { city: "San Francisco", state: "CA", zip: "94102" },
#     items: [{ sku: "ITEM-001", quantity: 1 }]
#   )
#
class ShippingReserveAgent < ApplicationAgent
  description 'Reserves shipping capacity and generates tracking'
  model 'gpt-4o-mini'
  temperature 0.0

  param :carrier, required: true
  param :shipping_cost, required: true
  param :address, required: true
  param :items, required: true

  def system_prompt
    <<~PROMPT
      You are a shipping reservation system. Given carrier and shipment details,
      reserve shipping capacity and generate tracking information.

      Return a JSON object with:
      - reservation_id: unique reservation identifier
      - tracking_number: carrier tracking number
      - label_url: URL to shipping label (simulated)
      - pickup_scheduled: boolean indicating if pickup is scheduled
      - estimated_ship_date: ISO date string
    PROMPT
  end

  def user_prompt
    <<~PROMPT
      Reserve shipping with:

      Carrier: #{carrier}
      Cost: $#{shipping_cost}
      Address: #{format_address(address)}
      Items: #{items.size} item(s)
    PROMPT
  end

  def schema
    {
      type: 'object',
      properties: {
        reservation_id: { type: 'string' },
        tracking_number: { type: 'string' },
        label_url: { type: 'string' },
        pickup_scheduled: { type: 'boolean' },
        estimated_ship_date: { type: 'string' }
      },
      required: %w[reservation_id tracking_number label_url pickup_scheduled estimated_ship_date]
    }
  end

  private

  def format_address(addr)
    if addr.is_a?(Hash)
      "#{addr[:city]}, #{addr[:state]} #{addr[:zip]}"
    else
      addr.to_s
    end
  end
end
