# frozen_string_literal: true

require "rails/generators"

module RubyLlmAgents
  # Agent generator for creating new agents
  #
  # Usage:
  #   rails generate ruby_llm_agents:agent SearchIntent query:required limit:10
  #
  # This will create:
  #   - app/agents/search_intent_agent.rb
  #
  # Parameter syntax:
  #   name           - Optional parameter
  #   name:required  - Required parameter
  #   name:default   - Optional with default value (e.g., limit:10)
  #
  class AgentGenerator < ::Rails::Generators::NamedBase
    source_root File.expand_path("templates", __dir__)

    argument :params, type: :array, default: [], banner: "param[:required|:default] param[:required|:default]"

    class_option :model, type: :string, default: "gemini-2.0-flash",
                 desc: "The LLM model to use"
    class_option :temperature, type: :numeric, default: 0.0,
                 desc: "The temperature setting (0.0-1.0)"
    class_option :cache, type: :string, default: nil,
                 desc: "Cache TTL (e.g., '1.hour', '30.minutes')"

    def create_agent_file
      # Support nested paths: "chat/support" -> "app/agents/chat/support_agent.rb"
      # Rails' class_name handles namespacing: "chat/support" -> "Chat::Support"
      agent_path = name.underscore
      template "agent.rb.tt", "app/agents/#{agent_path}_agent.rb"
    end

    def show_usage
      full_class_name = (namespace_parts + [agent_class_name]).join("::")
      say ""
      say "Agent #{full_class_name}Agent created!", :green
      say ""
      say "Usage:"
      say "  #{full_class_name}Agent.call(#{usage_params})"
      say "  #{full_class_name}Agent.call(#{usage_params}, dry_run: true)"
      say ""
    end

    private

    # Returns the full class path as an array (e.g., ["Chat", "Support", "Ticket"] for "chat/support/ticket")
    # Computed directly from name to avoid Rails namespace issues
    def class_path_parts
      @class_path_parts ||= name.split('/').map { |part| part.camelize }
    end

    # Returns the namespace modules as an array (e.g., ["Chat", "Support"] for "chat/support/ticket")
    def namespace_parts
      @namespace_parts ||= class_path_parts[0..-2]
    end

    # Returns just the agent class name without namespace (e.g., "Ticket" for "chat/support/ticket")
    def agent_class_name
      @agent_class_name ||= class_path_parts.last
    end

    # Returns true if this agent is namespaced
    def namespaced?
      namespace_parts.any?
    end

    def parsed_params
      @parsed_params ||= params.map do |param|
        name, modifier = param.split(":")
        ParsedParam.new(name, modifier)
      end
    end

    def usage_params
      parsed_params.map do |p|
        if p.required?
          "#{p.name}: value"
        else
          "#{p.name}: #{p.default || 'value'}"
        end
      end.join(", ")
    end

    # Helper class for parsing parameter definitions
    class ParsedParam
      attr_reader :name, :default

      def initialize(name, modifier)
        @name = name
        @required = modifier == "required"
        @default = @required ? nil : modifier
      end

      def required?
        @required
      end
    end
  end
end
