# frozen_string_literal: true

module RubyLLM
  module Agents
    module Providers
      class Inception
        # Chat methods for Inception Mercury API.
        # Mercury uses standard OpenAI chat format.
        module Chat
          def format_role(role)
            role.to_s
          end
        end
      end
    end
  end
end
