# frozen_string_literal: true

module RubyLLM
  module Agents
    # Execution logic for content moderation
    #
    # Provides methods to check content against moderation policies
    # and handle flagged content according to configuration.
    #
    # @api private
    module ModerationExecution
      # Moderates input text if input moderation is enabled
      #
      # @param text [String] Text to moderate
      # @return [RubyLLM::Moderation, nil] Moderation result or nil if not enabled
      def moderate_input(text)
        return nil unless should_moderate?(:input)

        perform_moderation(text, :input)
      end

      # Moderates output text if output moderation is enabled
      #
      # @param text [String] Text to moderate
      # @return [RubyLLM::Moderation, nil] Moderation result or nil if not enabled
      def moderate_output(text)
        return nil unless should_moderate?(:output)

        perform_moderation(text, :output)
      end

      # Returns whether moderation was blocked
      #
      # @return [Boolean] true if content was blocked by moderation
      def moderation_blocked?
        @moderation_blocked == true
      end

      # Returns the phase where moderation blocked content
      #
      # @return [Symbol, nil] :input or :output, or nil if not blocked
      def moderation_blocked_phase
        @moderation_blocked_phase
      end

      # Returns all moderation results collected during execution
      #
      # @return [Hash{Symbol => RubyLLM::Moderation}] Results keyed by phase
      def moderation_results
        @moderation_results || {}
      end

      private

      # Checks if the given phase should be moderated
      #
      # @param phase [Symbol] :input or :output
      # @return [Boolean] true if this phase should be moderated
      def should_moderate?(phase)
        config = resolved_moderation_config
        return false unless config
        return false if @options[:moderation] == false

        config[:phases].include?(phase)
      end

      # Resolves the effective moderation configuration
      #
      # Merges class-level configuration with runtime overrides.
      #
      # @return [Hash, nil] Resolved configuration or nil if disabled
      def resolved_moderation_config
        runtime_config = @options[:moderation]
        return nil if runtime_config == false

        base_config = self.class.moderation_config
        return nil unless base_config

        if runtime_config.is_a?(Hash)
          base_config.merge(runtime_config)
        else
          base_config
        end
      end

      # Performs moderation on text
      #
      # @param text [String] Text to moderate
      # @param phase [Symbol] :input or :output
      # @return [RubyLLM::Moderation] The moderation result
      def perform_moderation(text, phase)
        config = resolved_moderation_config

        moderation_opts = {}
        moderation_opts[:model] = config[:model] if config[:model]

        result = RubyLLM.moderate(text, **moderation_opts)

        @moderation_results ||= {}
        @moderation_results[phase] = result

        record_moderation_execution(result, phase)

        if content_flagged?(result, config, phase)
          handle_flagged_content(result, config, phase)
        end

        result
      end

      # Determines if content should be flagged based on result and config
      #
      # @param result [RubyLLM::Moderation] The moderation result
      # @param config [Hash] Moderation configuration
      # @param phase [Symbol] :input or :output
      # @return [Boolean] true if content should be flagged
      def content_flagged?(result, config, phase)
        return false unless result.flagged?

        # Check phase-specific or global threshold
        threshold = config[:"#{phase}_threshold"] || config[:threshold]
        if threshold
          max_score = result.category_scores.values.max
          return false if max_score.nil? || max_score < threshold
        end

        # Check category filter
        if config[:categories]&.any?
          flagged_categories = result.flagged_categories.map { |c| normalize_category(c) }
          allowed_categories = config[:categories].map { |c| normalize_category(c) }
          return false if (flagged_categories & allowed_categories).empty?
        end

        true
      end

      # Normalizes category names for comparison
      #
      # @param category [String, Symbol] Category name
      # @return [Symbol] Normalized category symbol
      def normalize_category(category)
        category.to_s.tr("/", "_").tr("-", "_").downcase.to_sym
      end

      # Handles flagged content according to configuration
      #
      # @param result [RubyLLM::Moderation] The moderation result
      # @param config [Hash] Moderation configuration
      # @param phase [Symbol] :input or :output
      # @return [void]
      def handle_flagged_content(result, config, phase)
        # Custom handler takes priority
        if config[:custom_handler]
          action = send(config[:custom_handler], result, phase)
          return if action == :continue
        end

        on_flagged = config[:on_flagged] || :block

        case on_flagged
        when :raise
          raise ModerationError.new(result, phase)
        when :block
          @moderation_blocked = true
          @moderation_blocked_phase = phase
        when :warn
          log_moderation_warning(result, phase)
        when :log
          log_moderation_info(result, phase)
        end
      end

      # Logs a moderation warning
      #
      # @param result [RubyLLM::Moderation] The moderation result
      # @param phase [Symbol] :input or :output
      # @return [void]
      def log_moderation_warning(result, phase)
        return unless defined?(Rails) && Rails.respond_to?(:logger)

        Rails.logger.warn(
          "[RubyLLM::Agents] Content flagged in #{phase} moderation: " \
          "#{result.flagged_categories.join(', ')}"
        )
      end

      # Logs moderation info
      #
      # @param result [RubyLLM::Moderation] The moderation result
      # @param phase [Symbol] :input or :output
      # @return [void]
      def log_moderation_info(result, phase)
        return unless defined?(Rails) && Rails.respond_to?(:logger)

        Rails.logger.info(
          "[RubyLLM::Agents] Content flagged in #{phase} moderation: " \
          "#{result.flagged_categories.join(', ')}"
        )
      end

      # Records moderation execution for tracking
      #
      # @param result [RubyLLM::Moderation] The moderation result
      # @param phase [Symbol] :input or :output
      # @return [void]
      def record_moderation_execution(result, phase)
        return unless RubyLLM::Agents.configuration.track_moderation
        return unless execution_model_available?

        RubyLLM::Agents::Execution.create!(
          agent_type: self.class.name,
          execution_type: "moderation",
          model_id: result.model,
          input_tokens: 0,
          output_tokens: 0,
          total_cost: 0, # Moderation is typically free or very cheap
          duration_ms: 0,
          status: result.flagged? ? "flagged" : "passed",
          metadata: {
            phase: phase,
            flagged: result.flagged?,
            flagged_categories: result.flagged_categories,
            category_scores: result.category_scores
          },
          tenant_id: resolved_tenant_id
        )
      rescue StandardError => e
        Rails.logger.warn("[RubyLLM::Agents] Failed to record moderation: #{e.message}") if defined?(Rails)
      end

      # Returns the default moderation model
      #
      # @return [String] Default moderation model identifier
      def default_moderation_model
        RubyLLM::Agents.configuration.default_moderation_model || "omni-moderation-latest"
      end

      # Builds the text to moderate for input phase
      #
      # Combines user prompt content into a single string.
      #
      # @return [String] Text to moderate
      def build_moderation_input
        prompt = user_prompt
        if prompt.is_a?(Array)
          prompt.map { |p| p.is_a?(Hash) ? p[:content] : p.to_s }.join("\n")
        else
          prompt.to_s
        end
      end

      # Builds a result for blocked moderation
      #
      # @param phase [Symbol] :input or :output
      # @return [Result] Result with moderation blocked status
      def build_moderation_blocked_result(phase)
        Result.new(
          content: nil,
          status: :"#{phase}_moderation_blocked",
          moderation_flagged: true,
          moderation_result: @moderation_results[phase],
          moderation_phase: phase,
          agent_class: self.class.name,
          model_id: model,
          input_tokens: 0,
          output_tokens: 0,
          total_cost: 0,
          started_at: @execution_started_at,
          completed_at: Time.current
        )
      end
    end
  end
end
