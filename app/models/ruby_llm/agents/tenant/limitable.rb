# frozen_string_literal: true

require "active_support/concern"

module RubyLLM
  module Agents
    class Tenant
      # Provides rate limiting, feature flags, and model restrictions for tenants.
      #
      # This concern adds functionality for:
      # - Rate limiting (requests per minute/hour)
      # - Feature flags (enable/disable features per tenant)
      # - Model restrictions (allowed/blocked model lists)
      #
      # @example Rate limiting
      #   tenant = Tenant.for("acme_corp")
      #   tenant.rate_limit_per_minute = 60
      #   tenant.rate_limit_per_hour = 1000
      #   tenant.can_make_request?  # => true (if under limits)
      #
      # @example Feature flags
      #   tenant.enable_feature!(:streaming)
      #   tenant.feature_enabled?(:streaming)  # => true
      #   tenant.disable_feature!(:streaming)
      #
      # @example Model restrictions
      #   tenant.allow_model!("gpt-4o")
      #   tenant.block_model!("gpt-4")
      #   tenant.model_allowed?("gpt-4o")  # => true
      #   tenant.model_allowed?("gpt-4")   # => false
      #
      # @api public
      module Limitable
        extend ActiveSupport::Concern

        # Check if a request can be made within rate limits
        #
        # This checks the current request rate against configured limits.
        # If no limits are configured, always returns true.
        #
        # @return [Boolean] true if request is within rate limits
        #
        # @example
        #   if tenant.can_make_request?
        #     # proceed with request
        #   else
        #     raise RateLimitExceeded
        #   end
        def can_make_request?
          return true unless rate_limited?

          within_minute_limit? && within_hour_limit?
        end

        # Check if rate limiting is enabled for this tenant
        #
        # @return [Boolean] true if any rate limit is configured
        def rate_limited?
          rate_limit_per_minute.present? || rate_limit_per_hour.present?
        end

        # Get the number of requests made in the current minute
        #
        # @return [Integer] request count for current minute
        def requests_this_minute
          executions_in_window(1.minute)
        end

        # Get the number of requests made in the current hour
        #
        # @return [Integer] request count for current hour
        def requests_this_hour
          executions_in_window(1.hour)
        end

        # Check if within per-minute rate limit
        #
        # @return [Boolean] true if under or at the limit
        def within_minute_limit?
          return true unless rate_limit_per_minute

          requests_this_minute < rate_limit_per_minute
        end

        # Check if within per-hour rate limit
        #
        # @return [Boolean] true if under or at the limit
        def within_hour_limit?
          return true unless rate_limit_per_hour

          requests_this_hour < rate_limit_per_hour
        end

        # Get remaining requests for the current minute
        #
        # @return [Integer, nil] remaining requests or nil if no limit
        def remaining_requests_this_minute
          return nil unless rate_limit_per_minute

          [rate_limit_per_minute - requests_this_minute, 0].max
        end

        # Get remaining requests for the current hour
        #
        # @return [Integer, nil] remaining requests or nil if no limit
        def remaining_requests_this_hour
          return nil unless rate_limit_per_hour

          [rate_limit_per_hour - requests_this_hour, 0].max
        end

        # ==================
        # Feature Flags
        # ==================

        # Check if a feature is enabled for this tenant
        #
        # @param feature [Symbol, String] The feature name
        # @return [Boolean] true if the feature is enabled
        #
        # @example
        #   tenant.feature_enabled?(:streaming)  # => true
        #   tenant.feature_enabled?("caching")   # => false
        def feature_enabled?(feature)
          feature_flags[feature.to_s] == true
        end

        # Enable a feature for this tenant
        #
        # @param feature [Symbol, String] The feature name
        # @return [Boolean] true if save succeeded
        #
        # @example
        #   tenant.enable_feature!(:streaming)
        def enable_feature!(feature)
          self.feature_flags = feature_flags.merge(feature.to_s => true)
          save!
        end

        # Disable a feature for this tenant
        #
        # @param feature [Symbol, String] The feature name
        # @return [Boolean] true if save succeeded
        #
        # @example
        #   tenant.disable_feature!(:streaming)
        def disable_feature!(feature)
          self.feature_flags = feature_flags.merge(feature.to_s => false)
          save!
        end

        # Set a feature flag to a specific value
        #
        # @param feature [Symbol, String] The feature name
        # @param enabled [Boolean] Whether the feature should be enabled
        # @return [Boolean] true if save succeeded
        def set_feature!(feature, enabled)
          self.feature_flags = feature_flags.merge(feature.to_s => enabled)
          save!
        end

        # Get all enabled features
        #
        # @return [Array<String>] List of enabled feature names
        def enabled_features
          feature_flags.select { |_, v| v == true }.keys
        end

        # Get all disabled features
        #
        # @return [Array<String>] List of disabled feature names
        def disabled_features
          feature_flags.select { |_, v| v == false }.keys
        end

        # ==================
        # Model Restrictions
        # ==================

        # Check if a model is allowed for this tenant
        #
        # Rules:
        # - If blocked_models contains the model, return false
        # - If allowed_models is empty, return true (all allowed)
        # - If allowed_models is not empty, model must be in the list
        #
        # @param model_id [String] The model identifier
        # @return [Boolean] true if the model is allowed
        #
        # @example
        #   tenant.model_allowed?("gpt-4o")      # => true
        #   tenant.model_allowed?("gpt-3.5")    # => false (if blocked)
        def model_allowed?(model_id)
          return false if model_blocked?(model_id)
          return true if allowed_models.empty?

          allowed_models.include?(model_id)
        end

        # Check if a model is explicitly blocked
        #
        # @param model_id [String] The model identifier
        # @return [Boolean] true if the model is blocked
        def model_blocked?(model_id)
          blocked_models.include?(model_id)
        end

        # Add a model to the allowed list
        #
        # @param model_id [String] The model identifier
        # @return [Boolean] true if save succeeded
        #
        # @example
        #   tenant.allow_model!("gpt-4o")
        def allow_model!(model_id)
          return true if allowed_models.include?(model_id)

          self.allowed_models = allowed_models + [model_id]
          # Also remove from blocked if present
          self.blocked_models = blocked_models - [model_id]
          save!
        end

        # Remove a model from the allowed list
        #
        # @param model_id [String] The model identifier
        # @return [Boolean] true if save succeeded
        def disallow_model!(model_id)
          self.allowed_models = allowed_models - [model_id]
          save!
        end

        # Add a model to the blocked list
        #
        # @param model_id [String] The model identifier
        # @return [Boolean] true if save succeeded
        #
        # @example
        #   tenant.block_model!("gpt-3.5-turbo")
        def block_model!(model_id)
          return true if blocked_models.include?(model_id)

          self.blocked_models = blocked_models + [model_id]
          # Also remove from allowed if present
          self.allowed_models = allowed_models - [model_id]
          save!
        end

        # Remove a model from the blocked list
        #
        # @param model_id [String] The model identifier
        # @return [Boolean] true if save succeeded
        def unblock_model!(model_id)
          self.blocked_models = blocked_models - [model_id]
          save!
        end

        # Get all models that are explicitly allowed
        #
        # @return [Array<String>] List of allowed model IDs
        def explicitly_allowed_models
          allowed_models.dup
        end

        # Get all models that are explicitly blocked
        #
        # @return [Array<String>] List of blocked model IDs
        def explicitly_blocked_models
          blocked_models.dup
        end

        # Check if model restrictions are configured
        #
        # @return [Boolean] true if any restrictions are set
        def has_model_restrictions?
          allowed_models.any? || blocked_models.any?
        end

        private

        # Count executions within a time window
        #
        # @param window [ActiveSupport::Duration] Time window
        # @return [Integer] Count of executions
        def executions_in_window(window)
          return 0 unless respond_to?(:executions)

          executions.where("created_at > ?", window.ago).count
        end
      end
    end
  end
end
