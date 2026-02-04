# frozen_string_literal: true

require_relative "../concerns/image_operation_dsl"

module RubyLLM
  module Agents
    class ImageEditor
      # DSL for configuring image editors
      #
      # Provides class-level methods to configure model, size,
      # and other image editing parameters.
      #
      # @example
      #   class ProductEditor < RubyLLM::Agents::ImageEditor
      #     model "gpt-image-1"
      #     size "1024x1024"
      #   end
      #
      module DSL
        include Concerns::ImageOperationDSL

        # Set or get the output image size
        #
        # @param value [String, nil] Size (e.g., "1024x1024")
        # @return [String] The size to use
        def size(value = nil)
          if value
            @size = value
          else
            @size || inherited_or_default(:size, config.default_image_size)
          end
        end

        private

        def default_model
          config.default_editor_model || config.default_image_model
        end
      end
    end
  end
end
