# frozen_string_literal: true

# Configuration extension must be loaded first (adds inception_api_key to RubyLLM::Configuration)
require_relative "inception/configuration"

module RubyLLM
  module Agents
    module Providers
      # Inception Labs Mercury API integration (OpenAI-compatible).
      # Mercury models are diffusion LLMs (dLLMs) that generate tokens
      # in parallel for dramatically faster inference.
      #
      # @see https://docs.inceptionlabs.ai/
      class Inception < ::RubyLLM::Providers::OpenAI
        def api_base
          "https://api.inceptionlabs.ai/v1"
        end

        def headers
          {
            "Authorization" => "Bearer #{@config.inception_api_key}"
          }
        end

        class << self
          def capabilities
            Inception::Capabilities
          end

          def configuration_requirements
            %i[inception_api_key]
          end
        end
      end
    end
  end
end

# Load sub-modules after the class is defined
require_relative "inception/capabilities"
require_relative "inception/chat"
require_relative "inception/models"
require_relative "inception/registry"

# Include modules after they're loaded
RubyLLM::Agents::Providers::Inception.include RubyLLM::Agents::Providers::Inception::Chat
RubyLLM::Agents::Providers::Inception.include RubyLLM::Agents::Providers::Inception::Models

# Register Mercury models in the RubyLLM model registry
RubyLLM::Agents::Providers::Inception::Registry.register_models!
