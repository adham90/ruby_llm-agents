# frozen_string_literal: true

class Chat::TestAgent < ApplicationAgent
  description "A general-purpose test agent for development and experimentation"

  # ============================================
  # Model Configuration
  # ============================================

  model "gemini-2.0-flash"
  temperature 0.0
  version "1.0"
  # timeout 30  # Per-request timeout in seconds (default: 60)

  # ============================================
  # Caching
  # ============================================

  # cache 1.hour  # Enable response caching with TTL

  # ============================================
  # Reliability (Retries & Fallbacks)
  # ============================================

  # Automatic retries with exponential backoff
  # - max: Number of retry attempts
  # - backoff: :constant or :exponential
  # - base: Base delay in seconds
  # - max_delay: Maximum delay between retries
  # - on: Additional error classes to retry on
  # retries max: 2, backoff: :exponential, base: 0.4, max_delay: 3.0

  # Fallback models (tried in order when primary model fails)
  # fallback_models ["gpt-4o-mini", "claude-3-haiku"]

  # Total timeout across all retry/fallback attempts
  # total_timeout 30

  # Circuit breaker (prevents repeated calls to failing models)
  # - errors: Number of errors to trigger open state
  # - within: Rolling window in seconds
  # - cooldown: Time to wait before allowing requests again
  # circuit_breaker errors: 5, within: 60, cooldown: 300

  # ============================================
  # Parameters
  # ============================================

  param :query, required: true

  private

  # ============================================
  # Prompts (required)
  # ============================================

  def system_prompt
    <<~PROMPT
      You are a helpful assistant.
      # Define your system instructions here
    PROMPT
  end

  def user_prompt
    # Build the prompt from parameters
    query
  end

  # ============================================
  # Optional Overrides
  # ============================================

  # Structured output schema (returns parsed hash instead of raw text)
  # def schema
  #   @schema ||= RubyLLM::Schema.create do
  #     string :result, description: "The result"
  #     integer :confidence, description: "Confidence score 1-100"
  #     array :tags, description: "Relevant tags" do
  #       string
  #     end
  #   end
  # end

  # Custom response processing (default: symbolize hash keys)
  # def process_response(response)
  #   content = response.content
  #   # Transform or validate the response
  #   content
  # end

  # Custom metadata to include in execution logs
  # def execution_metadata
  #   { custom_field: "value", request_id: params[:request_id] }
  # end

  # Custom cache key data (default: all params except skip_cache, dry_run)
  # def cache_key_data
  #   { query: params[:query], locale: I18n.locale }
  # end
end
