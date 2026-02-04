# frozen_string_literal: true

# A simple test agent for specs
class TestAgent < RubyLLM::Agents::Base
  model "gpt-4"
  temperature 0.5
  version "1.0"

  param :query, required: true
  param :limit, default: 10

  private

  def system_prompt
    "You are a helpful test assistant."
  end

  def user_prompt
    query
  end

  def metadata
    { query: query, limit: limit }
  end
end
