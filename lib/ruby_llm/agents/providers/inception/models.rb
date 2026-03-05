# frozen_string_literal: true

module RubyLLM
  module Agents
    module Providers
      class Inception
        # Parses model metadata from the Inception /models API endpoint.
        # Response format is OpenAI-compatible.
        module Models
          module_function

          def parse_list_models_response(response, slug, capabilities)
            Array(response.body["data"]).map do |model_data|
              model_id = model_data["id"]

              ::RubyLLM::Model::Info.new(
                id: model_id,
                name: capabilities.format_display_name(model_id),
                provider: slug,
                family: "mercury",
                created_at: model_data["created"] ? Time.at(model_data["created"]) : nil,
                context_window: capabilities.context_window_for(model_id),
                max_output_tokens: capabilities.max_tokens_for(model_id),
                modalities: capabilities.modalities_for(model_id),
                capabilities: capabilities.capabilities_for(model_id),
                pricing: capabilities.pricing_for(model_id),
                metadata: {
                  object: model_data["object"],
                  owned_by: model_data["owned_by"]
                }.compact
              )
            end
          end
        end
      end
    end
  end
end
