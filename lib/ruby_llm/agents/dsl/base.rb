# frozen_string_literal: true

module RubyLLM
  module Agents
    module DSL
      # Base DSL available to all agents.
      #
      # Provides common configuration methods that every agent type needs:
      # - model: The LLM model to use
      # - prompt: The user prompt (string with {placeholders} or block)
      # - system: System instructions
      # - description: Human-readable description
      # - timeout: Request timeout
      # - returns: Structured output schema
      #
      # @example Simplified DSL
      #   class SearchAgent < RubyLLM::Agents::BaseAgent
      #     model "gpt-4o"
      #     system "You are a helpful search assistant."
      #     prompt "Search for: {query} (limit: {limit})"
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
      # @example Dynamic prompt with block
      #   class SummaryAgent < RubyLLM::Agents::BaseAgent
      #     prompt do
      #       "Summarize in #{word_count} words: #{text}"
      #     end
      #   end
      #
      module Base
        # Regex pattern to extract {placeholder} parameters from prompt strings
        PLACEHOLDER_PATTERN = /\{(\w+)\}/.freeze

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

        # Sets the user prompt template or block
        #
        # When a string is provided, {placeholder} syntax is used to interpolate
        # parameters. Parameters are automatically registered (as required) unless
        # already defined with `param`.
        #
        # When a block is provided, it's evaluated in the instance context at
        # execution time, allowing access to all instance methods and parameters.
        #
        # @param template [String, nil] Prompt template with {placeholder} syntax
        # @yield Block that returns the prompt string (evaluated at execution time)
        # @return [String, Proc, nil] The current prompt configuration
        #
        # @example With template string (parameters auto-detected)
        #   prompt "Search for: {query} in {category}"
        #   # Automatically registers :query and :category as required params
        #
        # @example With block for dynamic prompts
        #   prompt do
        #     base = "Analyze the following"
        #     base += " in #{language}" if language != "en"
        #     "#{base}: #{text}"
        #   end
        #
        def prompt(template = nil, &block)
          if template
            @prompt_template = template
            auto_register_params_from_template(template)
          elsif block
            @prompt_block = block
          end
          @prompt_template || @prompt_block || inherited_or_default(:prompt_config, nil)
        end

        # Returns the prompt configuration (template or block)
        #
        # @return [String, Proc, nil] The prompt template, block, or nil
        def prompt_config
          @prompt_template || @prompt_block || inherited_or_default(:prompt_config, nil)
        end

        # Sets the system prompt/instructions
        #
        # @param text [String, nil] System instructions for the LLM
        # @yield Block that returns the system prompt (evaluated at execution time)
        # @return [String, Proc, nil] The current system prompt
        #
        # @example Static system prompt
        #   system "You are a helpful assistant. Be concise and accurate."
        #
        # @example Dynamic system prompt
        #   system do
        #     "You are helping #{user_name}. Their preferences: #{preferences}"
        #   end
        #
        def system(text = nil, &block)
          if text
            @system_template = text
          elsif block
            @system_block = block
          end
          @system_template || @system_block || inherited_or_default(:system_config, nil)
        end

        # Returns the system prompt configuration
        #
        # @return [String, Proc, nil] The system template, block, or nil
        def system_config
          @system_template || @system_block || inherited_or_default(:system_config, nil)
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
        rescue StandardError
          "gpt-4o"
        end

        # Returns the default timeout from configuration
        #
        # @return [Integer] The default timeout
        def default_timeout
          RubyLLM::Agents.configuration.default_timeout
        rescue StandardError
          120
        end
      end
    end
  end
end
