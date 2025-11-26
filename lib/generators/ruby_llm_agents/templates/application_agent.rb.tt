# frozen_string_literal: true

# ApplicationAgent - Base class for all agents in this application
#
# All agents inherit from this class. Configure shared settings here
# that apply to all agents, or override them per-agent as needed.
#
# Example:
#   class MyAgent < ApplicationAgent
#     param :query, required: true
#
#     def user_prompt
#       query
#     end
#   end
#
# Usage:
#   MyAgent.call(query: "hello")
#   MyAgent.call(query: "hello", dry_run: true)    # Debug mode
#   MyAgent.call(query: "hello", skip_cache: true) # Bypass cache
#
class ApplicationAgent < RubyLLM::Agents::Base
  # ============================================
  # Shared Model Configuration
  # ============================================
  # These settings are inherited by all agents

  # model "gemini-2.0-flash"   # Default model for all agents
  # temperature 0.0            # Default temperature (0.0 = deterministic)
  # timeout 60                 # Default timeout in seconds

  # ============================================
  # Shared Caching
  # ============================================

  # cache 1.hour  # Enable caching for all agents (override per-agent if needed)

  # ============================================
  # Shared Reliability Settings
  # ============================================
  # Configure once here, all agents inherit these settings

  # Automatic retries for all agents
  # retries max: 2, backoff: :exponential, base: 0.4, max_delay: 3.0

  # Shared fallback models
  # fallback_models ["gpt-4o-mini", "claude-3-haiku"]

  # Total timeout across retries/fallbacks
  # total_timeout 30

  # Circuit breaker (per agent-model pair)
  # circuit_breaker errors: 5, within: 60, cooldown: 300

  # ============================================
  # Shared Helper Methods
  # ============================================
  # Define methods here that can be used by all agents

  # Example: Common system prompt prefix
  # def system_prompt_prefix
  #   "You are an AI assistant for #{Rails.application.class.module_parent_name}."
  # end

  # Example: Common metadata
  # def execution_metadata
  #   { app_version: Rails.application.config.version }
  # end
end
