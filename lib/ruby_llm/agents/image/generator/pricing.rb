# frozen_string_literal: true

require_relative "../../pricing/data_store"
require_relative "../../pricing/ruby_llm_adapter"
require_relative "../../pricing/litellm_adapter"

module RubyLLM
  module Agents
    class ImageGenerator
      # Dynamic pricing resolution for image generation models.
      #
      # Uses a three-tier strategy (no hardcoded prices):
      # 1. Configurable pricing table - user overrides
      # 2. RubyLLM gem (local, no HTTP) - model registry pricing
      # 3. LiteLLM (via shared DataStore) - comprehensive, community-maintained
      #
      # When no pricing is found, returns 0 to signal unknown cost.
      #
      # @example Get price for a model
      #   Pricing.cost_per_image("gpt-image-1", size: "1024x1024", quality: "hd")
      #   # => 0.08
      #
      # @example Calculate total cost
      #   Pricing.calculate_cost(model_id: "dall-e-3", size: "1024x1024", count: 4)
      #   # => 0.16
      #
      module Pricing
        extend self

        # Calculate total cost for image generation
        #
        # @param model_id [String] The model identifier
        # @param size [String] Image size (e.g., "1024x1024")
        # @param quality [String] Quality setting ("standard", "hd")
        # @param count [Integer] Number of images
        # @return [Float] Total cost in USD
        def calculate_cost(model_id:, size: nil, quality: nil, count: 1)
          cost = cost_per_image(model_id, size: size, quality: quality)
          (cost * count).round(6)
        end

        # Get cost for a single image
        #
        # @param model_id [String] The model identifier
        # @param size [String] Image size
        # @param quality [String] Quality setting
        # @return [Float] Cost per image in USD (0 if unknown)
        def cost_per_image(model_id, size: nil, quality: nil)
          # Tier 1: User-configurable pricing table
          if (config_price = from_config(model_id, size, quality))
            return config_price
          end

          # Tier 2: RubyLLM gem (local, no HTTP)
          if (ruby_llm_price = from_ruby_llm(model_id))
            return ruby_llm_price
          end

          # Tier 3: LiteLLM (via shared DataStore + adapter)
          if (litellm_price = from_litellm(model_id, size, quality))
            return litellm_price
          end

          # No pricing found — return user-configured default or 0
          config.default_image_cost || 0
        end

        # Refresh pricing data
        #
        # @return [void]
        def refresh!
          Agents::Pricing::DataStore.refresh!
        end

        private

        # ============================================================
        # Tier 1: User-configurable pricing table
        # ============================================================

        def from_config(model_id, size, quality)
          table = config.image_model_pricing
          return nil unless table

          normalized = normalize_model_id(model_id)

          # Try exact match, then normalized
          pricing = table[model_id] || table[normalized] || table[model_id.to_sym] || table[normalized.to_sym]
          return nil unless pricing

          resolve_config_price(pricing, size, quality)
        end

        def resolve_config_price(pricing, size, quality)
          return pricing if pricing.is_a?(Numeric)
          return nil unless pricing.is_a?(Hash)

          # Size/quality combined key (e.g., "1024x1024/hd")
          combined_key = [size, quality].compact.join("/")
          if combined_key.present? && (pricing[combined_key] || pricing[combined_key.to_sym])
            return pricing[combined_key] || pricing[combined_key.to_sym]
          end

          # Size-specific pricing
          if size && (pricing[size] || pricing[size.to_sym])
            return pricing[size] || pricing[size.to_sym]
          end

          # Quality-specific pricing
          if quality == "hd"
            if pricing[:hd] || pricing["hd"]
              pixels = parse_pixels(size)
              if pixels && pixels >= 1_000_000 && (pricing[:large_hd] || pricing["large_hd"])
                return pricing[:large_hd] || pricing["large_hd"]
              end
              return pricing[:hd] || pricing["hd"]
            end
          end

          # Base price
          pricing[:base] || pricing["base"] || pricing[:default] || pricing["default"] || pricing[:standard] || pricing["standard"]
        end

        # ============================================================
        # Tier 2: RubyLLM gem (local, no HTTP)
        # ============================================================

        def from_ruby_llm(model_id)
          data = Agents::Pricing::RubyLLMAdapter.find_model(model_id)
          return nil unless data

          data[:input_cost_per_image]
        end

        # ============================================================
        # Tier 3: LiteLLM (via shared DataStore + adapter)
        # ============================================================

        def from_litellm(model_id, size, quality)
          data = Agents::Pricing::LiteLLMAdapter.find_model(model_id)
          return nil unless data

          extract_image_price(data, size, quality)
        end

        def extract_image_price(data, size, quality)
          # Check quality-specific pricing first when HD requested
          if quality == "hd" && data[:input_cost_per_image_hd]
            return data[:input_cost_per_image_hd]
          end

          if data[:input_cost_per_image]
            return data[:input_cost_per_image]
          end

          if data[:input_cost_per_pixel] && size
            width, height = size.split("x").map(&:to_i)
            pixels = width * height
            return (data[:input_cost_per_pixel] * pixels).round(6)
          end

          nil
        end

        def litellm_image_models
          data = Agents::Pricing::DataStore.litellm_data
          return {} unless data.is_a?(Hash)

          data.select do |key, value|
            value.is_a?(Hash) && (
              value["input_cost_per_image"] ||
              value["input_cost_per_pixel"] ||
              key.to_s.match?(/dall-e|flux|sdxl|stable|imagen|image/i)
            )
          end
        end

        def parse_pixels(size)
          return nil unless size
          width, height = size.to_s.split("x").map(&:to_i)
          return nil if width.zero? || height.zero?
          width * height
        rescue
          nil
        end

        def normalize_model_id(model_id)
          model_id.to_s
            .downcase
            .gsub(/[^a-z0-9.-]/, "-").squeeze("-")
            .gsub(/^-|-$/, "")
        end

        def config
          RubyLLM::Agents.configuration
        end
      end
    end
  end
end
