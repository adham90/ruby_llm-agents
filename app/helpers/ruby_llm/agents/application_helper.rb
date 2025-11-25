# frozen_string_literal: true

module RubyLLM
  module Agents
    module ApplicationHelper
      include Chartkick::Helper if defined?(Chartkick)

      def ruby_llm_agents
        RubyLLM::Agents::Engine.routes.url_helpers
      end

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

      def highlight_json(obj)
        return "" if obj.nil?

        json_string = JSON.pretty_generate(obj)
        highlight_json_string(json_string)
      end

      def highlight_json_string(json_string)
        return "" if json_string.blank?

        tokens = []
        i = 0
        chars = json_string.chars

        while i < chars.length
          char = chars[i]

          case char
          when '"'
            # Parse string
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
            # Parse number
            num_start = i
            i += 1
            while i < chars.length && chars[i] =~ /[0-9.eE+\-]/
              i += 1
            end
            tokens << { type: :number, value: chars[num_start...i].join }
          when 't'
            # true
            if chars[i, 4].join == 'true'
              tokens << { type: :boolean, value: 'true' }
              i += 4
            else
              tokens << { type: :text, value: char }
              i += 1
            end
          when 'f'
            # false
            if chars[i, 5].join == 'false'
              tokens << { type: :boolean, value: 'false' }
              i += 5
            else
              tokens << { type: :text, value: char }
              i += 1
            end
          when 'n'
            # null
            if chars[i, 4].join == 'null'
              tokens << { type: :null, value: 'null' }
              i += 4
            else
              tokens << { type: :text, value: char }
              i += 1
            end
          when ':', ',', '{', '}', '[', ']', ' ', "\n", "\t"
            tokens << { type: :punct, value: char }
            i += 1
          else
            tokens << { type: :text, value: char }
            i += 1
          end
        end

        # Build highlighted HTML - detect if string is a key (followed by :)
        result = []
        tokens.each_with_index do |token, idx|
          case token[:type]
          when :string
            # Check if this is a key (next non-whitespace token is :)
            is_key = false
            (idx + 1...tokens.length).each do |j|
              if tokens[j][:type] == :punct
                if tokens[j][:value] == ':'
                  is_key = true
                  break
                elsif tokens[j][:value] !~ /\s/
                  break
                end
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
