# frozen_string_literal: true

require "net/http"
require "json"

module RubyLLM
  module Agents
    class ImageGenerator
      # Dynamic pricing resolution for image generation models
      #
      # Uses a three-tier strategy:
      # 1. LiteLLM JSON (primary) - comprehensive, community-maintained
      # 2. Configurable pricing table - user overrides
      # 3. Hardcoded fallbacks - last resort
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

        LITELLM_PRICING_URL = "https://raw.githubusercontent.com/BerriAI/litellm/main/model_prices_and_context_window.json"
        DEFAULT_CACHE_TTL = 24 * 60 * 60 # 24 hours in seconds

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
        # @return [Float] Cost per image in USD
        def cost_per_image(model_id, size: nil, quality: nil)
          # 1. Try LiteLLM pricing data
          if (litellm_price = from_litellm(model_id, size, quality))
            return litellm_price
          end

          # 2. Try configurable pricing table
          if (config_price = from_config(model_id, size, quality))
            return config_price
          end

          # 3. Fall back to hardcoded estimates
          fallback_price(model_id, size, quality)
        end

        # Refresh pricing data from LiteLLM
        #
        # @return [Hash] The fetched pricing data
        def refresh!
          @litellm_data = nil
          @litellm_fetched_at = nil
          litellm_data
        end

        # Get all known pricing for debugging/display
        #
        # @return [Hash] Merged pricing from all sources
        def all_pricing
          {
            litellm: litellm_image_models,
            configured: config.image_model_pricing || {},
            fallbacks: fallback_pricing_table
          }
        end

        private

        # Fetch from LiteLLM JSON
        def from_litellm(model_id, size, quality)
          data = litellm_data
          return nil unless data

          # Try exact match first
          model_data = find_litellm_model(data, model_id, size, quality)
          return nil unless model_data

          extract_litellm_price(model_data, size, quality)
        end

        def find_litellm_model(data, model_id, size, quality)
          normalized = normalize_model_id(model_id)

          # Try various key formats LiteLLM uses
          candidates = [
            model_id,
            normalized,
            "#{size}/#{model_id}",
            "#{size}/#{quality}/#{model_id}",
            "aiml/#{normalized}",
            "together_ai/#{normalized}"
          ]

          candidates.each do |key|
            return data[key] if data[key]
          end

          # Fuzzy match by model name pattern
          data.find do |key, _value|
            key_lower = key.to_s.downcase
            normalized_lower = normalized.downcase

            key_lower.include?(normalized_lower) ||
              normalized_lower.include?(key_lower.split("/").last.to_s)
          end&.last
        end

        def extract_litellm_price(model_data, size, quality)
          # LiteLLM uses different pricing fields for images
          if model_data["input_cost_per_image"]
            return model_data["input_cost_per_image"]
          end

          if model_data["input_cost_per_pixel"] && size
            width, height = size.split("x").map(&:to_i)
            pixels = width * height
            return (model_data["input_cost_per_pixel"] * pixels).round(6)
          end

          # Some models have quality-based pricing
          if quality == "hd" && model_data["input_cost_per_image_hd"]
            return model_data["input_cost_per_image_hd"]
          end

          nil
        end

        def litellm_data
          return @litellm_data if @litellm_data && !cache_expired?

          @litellm_data = fetch_litellm_data
          @litellm_fetched_at = Time.now
          @litellm_data
        end

        def fetch_litellm_data
          # Use Rails cache if available
          if defined?(Rails) && Rails.cache
            Rails.cache.fetch("litellm_pricing_data", expires_in: cache_ttl) do
              fetch_from_url
            end
          else
            fetch_from_url
          end
        rescue StandardError => e
          warn "[RubyLLM::Agents] Failed to fetch LiteLLM pricing: #{e.message}"
          {}
        end

        def fetch_from_url
          uri = URI(config.litellm_pricing_url || LITELLM_PRICING_URL)
          http = Net::HTTP.new(uri.host, uri.port)
          http.use_ssl = uri.scheme == "https"
          http.open_timeout = 5
          http.read_timeout = 10

          request = Net::HTTP::Get.new(uri)
          response = http.request(request)

          if response.is_a?(Net::HTTPSuccess)
            JSON.parse(response.body)
          else
            {}
          end
        rescue StandardError => e
          warn "[RubyLLM::Agents] HTTP error fetching LiteLLM pricing: #{e.message}"
          {}
        end

        def cache_expired?
          return true unless @litellm_fetched_at
          Time.now - @litellm_fetched_at > cache_ttl
        end

        def cache_ttl
          ttl = config.litellm_pricing_cache_ttl
          return DEFAULT_CACHE_TTL unless ttl

          # Handle ActiveSupport::Duration
          ttl.respond_to?(:to_i) ? ttl.to_i : ttl
        end

        # Get image-specific models from LiteLLM data
        def litellm_image_models
          litellm_data.select do |key, value|
            value.is_a?(Hash) && (
              value["input_cost_per_image"] ||
              value["input_cost_per_pixel"] ||
              key.to_s.match?(/dall-e|flux|sdxl|stable|imagen|image/i)
            )
          end
        end

        # Fetch from configurable pricing table
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

        # Hardcoded fallback prices
        def fallback_price(model_id, size, quality)
          normalized = normalize_model_id(model_id)

          case normalized
          when /gpt-image-1|dall-e-3/i
            dalle3_price(size, quality)
          when /dall-e-2/i
            dalle2_price(size)
          when /imagen/i
            0.02
          when /flux.*pro.*ultra/i
            0.063
          when /flux.*pro/i
            0.05
          when /flux.*dev/i
            0.025
          when /flux.*schnell/i
            0.003
          when /sdxl.*lightning/i
            0.002
          when /sdxl|stable-diffusion-xl/i
            0.04
          when /stable-diffusion/i
            0.02
          when /ideogram/i
            0.04
          when /recraft/i
            0.04
          when /real-esrgan|upscal/i
            0.01
          when /blip|caption|analyz/i
            0.001
          when /segment|background|rembg/i
            0.01
          else
            config.default_image_cost || 0.04
          end
        end

        def dalle3_price(size, quality)
          pixels = parse_pixels(size)
          is_large = pixels && pixels >= 1_000_000

          case quality
          when "hd"
            is_large ? 0.12 : 0.08
          else
            is_large ? 0.08 : 0.04
          end
        end

        def dalle2_price(size)
          case size
          when "1024x1024" then 0.02
          when "512x512" then 0.018
          when "256x256" then 0.016
          else 0.02
          end
        end

        def fallback_pricing_table
          {
            "gpt-image-1" => { standard: 0.04, hd: 0.08, large_hd: 0.12 },
            "dall-e-3" => { standard: 0.04, hd: 0.08, large_hd: 0.12 },
            "dall-e-2" => { "1024x1024" => 0.02, "512x512" => 0.018, "256x256" => 0.016 },
            "flux-pro" => 0.05,
            "flux-dev" => 0.025,
            "flux-schnell" => 0.003,
            "sdxl" => 0.04,
            "stable-diffusion-3.5" => 0.03,
            "imagen-3" => 0.02,
            "ideogram-2" => 0.04
          }
        end

        def parse_pixels(size)
          return nil unless size
          width, height = size.to_s.split("x").map(&:to_i)
          return nil if width.zero? || height.zero?
          width * height
        rescue StandardError
          nil
        end

        def normalize_model_id(model_id)
          model_id.to_s
                  .downcase
                  .gsub(/[^a-z0-9.-]/, "-")
                  .gsub(/-+/, "-")
                  .gsub(/^-|-$/, "")
        end

        def config
          RubyLLM::Agents.configuration
        end
      end
    end
  end
end
