# frozen_string_literal: true

# Mock value objects for testing agents without actual API responses
# These replace loose doubles with verifiable objects that match real interfaces
module RubyLLM
  module Agents
    module TestSupport
      # Mock image object that matches the interface of RubyLLM image responses
      # Used by: image_transform_result_spec, image_upscale_result_spec,
      #          image_variation_result_spec, image_generation_result_spec,
      #          background_removal_result_spec, image_edit_result_spec
      class MockImage
        attr_reader :url, :data, :mime_type, :revised_prompt
        attr_accessor :saved_paths

        def initialize(
          url: "https://example.com/image.png",
          data: nil,
          mime_type: "image/png",
          revised_prompt: nil
        )
          @url = url
          @data = data
          @mime_type = mime_type
          @revised_prompt = revised_prompt
          @saved_paths = []
        end

        def base64?
          @data.present? && @url.blank?
        end

        def to_blob
          @data || "\x89PNG\r\n\x1a\n"
        end

        def save(path)
          @saved_paths << path
          true
        end

        # Check if save was called (useful for specs)
        def saved?
          @saved_paths.any?
        end

        # Factory methods for common test scenarios
        class << self
          def with_url(url = "https://example.com/image.png", **options)
            new(url: url, **options)
          end

          def with_base64(data = "iVBORw0KGgo=", **options)
            new(url: nil, data: data, **options)
          end

          def transformed(revised_prompt: "Transformed image prompt")
            new(
              url: "https://example.com/transformed.png",
              revised_prompt: revised_prompt
            )
          end

          def upscaled
            new(
              url: "https://example.com/upscaled.png",
              mime_type: "image/png"
            )
          end

          def variation
            new(
              url: "https://example.com/variation.png",
              revised_prompt: "Image variation"
            )
          end

          def edited(revised_prompt: "Edited background")
            new(
              url: "https://example.com/edited.png",
              revised_prompt: revised_prompt
            )
          end

          def foreground
            img = new(
              url: nil,  # URL should be nil for base64 images
              data: "base64data",
              mime_type: "image/png"
            )
            # Add url method that returns the expected URL for tests
            img.define_singleton_method(:url) { "https://example.com/foreground.png" }
            # Override to_blob for foreground
            img.define_singleton_method(:to_blob) { "blob_data" }
            # Override base64? to return true
            img.define_singleton_method(:base64?) { true }
            img
          end

          def mask
            img = new(
              url: "https://example.com/mask.png",
              data: "mask_base64",
              mime_type: "image/png"
            )
            # Override to_blob for mask
            img.define_singleton_method(:to_blob) { "mask_blob" }
            img
          end
        end
      end

      # Mock step result for workflow tests
      # Used by: workflow/instrumentation_spec.rb
      class MockStepResult
        attr_reader :total_cost, :input_tokens, :output_tokens, :cached_tokens,
                    :input_cost, :output_cost, :duration_ms, :status

        def initialize(
          success: true,
          total_cost: 0.01,
          input_tokens: 100,
          output_tokens: 50,
          cached_tokens: 0,
          input_cost: 0.005,
          output_cost: 0.005,
          duration_ms: 100
        )
          @success = success
          @total_cost = total_cost
          @input_tokens = input_tokens
          @output_tokens = output_tokens
          @cached_tokens = cached_tokens
          @input_cost = input_cost
          @output_cost = output_cost
          @duration_ms = duration_ms
          @status = success ? "success" : "error"
        end

        def success?
          @success
        end

        # Factory methods for common test scenarios
        class << self
          def successful(**options)
            new(success: true, **options)
          end

          def failed(error_message: "Test error", **options)
            new(success: false, **options)
          end

          def expensive(total_cost: 1.0, input_tokens: 10_000, output_tokens: 5_000)
            new(
              total_cost: total_cost,
              input_tokens: input_tokens,
              output_tokens: output_tokens,
              input_cost: total_cost * 0.6,
              output_cost: total_cost * 0.4
            )
          end
        end
      end

      # Mock branch result for parallel workflow tests
      class MockBranchResult < MockStepResult
        attr_reader :branch_name

        def initialize(branch_name: "test_branch", **options)
          super(**options)
          @branch_name = branch_name
        end
      end

      # Mock moderation result for moderation tests
      class MockModerationResult
        attr_reader :flagged, :categories, :scores

        def initialize(
          flagged: false,
          categories: {},
          scores: {}
        )
          @flagged = flagged
          @categories = categories
          @scores = scores
        end

        def flagged?
          @flagged
        end

        # Factory methods
        class << self
          def safe
            new(
              flagged: false,
              categories: { "hate" => false, "violence" => false },
              scores: { "hate" => 0.001, "violence" => 0.002 }
            )
          end

          def flagged_hate
            new(
              flagged: true,
              categories: { "hate" => true, "violence" => false },
              scores: { "hate" => 0.95, "violence" => 0.001 }
            )
          end

          def flagged_violence
            new(
              flagged: true,
              categories: { "hate" => false, "violence" => true },
              scores: { "hate" => 0.001, "violence" => 0.92 }
            )
          end
        end
      end

      # Mock embedding result
      class MockEmbedding
        attr_reader :values, :dimensions

        def initialize(values: nil, dimensions: 1536)
          @dimensions = dimensions
          @values = values || Array.new(dimensions) { rand(-1.0..1.0) }
        end

        def to_a
          @values
        end

        class << self
          def with_dimensions(dim)
            new(dimensions: dim)
          end

          def zero_vector(dimensions: 1536)
            new(values: Array.new(dimensions, 0.0))
          end
        end
      end
    end
  end
end

# Make the mock objects available in specs
RSpec.configure do |config|
  config.before(:suite) do
    # Ensure the test support module is available
  end
end
