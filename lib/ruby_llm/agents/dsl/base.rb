# frozen_string_literal: true

module RubyLLM
  module Agents
    module DSL
      # Base DSL available to all agents.
      #
      # Provides common configuration methods that every agent type needs:
      # - model: The LLM model to use
      # - system: System instructions
      # - user: The user prompt (string with {placeholders})
      # - assistant: Assistant prefill (string with optional {placeholders})
      # - description: Human-readable description
      # - timeout: Request timeout
      # - returns: Structured output schema
      #
      # Two levels for defining prompts:
      # - Class-level string/heredoc for static content
      # - Instance method override for dynamic content
      #
      # @example Template agent (structured input via .call)
      #   class SearchAgent < RubyLLM::Agents::BaseAgent
      #     model "gpt-4o"
      #     system "You are a helpful search assistant."
      #     user "Search for: {query} (limit: {limit})"
      #     assistant '{"results":['
      #
      #     param :limit, default: 10  # Override auto-detected param
      #
      #     returns do
      #       array :results do
      #         string :title
      #         string :url
      #       end
      #     end
      #   end
      #
      # @example Conversational agent (freeform input via .ask)
      #   class RubyExpert < RubyLLM::Agents::BaseAgent
      #     model "gpt-4o"
      #     system "You are a senior Ruby developer."
      #   end
      #
      #   RubyExpert.ask("What is metaprogramming?")
      #
      # @example Dynamic prompts with method overrides
      #   class SmartAgent < RubyLLM::Agents::BaseAgent
      #     def system_prompt
      #       "You are helping #{company.name}. Today is #{Date.today}."
      #     end
      #
      #     def user_prompt
      #       "Question: #{params[:question]}"
      #     end
      #   end
      #
      module Base
        # Regex pattern to extract {placeholder} parameters from prompt strings
        PLACEHOLDER_PATTERN = /\{(\w+)\}/

        # @!group Configuration DSL

        # Sets or returns the LLM model for this agent class
        #
        # @param value [String, nil] The model identifier to set
        # @return [String] The current model setting
        # @example
        #   model "gpt-4o"
        def model(value = nil)
          @model = value if value
          @model || inherited_or_default(:model, default_model)
        end

        # Sets the user prompt template
        #
        # When a string is provided, {placeholder} syntax is used to interpolate
        # parameters. Parameters are automatically registered (as required) unless
        # already defined with `param`.
        #
        # @param template [String, nil] Prompt template with {placeholder} syntax
        # @return [String, nil] The current user prompt configuration
        #
        # @example With template string (parameters auto-detected)
        #   user "Search for: {query} in {category}"
        #   # Automatically registers :query and :category as required params
        #
        # @example Multi-line with heredoc
        #   user <<~S
        #     Search for: {query}
        #     Category: {category}
        #     Limit: {limit}
        #   S
        #
        def user(template = nil)
          if template
            @user_template = template
            auto_register_params_from_template(template)
          end
          @user_template || inherited_or_default(:user_config, nil)
        end

        # Returns the user prompt configuration
        #
        # @return [String, nil] The user template, or nil
        def user_config
          @user_template || inherited_or_default(:user_config, nil)
        end

        # Backward-compatible alias for `user`
        #
        # @deprecated Use `user` instead.
        # @param template [String, nil] Prompt template with {placeholder} syntax
        # @return [String, nil] The current prompt configuration
        def prompt(template = nil)
          if template
            Deprecations.warn(
              "`prompt` is deprecated. Use `user` instead (e.g., `user \"#{template.truncate(40)}\"`).",
              caller
            )
            @user_template = template
            auto_register_params_from_template(template)
          end
          @user_template || inherited_or_default(:user_config, nil)
        end

        # Sets the system prompt/instructions
        #
        # When a string is provided, {placeholder} syntax is supported for
        # parameter interpolation, same as the `user` DSL.
        #
        # @param text [String, nil] System instructions for the LLM
        # @return [String, nil] The current system prompt
        #
        # @example Static system prompt
        #   system "You are a helpful assistant. Be concise and accurate."
        #
        # @example With placeholders
        #   system "You are helping {user_name} with their {task}."
        #
        # @example Dynamic system prompt (method override)
        #   def system_prompt
        #     "You are helping #{user_name}. Today is #{Date.today}."
        #   end
        #
        def system(text = nil)
          if text
            @system_template = text
            auto_register_params_from_template(text)
          end
          @system_template || inherited_or_default(:system_config, nil)
        end

        # Returns the system prompt configuration
        #
        # @return [String, nil] The system template, or nil
        def system_config
          @system_template || inherited_or_default(:system_config, nil)
        end

        # Sets the assistant prefill string
        #
        # The assistant prefill is sent as the last message with the "assistant"
        # role, priming the model to continue from that point. Useful for:
        # - Forcing output format (e.g., starting with "{" for JSON)
        # - Steering the response style
        #
        # Supports {placeholder} syntax for parameter interpolation.
        #
        # @param text [String, nil] The assistant prefill text
        # @return [String, nil] The current assistant configuration
        #
        # @example Force JSON output
        #   assistant '{"category":'
        #
        # @example With placeholders
        #   assistant "Results for {query}:"
        #
        def assistant(text = nil)
          if text
            @assistant_template = text
            auto_register_params_from_template(text)
          end
          @assistant_template || inherited_or_default(:assistant_config, nil)
        end

        # Returns the assistant prefill configuration
        #
        # @return [String, nil] The assistant template, or nil
        def assistant_config
          @assistant_template || inherited_or_default(:assistant_config, nil)
        end

        # Sets or returns the description for this agent class
        #
        # Useful for documentation and tool registration.
        #
        # @param value [String, nil] The description text
        # @return [String, nil] The current description
        # @example
        #   description "Searches the knowledge base for relevant documents"
        def description(value = nil)
          @description = value if value
          @description || inherited_or_default(:description, nil)
        end

        # Sets or returns the timeout in seconds for LLM requests
        #
        # @param value [Integer, nil] Timeout in seconds
        # @return [Integer] The current timeout setting
        # @example
        #   timeout 30
        def timeout(value = nil)
          @timeout = value if value
          @timeout || inherited_or_default(:timeout, default_timeout)
        end

        # Enables Anthropic prompt caching for this agent
        #
        # When enabled, adds cache_control breakpoints to the system prompt
        # and the last tool definition so Anthropic caches them across
        # multi-turn agent loops. This reduces input token costs by ~90%
        # on subsequent calls within the same cache window (~5 minutes).
        #
        # Only takes effect when the resolved model is served by Anthropic.
        # Non-Anthropic models silently ignore this setting.
        #
        # @param value [Boolean, nil] Whether to enable prompt caching
        # @return [Boolean] The current setting
        #
        # @example
        #   class BuildAgent < ApplicationAgent
        #     cache_prompts true
        #     system "You are a build assistant."
        #     tools BuildTool, TestTool, DeployTool
        #   end
        #
        def cache_prompts(value = nil)
          @cache_prompts = value unless value.nil?
          return @cache_prompts if defined?(@cache_prompts) && !@cache_prompts.nil?

          inherited_or_default(:cache_prompts, false)
        end

        # Sets or returns the response schema for structured output
        #
        # Accepts a hash (JSON Schema), a block (passed to RubyLLM::Schema.create),
        # or any object that responds to `to_json_schema`.
        #
        # @param value [Hash, Object, nil] The schema to set
        # @param block [Proc, nil] Block passed to RubyLLM::Schema.create
        # @return [Hash, RubyLLM::Schema, nil] The current schema setting
        # @example With a block (recommended)
        #   schema do
        #     string :name, description: "The user's name"
        #     integer :age, description: "The user's age"
        #   end
        # @example With a hash
        #   schema type: "object", properties: { name: { type: "string" } }
        def schema(value = nil, &block)
          if value
            @schema = value
          elsif block
            @schema = RubyLLM::Schema.create(&block)
          end
          @schema || inherited_or_default(:schema, nil)
        end

        # Alias for schema with a clearer name
        #
        # Defines the structured output schema for this agent.
        # This is the preferred method for defining schemas in the simplified DSL.
        #
        # @param block [Proc] Block passed to RubyLLM::Schema.create
        # @return [RubyLLM::Schema, nil] The current schema setting
        #
        # @example
        #   returns do
        #     string :summary, "A brief summary"
        #     array :insights, of: :string, description: "Key insights"
        #     number :confidence, "Confidence score from 0 to 1"
        #   end
        #
        def returns(&block)
          schema(&block)
        end

        # @!endgroup

        private

        # Auto-registers parameters found in prompt template placeholders
        #
        # Extracts {placeholder} patterns from the template and registers
        # each as a required parameter (unless already defined).
        #
        # @param template [String] The prompt template
        # @return [void]
        def auto_register_params_from_template(template)
          return unless respond_to?(:param)

          placeholders = template.scan(PLACEHOLDER_PATTERN).flatten.map(&:to_sym)
          existing_params = respond_to?(:params) ? params.keys : []

          placeholders.each do |placeholder|
            next if existing_params.include?(placeholder)

            # Auto-register as required parameter
            param(placeholder, required: true)
          end
        end

        # Looks up setting from superclass or uses default
        #
        # @param method [Symbol] The method to call on superclass
        # @param default [Object] Default value if not found
        # @return [Object] The resolved value
        def inherited_or_default(method, default)
          return default unless superclass.respond_to?(method)

          superclass.send(method)
        end

        # Returns the default model from configuration
        #
        # @return [String] The default model
        def default_model
          RubyLLM::Agents.configuration.default_model
        rescue
          "gpt-4o"
        end

        # Returns the default timeout from configuration
        #
        # @return [Integer] The default timeout
        def default_timeout
          RubyLLM::Agents.configuration.default_timeout
        rescue
          120
        end
      end
    end
  end
end
