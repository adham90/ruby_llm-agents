# frozen_string_literal: true

# ApplicationAgent - Base class for all agents in this application
#
# All agents inherit from this class. Configure shared settings here
# that apply to all agents, or override them per-agent as needed.
#
# ============================================================================
# AGENT DSL REFERENCE
# ============================================================================
#
# MODEL CONFIGURATION:
# --------------------
#   model "gpt-4o"           # LLM model identifier
#   temperature 0.7          # Response randomness (0.0-2.0)
#   timeout 60               # Request timeout in seconds
#   version "1.0"            # Agent version (affects cache keys)
#   description "..."        # Human-readable agent description
#
# CACHING:
# --------
#   cache_for 1.hour         # Enable response caching with TTL
#   # Cached responses are keyed by: agent class + version + params + prompts
#   # Use temperature 0.0 for deterministic (cacheable) results
#
# STREAMING:
# ----------
#   streaming true           # Enable streaming mode
#   # When streaming:
#   #   MyAgent.call(query: "...") { |chunk| print chunk.content }
#   # Or explicitly:
#   #   MyAgent.stream(query: "...") { |chunk| print chunk.content }
#
# TOOLS:
# ------
#   tools [SearchTool, CalculatorTool]  # Array of RubyLLM::Tool classes
#   # Tools are automatically executed when the LLM requests them.
#   # The agent loops until the LLM provides a final answer.
#
# RELIABILITY BLOCK:
# ------------------
#   reliability do
#     retries max: 3, backoff: :exponential, base: 0.4, max_delay: 3.0
#     fallback_models "gpt-4o-mini", "claude-3-haiku-20240307"
#     total_timeout 45
#     circuit_breaker errors: 5, within: 60, cooldown: 300
#   end
#
# RELIABILITY (individual methods):
# ---------------------------------
#   retries max: 2, backoff: :exponential, base: 0.4, max_delay: 3.0
#   # backoff: :constant or :exponential
#   # on: [ErrorClass] - specific errors to retry on
#
#   fallback_models ["gpt-4o-mini", "claude-3-haiku"]
#   # Tried in order when primary model fails
#
#   total_timeout 30
#   # Overall timeout across all retries/fallbacks
#
#   circuit_breaker errors: 10, within: 60, cooldown: 300
#   # Opens after `errors` failures within `within` seconds
#   # Stays open for `cooldown` seconds before half-open
#
# PARAMETERS:
# -----------
#   param :query, required: true         # Required parameter
#   param :limit, default: 10            # Optional with default
#   param :count, default: 5, type: Integer  # Type validation
#   param :tags, type: Array             # Array type
#
# ============================================================================
# TEMPLATE METHODS (override in subclasses)
# ============================================================================
#
#   def user_prompt          # REQUIRED: User message to LLM
#     query
#   end
#
#   def system_prompt        # OPTIONAL: System instructions
#     "You are a helpful assistant..."
#   end
#
#   def schema               # OPTIONAL: Structured output schema (JSON Schema format)
#     {
#       type: "object",
#       properties: {
#         summary: { type: "string" },
#         score: { type: "number" },
#         items: { type: "array", items: { type: "string" } },
#         metadata: {
#           type: "object",
#           properties: { source: { type: "string" } }
#         }
#       },
#       required: %w[summary score]
#     }
#   end
#
#   def messages             # OPTIONAL: Conversation history
#     [{ role: :user, content: "Hi" }, { role: :assistant, content: "Hello!" }]
#   end
#
#   def process_response(response)  # OPTIONAL: Transform LLM response
#     response.content.upcase
#   end
#
#   def metadata   # OPTIONAL: Extra data for execution logs
#     { user_id: current_user_id }
#   end
#
# ============================================================================
# USAGE EXAMPLES
# ============================================================================
#
#   # Basic call
#   MyAgent.call(query: "hello")
#
#   # Debug mode (no API call)
#   MyAgent.call(query: "hello", dry_run: true)
#
#   # Bypass cache
#   MyAgent.call(query: "hello", skip_cache: true)
#
#   # With tenant for budget tracking
#   MyAgent.call(query: "hello", tenant: organization)
#
#   # Streaming
#   MyAgent.call(query: "hello") { |chunk| print chunk.content }
#   MyAgent.stream(query: "hello") { |chunk| print chunk.content }
#
#   # With attachments (images, files, URLs)
#   VisionAgent.call(query: "Describe this", with: "image.png")
#   VisionAgent.call(query: "Compare these", with: ["a.png", "b.png"])
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

  # cache_for 1.hour  # Enable caching for all agents

  # ============================================
  # Shared Reliability Settings
  # ============================================
  # Configure once here, all agents inherit these settings
  #
  # reliability do
  #   retries max: 2, backoff: :exponential, base: 0.4, max_delay: 3.0
  #   fallback_models "gpt-4o-mini", "claude-3-haiku-20240307"
  #   total_timeout 30
  #   circuit_breaker errors: 5, within: 60, cooldown: 300
  # end

  # ============================================
  # Shared Helper Methods
  # ============================================
  # Define methods here that can be used by all agents

  # Example: Common system prompt prefix
  # def system_prompt_prefix
  #   "You are an AI assistant for #{Rails.application.class.module_parent_name}."
  # end

  # Example: Common metadata
  # def metadata
  #   { app_version: Rails.application.config.version }
  # end
end
