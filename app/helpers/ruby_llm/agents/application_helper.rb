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

      # Wiki base URL for documentation links
      WIKI_BASE_URL = "https://github.com/adham90/ruby_llm-agents/wiki/".freeze

      # Page to documentation mapping
      DOC_PAGES = {
        "dashboard/index" => "Dashboard",
        "agents/index" => "Agent-DSL",
        "agents/show" => "Agent-DSL",
        "executions/index" => "Execution-Tracking",
        "executions/show" => "Execution-Tracking",
        "tenants/index" => "Multi-Tenancy",
        "system_config/show" => "Configuration"
      }.freeze

      # Returns the documentation URL for the current page or a specific page key
      #
      # @param page_key [String, nil] Optional page key (e.g., "agents/index")
      # @return [String, nil] The documentation URL or nil if no mapping exists
      # @example Get documentation URL for current page
      #   documentation_url #=> "https://github.com/adham90/ruby_llm-agents/wiki/Agent-DSL"
      # @example Get documentation URL for specific page
      #   documentation_url("dashboard/index") #=> "https://github.com/adham90/ruby_llm-agents/wiki/Dashboard"
      def documentation_url(page_key = nil)
        key = page_key || "#{controller_name}/#{action_name}"
        doc_page = DOC_PAGES[key]
        return nil unless doc_page

        "#{WIKI_BASE_URL}#{doc_page}"
      end

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

      # Returns the URL for "All Tenants" (clears tenant filter)
      #
      # Removes tenant_id from query params to show unfiltered results.
      #
      # @return [String] URL without tenant filtering
      def all_tenants_url
        url_for(request.query_parameters.except("tenant_id"))
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
          '<span class="inline-flex items-center px-2 py-1 rounded text-xs font-medium bg-green-100 dark:bg-green-500/20 text-green-700 dark:text-green-300">Enabled</span>'.html_safe
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
          '<span class="inline-flex items-center px-2 py-1 rounded text-xs font-medium bg-green-100 dark:bg-green-500/20 text-green-700 dark:text-green-300">Configured</span>'.html_safe
        else
          '<span class="inline-flex items-center px-2 py-1 rounded text-xs font-medium bg-gray-100 dark:bg-gray-700 text-gray-500 dark:text-gray-400">Not configured</span>'.html_safe
        end
      end

      # Redacts sensitive data from an object for display
      #
      # Uses the configured redaction rules to mask sensitive fields
      # and patterns in the data.
      #
      # @param obj [Object] The object to redact (Hash, Array, or primitive)
      # @return [Object] The redacted object
      # @example
      #   redact_for_display({ password: "secret", name: "John" })
      #   #=> { password: "[REDACTED]", name: "John" }
      def redact_for_display(obj)
        Redactor.redact(obj)
      end

      # Syntax-highlights a redacted Ruby object as pretty-printed JSON
      #
      # Combines redaction and highlighting in one call.
      #
      # @param obj [Object] Any JSON-serializable Ruby object
      # @return [ActiveSupport::SafeBuffer] HTML-safe highlighted redacted JSON
      def highlight_json_redacted(obj)
        return "" if obj.nil?

        redacted = redact_for_display(obj)
        highlight_json(redacted)
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

      # Renders an SVG sparkline chart from trend data
      #
      # Creates a simple polyline SVG for inline trend visualization.
      # Used in version comparison to show historical performance.
      #
      # @param trend_data [Array<Hash>] Array of daily data points
      # @param metric_key [Symbol] The metric to chart (:count, :success_rate, :avg_cost, etc.)
      # @param color_class [String] Tailwind color class for the line
      # @return [ActiveSupport::SafeBuffer] SVG sparkline element
      def render_sparkline(trend_data, metric_key, color_class: "text-blue-500")
        return "".html_safe if trend_data.blank? || trend_data.length < 2

        values = trend_data.map { |d| d[metric_key].to_f || 0 }
        max_val = values.max || 1
        min_val = values.min || 0
        range = max_val - min_val
        range = 1 if range.zero?

        # Generate SVG polyline points
        points = values.each_with_index.map do |val, i|
          x = (i.to_f / (values.length - 1)) * 100
          y = 28 - ((val - min_val) / range * 24) + 2 # 2px padding top/bottom
          "#{x.round(2)},#{y.round(2)}"
        end.join(" ")

        content_tag(:svg, class: "w-full h-8", viewBox: "0 0 100 30", preserveAspectRatio: "none") do
          content_tag(:polyline, nil,
            points: points,
            fill: "none",
            stroke: "currentColor",
            "stroke-width": "2",
            "stroke-linecap": "round",
            "stroke-linejoin": "round",
            class: color_class
          )
        end
      end

      # Renders a comparison badge based on change percentage
      #
      # Determines if a metric change is significant and returns an appropriate
      # badge indicating improvement, regression, or stability.
      #
      # @param change_pct [Float] Percentage change between versions
      # @param metric_type [Symbol] Type of metric (:success_rate, :cost, :tokens, :duration, :count)
      # @return [ActiveSupport::SafeBuffer] HTML badge element
      def comparison_badge(change_pct, metric_type)
        threshold = case metric_type
                    when :success_rate then 5
                    when :cost, :tokens then 15
                    when :duration then 20
                    when :count then 25
                    else 10
                    end

        # Determine what "improvement" means for this metric
        # For cost/tokens/duration: negative change is good (lower is better)
        # For success_rate/count: positive change is good (higher is better)
        is_improvement = case metric_type
                         when :success_rate, :count then change_pct > threshold
                         when :cost, :tokens, :duration then change_pct < -threshold
                         else false
                         end

        is_regression = case metric_type
                        when :success_rate, :count then change_pct < -threshold
                        when :cost, :tokens, :duration then change_pct > threshold
                        else false
                        end

        if is_improvement
          content_tag(:span, class: "inline-flex items-center gap-1 px-2 py-0.5 text-xs font-medium text-green-700 dark:text-green-300 bg-green-100 dark:bg-green-500/20 rounded-full") do
            safe_join([
              content_tag(:svg, class: "w-3 h-3", fill: "none", stroke: "currentColor", viewBox: "0 0 24 24") do
                content_tag(:path, nil, "stroke-linecap": "round", "stroke-linejoin": "round", "stroke-width": "2", d: "M5 10l7-7m0 0l7 7m-7-7v18")
              end,
              "Improved"
            ])
          end
        elsif is_regression
          content_tag(:span, class: "inline-flex items-center gap-1 px-2 py-0.5 text-xs font-medium text-red-700 dark:text-red-300 bg-red-100 dark:bg-red-500/20 rounded-full") do
            safe_join([
              content_tag(:svg, class: "w-3 h-3", fill: "none", stroke: "currentColor", viewBox: "0 0 24 24") do
                content_tag(:path, nil, "stroke-linecap": "round", "stroke-linejoin": "round", "stroke-width": "2", d: "M19 14l-7 7m0 0l-7-7m7 7V3")
              end,
              "Regressed"
            ])
          end
        else
          content_tag(:span, class: "inline-flex items-center gap-1 px-2 py-0.5 text-xs font-medium text-gray-600 dark:text-gray-400 bg-gray-100 dark:bg-gray-700 rounded-full") do
            safe_join([
              content_tag(:svg, class: "w-3 h-3", fill: "none", stroke: "currentColor", viewBox: "0 0 24 24") do
                content_tag(:path, nil, "stroke-linecap": "round", "stroke-linejoin": "round", "stroke-width": "2", d: "M5 12h14")
              end,
              "Stable"
            ])
          end
        end
      end

      # Compact comparison indicator with arrow for now strip metrics
      #
      # Shows a colored arrow indicator showing percentage change vs previous period.
      # For errors/cost/duration: decrease is good (green). For success/tokens: increase is good.
      #
      # @param change_pct [Float, nil] Percentage change from previous period
      # @param metric_type [Symbol] Type of metric (:success, :errors, :cost, :duration, :tokens)
      # @return [ActiveSupport::SafeBuffer, String] HTML span with indicator or empty string
      def comparison_indicator(change_pct, metric_type: :count)
        return "".html_safe if change_pct.nil?

        # For errors/cost/duration, decrease is good. For success/tokens, increase is good.
        positive_is_good = metric_type.in?(%i[success tokens count])
        is_improvement = positive_is_good ? change_pct > 0 : change_pct < 0

        arrow = change_pct > 0 ? "\u2191" : "\u2193"
        color = is_improvement ? "text-green-600 dark:text-green-400" : "text-red-600 dark:text-red-400"

        content_tag(:span, "#{arrow}#{change_pct.abs}%", class: "text-xs font-medium #{color} ml-1")
      end

      # Returns human-readable display name for time range
      #
      # @param range [String] Range parameter (today, 7d, 30d)
      # @return [String] Human-readable range name
      # @example
      #   range_display_name("7d") #=> "7 Days"
      def range_display_name(range)
        case range
        when "today" then "Today"
        when "7d" then "7 Days"
        when "30d" then "30 Days"
        else "Today"
        end
      end

      # Formats milliseconds to human-readable duration
      #
      # @param ms [Numeric, nil] Duration in milliseconds
      # @return [String] Human-readable duration (e.g., "150ms", "2.5s", "1.2m")
      def format_duration_ms(ms)
        return "0ms" if ms.nil? || ms.zero?

        if ms < 1000
          "#{ms.round}ms"
        elsif ms < 60_000
          "#{(ms / 1000.0).round(1)}s"
        else
          "#{(ms / 60_000.0).round(1)}m"
        end
      end

      # Returns the appropriate row background class based on change significance
      #
      # @param change_pct [Float] Percentage change
      # @param metric_type [Symbol] Type of metric
      # @return [String] Tailwind CSS classes for row background
      def comparison_row_class(change_pct, metric_type)
        threshold = case metric_type
                    when :success_rate then 5
                    when :cost, :tokens then 15
                    when :duration then 20
                    when :count then 25
                    else 10
                    end

        is_improvement = case metric_type
                         when :success_rate, :count then change_pct > threshold
                         when :cost, :tokens, :duration then change_pct < -threshold
                         else false
                         end

        is_regression = case metric_type
                        when :success_rate, :count then change_pct < -threshold
                        when :cost, :tokens, :duration then change_pct > threshold
                        else false
                        end

        if is_improvement
          "bg-green-50 dark:bg-green-900/20 border border-green-200 dark:border-green-800"
        elsif is_regression
          "bg-red-50 dark:bg-red-900/20 border border-red-200 dark:border-red-800"
        else
          "bg-gray-50 dark:bg-gray-700/50 border border-gray-200 dark:border-gray-700"
        end
      end

      # Generates an overall comparison summary based on multiple metrics
      #
      # @param metrics [Array<Hash>] Array of metric comparison results
      # @return [ActiveSupport::SafeBuffer] HTML summary banner
      def comparison_summary_badge(improvements_count, regressions_count, v2_label)
        if improvements_count >= 3 && regressions_count == 0
          content_tag(:span, class: "inline-flex items-center gap-1 px-3 py-1 text-sm font-medium text-green-700 dark:text-green-300 bg-green-100 dark:bg-green-500/20 rounded-lg") do
            safe_join([
              content_tag(:svg, class: "w-4 h-4", fill: "none", stroke: "currentColor", viewBox: "0 0 24 24") do
                content_tag(:path, nil, "stroke-linecap": "round", "stroke-linejoin": "round", "stroke-width": "2", d: "M9 12l2 2 4-4m6 2a9 9 0 11-18 0 9 9 0 0118 0z")
              end,
              "v#{v2_label} shows overall improvement"
            ])
          end
        elsif regressions_count >= 3 && improvements_count == 0
          content_tag(:span, class: "inline-flex items-center gap-1 px-3 py-1 text-sm font-medium text-red-700 dark:text-red-300 bg-red-100 dark:bg-red-500/20 rounded-lg") do
            safe_join([
              content_tag(:svg, class: "w-4 h-4", fill: "none", stroke: "currentColor", viewBox: "0 0 24 24") do
                content_tag(:path, nil, "stroke-linecap": "round", "stroke-linejoin": "round", "stroke-width": "2", d: "M12 9v2m0 4h.01m-6.938 4h13.856c1.54 0 2.502-1.667 1.732-3L13.732 4c-.77-1.333-2.694-1.333-3.464 0L3.34 16c-.77 1.333.192 3 1.732 3z")
              end,
              "v#{v2_label} shows overall regression"
            ])
          end
        elsif improvements_count > 0 || regressions_count > 0
          content_tag(:span, class: "inline-flex items-center gap-1 px-3 py-1 text-sm font-medium text-amber-700 dark:text-amber-300 bg-amber-100 dark:bg-amber-500/20 rounded-lg") do
            safe_join([
              content_tag(:svg, class: "w-4 h-4", fill: "none", stroke: "currentColor", viewBox: "0 0 24 24") do
                content_tag(:path, nil, "stroke-linecap": "round", "stroke-linejoin": "round", "stroke-width": "2", d: "M8 7h12m0 0l-4-4m4 4l-4 4m0 6H4m0 0l4 4m-4-4l4-4")
              end,
              "v#{v2_label} shows mixed results"
            ])
          end
        else
          content_tag(:span, class: "inline-flex items-center gap-1 px-3 py-1 text-sm font-medium text-gray-600 dark:text-gray-400 bg-gray-100 dark:bg-gray-700 rounded-lg") do
            safe_join([
              content_tag(:svg, class: "w-4 h-4", fill: "none", stroke: "currentColor", viewBox: "0 0 24 24") do
                content_tag(:path, nil, "stroke-linecap": "round", "stroke-linejoin": "round", "stroke-width": "2", d: "M5 12h14")
              end,
              "No significant changes"
            ])
          end
        end
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
              result << %(<span class="text-purple-600 dark:text-purple-400">#{escaped_value}</span>)
            else
              result << %(<span class="text-green-600 dark:text-green-400">#{escaped_value}</span>)
            end
          when :number
            result << %(<span class="text-blue-600 dark:text-blue-400">#{token[:value]}</span>)
          when :boolean
            result << %(<span class="text-amber-600 dark:text-amber-400">#{token[:value]}</span>)
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
