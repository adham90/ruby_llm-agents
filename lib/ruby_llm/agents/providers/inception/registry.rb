# frozen_string_literal: true

module RubyLLM
  module Agents
    module Providers
      class Inception
        # Registers Mercury models in the RubyLLM model registry so they
        # can be resolved by model ID without calling the Inception /models API.
        module Registry
          MODELS = [
            {id: "mercury-2", name: "Mercury 2"},
            {id: "mercury", name: "Mercury"},
            {id: "mercury-coder-small", name: "Mercury Coder Small"},
            {id: "mercury-edit", name: "Mercury Edit"}
          ].freeze

          module_function

          def register_models!
            models_instance = ::RubyLLM::Models.instance
            capabilities = Inception::Capabilities

            MODELS.each do |model_def|
              model_id = model_def[:id]

              model_info = ::RubyLLM::Model::Info.new(
                id: model_id,
                name: model_def[:name],
                provider: "inception",
                family: "mercury",
                context_window: capabilities.context_window_for(model_id),
                max_output_tokens: capabilities.max_tokens_for(model_id),
                modalities: capabilities.modalities_for(model_id),
                capabilities: capabilities.capabilities_for(model_id),
                pricing: capabilities.pricing_for(model_id)
              )

              models_instance.all << model_info
            end
          end
        end
      end
    end
  end
end
