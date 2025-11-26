# frozen_string_literal: true

module RubyLLM
  module Agents
    # View helpers for the RubyLLM::Agents dashboard
    #
    # Provides formatting utilities for displaying execution data,
    # including number formatting, URL helpers, and JSON syntax highlighting.
    #
    # @api public
    module ApplicationHelper
      include Chartkick::Helper if defined?(Chartkick)

      # Returns the URL helpers for the engine's routes
      #
      # Use this to generate paths and URLs within the dashboard views.
      #
      # @return [Module] URL helpers module with path/url methods
      # @example Generate execution path
      #   ruby_llm_agents.execution_path(execution)
      # @example Generate agents index URL
      #   ruby_llm_agents.agents_url
      def ruby_llm_agents
        RubyLLM::Agents::Engine.routes.url_helpers
      end

      # Formats large numbers with human-readable suffixes (K, M, B)
      #
      # @param number [Numeric, nil] The number to format
      # @param prefix [String, nil] Optional prefix (e.g., "$" for currency)
      # @param precision [Integer] Decimal places to show (default: 1)
      # @return [String] Formatted number with suffix
      # @example Basic usage
      #   number_to_human_short(1234567) #=> "1.2M"
      # @example With currency prefix
      #   number_to_human_short(1500, prefix: "$") #=> "$1.5K"
      # @example With custom precision
      #   number_to_human_short(1234567, precision: 2) #=> "1.23M"
      # @example Small numbers
      #   number_to_human_short(0.00123, precision: 1) #=> "0.0012"
      def number_to_human_short(number, prefix: nil, precision: 1)
        return "#{prefix}0" if number.nil? || number.zero?

        abs_number = number.to_f.abs
        formatted = if abs_number >= 1_000_000_000
          "#{(number / 1_000_000_000.0).round(precision)}B"
        elsif abs_number >= 1_000_000
          "#{(number / 1_000_000.0).round(precision)}M"
        elsif abs_number >= 1_000
          "#{(number / 1_000.0).round(precision)}K"
        elsif abs_number < 1 && abs_number > 0
          number.round(precision + 3).to_s
        else
          number.round(precision).to_s
        end

        "#{prefix}#{formatted}"
      end

      # Renders an enabled/disabled badge
      #
      # @param enabled [Boolean] Whether the feature is enabled
      # @return [ActiveSupport::SafeBuffer] HTML badge element
      def render_enabled_badge(enabled)
        if enabled
          '<span class="inline-flex items-center px-2 py-1 rounded text-xs font-medium bg-green-100 dark:bg-green-900/50 text-green-700 dark:text-green-300">Enabled</span>'.html_safe
        else
          '<span class="inline-flex items-center px-2 py-1 rounded text-xs font-medium bg-gray-100 dark:bg-gray-700 text-gray-500 dark:text-gray-400">Disabled</span>'.html_safe
        end
      end

      # Renders a configured/not configured badge
      #
      # @param configured [Boolean] Whether the setting is configured
      # @return [ActiveSupport::SafeBuffer] HTML badge element
      def render_configured_badge(configured)
        if configured
          '<span class="inline-flex items-center px-2 py-1 rounded text-xs font-medium bg-green-100 dark:bg-green-900/50 text-green-700 dark:text-green-300">Configured</span>'.html_safe
        else
          '<span class="inline-flex items-center px-2 py-1 rounded text-xs font-medium bg-gray-100 dark:bg-gray-700 text-gray-500 dark:text-gray-400">Not configured</span>'.html_safe
        end
      end

      # Syntax-highlights a Ruby object as pretty-printed JSON
      #
      # Converts the object to JSON and applies color highlighting
      # using Tailwind CSS classes.
      #
      # @param obj [Object] Any JSON-serializable Ruby object
      # @return [ActiveSupport::SafeBuffer] HTML-safe highlighted JSON string
      # @see #highlight_json_string
      # @example
      #   highlight_json({ name: "test", count: 42 })
      def highlight_json(obj)
        return "" if obj.nil?

        json_string = JSON.pretty_generate(obj)
        highlight_json_string(json_string)
      end

      # Syntax-highlights a JSON string with Tailwind CSS colors
      #
      # Tokenizes the JSON and wraps each token type in a span with
      # appropriate color classes:
      # - Purple (text-purple-600): Object keys
      # - Green (text-green-600): String values
      # - Blue (text-blue-600): Numbers
      # - Amber (text-amber-600): Booleans (true/false)
      # - Gray (text-gray-400): null values
      #
      # The tokenizer uses a character-by-character approach:
      # 1. Identifies token type by first character
      # 2. Parses complete token (handling escapes in strings)
      # 3. Determines if strings are keys (followed by colon)
      # 4. Wraps each token in appropriate span
      #
      # @param json_string [String] A valid JSON string
      # @return [ActiveSupport::SafeBuffer] HTML-safe highlighted output
      # @api private
      def highlight_json_string(json_string)
        return "" if json_string.blank?

        # Phase 1: Tokenization
        # Convert JSON string into array of typed tokens for later rendering
        tokens = []
        i = 0
        chars = json_string.chars

        while i < chars.length
          char = chars[i]

          case char
          when '"'
            # String token: starts with quote, ends with unescaped quote
            # Handles escape sequences like \" and \\
            str_start = i
            i += 1
            while i < chars.length
              if chars[i] == '\\'
                i += 2
              elsif chars[i] == '"'
                i += 1
                break
              else
                i += 1
              end
            end
            tokens << { type: :string, value: chars[str_start...i].join }
          when /[0-9\-]/
            # Number token: starts with digit or minus, continues with digits/decimals/exponents
            num_start = i
            i += 1
            while i < chars.length && chars[i] =~ /[0-9.eE+\-]/
              i += 1
            end
            tokens << { type: :number, value: chars[num_start...i].join }
          when 't'
            # Boolean token: check for "true" keyword
            if chars[i, 4].join == 'true'
              tokens << { type: :boolean, value: 'true' }
              i += 4
            else
              tokens << { type: :text, value: char }
              i += 1
            end
          when 'f'
            # Boolean token: check for "false" keyword
            if chars[i, 5].join == 'false'
              tokens << { type: :boolean, value: 'false' }
              i += 5
            else
              tokens << { type: :text, value: char }
              i += 1
            end
          when 'n'
            # Null token: check for "null" keyword
            if chars[i, 4].join == 'null'
              tokens << { type: :null, value: 'null' }
              i += 4
            else
              tokens << { type: :text, value: char }
              i += 1
            end
          when ':', ',', '{', '}', '[', ']', ' ', "\n", "\t"
            # Punctuation token: structural characters and whitespace
            tokens << { type: :punct, value: char }
            i += 1
          else
            # Fallback for unexpected characters
            tokens << { type: :text, value: char }
            i += 1
          end
        end

        # Phase 2: Rendering
        # Convert tokens to HTML with color classes
        # Key detection: strings followed by colon are object keys (purple)
        # Value strings get different color (green)
        result = []
        tokens.each_with_index do |token, idx|
          case token[:type]
          when :string
            # Key detection algorithm:
            # Look ahead past any whitespace tokens to find next punctuation
            # If next non-whitespace punct is ':', this string is an object key
            is_key = false
            (idx + 1...tokens.length).each do |j|
              if tokens[j][:type] == :punct
                if tokens[j][:value] == ':'
                  is_key = true
                  break
                elsif tokens[j][:value] !~ /\s/
                  # Non-whitespace punct that isn't colon - not a key
                  break
                end
                # Skip whitespace and continue looking
              else
                break
              end
            end

            escaped_value = ERB::Util.html_escape(token[:value])
            if is_key
              result << %(<span class="text-purple-600">#{escaped_value}</span>)
            else
              result << %(<span class="text-green-600">#{escaped_value}</span>)
            end
          when :number
            result << %(<span class="text-blue-600">#{token[:value]}</span>)
          when :boolean
            result << %(<span class="text-amber-600">#{token[:value]}</span>)
          when :null
            result << %(<span class="text-gray-400">#{token[:value]}</span>)
          else
            result << ERB::Util.html_escape(token[:value])
          end
        end

        result.join.html_safe
      end
    end
  end
end
