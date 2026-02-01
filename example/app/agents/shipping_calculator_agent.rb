# frozen_string_literal: true

# ShippingCalculatorAgent - Calculates shipping costs and options
#
# Used in order processing workflows to determine shipping rates
# based on address, items, and shipping preferences.
#
# Example usage:
#   result = ShippingCalculatorAgent.call(
#     address: { city: "San Francisco", state: "CA", zip: "94102" },
#     items: [{ weight: 2.5, dimensions: "10x8x4" }],
#     shipping_speed: "standard"
#   )
#
class ShippingCalculatorAgent < ApplicationAgent
  description 'Calculates shipping costs and delivery estimates'
  model 'gpt-4o-mini'
  temperature 0.0

  param :address, required: true
  param :items, required: true
  param :shipping_speed, default: 'standard'

  def system_prompt
    <<~PROMPT
      You are a shipping cost calculator. Given an address, items, and shipping speed,
      calculate the shipping cost and estimated delivery time.

      Return a JSON object with:
      - carrier: recommended carrier (e.g., "UPS", "FedEx", "USPS")
      - cost: shipping cost in USD
      - delivery_days: estimated delivery days
      - tracking_available: boolean
    PROMPT
  end

  def user_prompt
    <<~PROMPT
      Calculate shipping for:

      Address: #{format_address(address)}
      Items: #{format_items(items)}
      Speed: #{shipping_speed}
    PROMPT
  end

  def schema
    {
      type: 'object',
      properties: {
        carrier: { type: 'string' },
        cost: { type: 'number' },
        delivery_days: { type: 'integer' },
        tracking_available: { type: 'boolean' }
      },
      required: %w[carrier cost delivery_days tracking_available]
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

  def format_items(item_list)
    Array(item_list).map do |item|
      if item.is_a?(Hash)
        "#{item[:weight]}lb (#{item[:dimensions]})"
      else
        item.to_s
      end
    end.join(', ')
  end
end
