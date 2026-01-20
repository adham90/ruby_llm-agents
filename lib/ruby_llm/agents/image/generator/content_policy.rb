# frozen_string_literal: true

module RubyLLM
  module Agents
    class ImageGenerator
      # Content policy enforcement for image generation prompts
      #
      # Validates prompts against configurable policy levels to prevent
      # generation of inappropriate content.
      #
      # @example Using content policy in a generator
      #   class SafeImageGenerator < RubyLLM::Agents::ImageGenerator
      #     content_policy :strict
      #   end
      #
      # @example Manual validation
      #   ContentPolicy.validate!("A beautiful sunset", :moderate)
      #   # => nil (passes)
      #
      #   ContentPolicy.validate!("Violent scene", :strict)
      #   # => raises ContentPolicyViolation
      #
      module ContentPolicy
        # Blocked patterns by policy level
        #
        # :strict   - Blocks violence, nudity, hate, weapons, drugs
        # :moderate - Blocks explicit content, gore, hate speech
        # :standard - No blocking (relies on model's built-in filters)
        # :none     - No validation at all
        #
        BLOCKED_PATTERNS = {
          strict: [
            /\b(violence|violent|gore|blood|death|kill|murder)\b/i,
            /\b(nude|naked|nsfw|explicit|sexual|porn)\b/i,
            /\b(hate|racist|discrimination|slur)\b/i,
            /\b(weapon|gun|knife|bomb|explosive)\b/i,
            /\b(drug|cocaine|heroin|meth)\b/i
          ],
          moderate: [
            /\b(nude|naked|nsfw|explicit|sexual|porn)\b/i,
            /\b(gore|graphic.?violence)\b/i,
            /\b(hate.?speech|slur)\b/i
          ],
          standard: [],
          none: []
        }.freeze

        class << self
          # Validate a prompt against a policy level
          #
          # @param prompt [String] The prompt to validate
          # @param level [Symbol] Policy level (:none, :standard, :moderate, :strict)
          # @raise [ContentPolicyViolation] If prompt violates the policy
          def validate!(prompt, level)
            return if level == :none || level.nil?

            patterns = BLOCKED_PATTERNS[level.to_sym] || BLOCKED_PATTERNS[:standard]

            patterns.each do |pattern|
              if prompt.match?(pattern)
                raise ContentPolicyViolation,
                      "Prompt contains content blocked by #{level} policy"
              end
            end
          end

          # Check if a prompt passes the policy (non-raising version)
          #
          # @param prompt [String] The prompt to check
          # @param level [Symbol] Policy level
          # @return [Boolean] true if prompt passes
          def valid?(prompt, level)
            validate!(prompt, level)
            true
          rescue ContentPolicyViolation
            false
          end

          # Get the matched pattern for a violation (for debugging)
          #
          # @param prompt [String] The prompt to check
          # @param level [Symbol] Policy level
          # @return [Regexp, nil] The matched pattern or nil
          def matched_pattern(prompt, level)
            patterns = BLOCKED_PATTERNS[level.to_sym] || []
            patterns.find { |pattern| prompt.match?(pattern) }
          end
        end
      end

      # Exception raised when a prompt violates content policy
      class ContentPolicyViolation < StandardError; end
    end
  end
end
