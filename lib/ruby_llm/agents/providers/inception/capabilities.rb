# frozen_string_literal: true

module RubyLLM
  module Agents
    module Providers
      class Inception
        # Determines capabilities and pricing for Inception Mercury models.
        #
        # Mercury models are diffusion LLMs with text-only I/O.
        # Pricing is per million tokens.
        #
        # Models:
        # - mercury-2: Reasoning dLLM, function calling, structured output
        # - mercury: Base chat dLLM, function calling, structured output
        # - mercury-coder-small: Fast coding model
        # - mercury-edit: Code editing/FIM model
        module Capabilities
          module_function

          REASONING_MODELS = %w[mercury-2].freeze
          CODER_MODELS = %w[mercury-coder-small mercury-edit].freeze
          FUNCTION_CALLING_MODELS = %w[mercury-2 mercury].freeze

          def context_window_for(_model_id)
            128_000
          end

          def max_tokens_for(_model_id)
            32_000
          end

          def input_price_for(_model_id)
            0.25
          end

          def output_price_for(model_id)
            if CODER_MODELS.include?(model_id)
              1.00
            else
              0.75
            end
          end

          def supports_vision?(_model_id)
            false
          end

          def supports_functions?(model_id)
            FUNCTION_CALLING_MODELS.include?(model_id)
          end

          def supports_json_mode?(model_id)
            FUNCTION_CALLING_MODELS.include?(model_id)
          end

          def format_display_name(model_id)
            case model_id
            when "mercury-2" then "Mercury 2"
            when "mercury" then "Mercury"
            when "mercury-coder-small" then "Mercury Coder Small"
            when "mercury-edit" then "Mercury Edit"
            else
              model_id.split("-").map(&:capitalize).join(" ")
            end
          end

          def model_type(model_id)
            if CODER_MODELS.include?(model_id)
              "code"
            else
              "chat"
            end
          end

          def model_family(_model_id)
            :mercury
          end

          def modalities_for(_model_id)
            {input: ["text"], output: ["text"]}
          end

          def capabilities_for(model_id)
            caps = ["streaming"]
            if FUNCTION_CALLING_MODELS.include?(model_id)
              caps << "function_calling"
              caps << "structured_output"
            end
            caps << "reasoning" if REASONING_MODELS.include?(model_id)
            caps
          end

          def pricing_for(model_id)
            {
              text_tokens: {
                standard: {
                  input_per_million: input_price_for(model_id),
                  output_per_million: output_price_for(model_id)
                }
              }
            }
          end
        end
      end
    end
  end
end
