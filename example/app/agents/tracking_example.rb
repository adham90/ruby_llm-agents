# frozen_string_literal: true

# Tracking Example - Demonstrates RubyLLM::Agents.track
#
# The `track` block collects results from multiple agent calls,
# aggregates cost/tokens/timing, and links executions in the
# dashboard via a shared request_id.
#
# @example Basic tracking
#   report = RubyLLM::Agents.track do
#     SummarizeAgent.call(text: "Long article...")
#     ClassifyAgent.call(text: "Customer complaint")
#   end
#
#   report.call_count   # => 2
#   report.total_cost   # => 0.0023
#   report.total_tokens # => 450
#   report.value        # => return value of the block
#
# @example With shared tenant (injected into every call)
#   report = RubyLLM::Agents.track(tenant: current_user) do
#     AgentA.call(query: "hello")     # gets tenant: current_user
#     AgentB.call(query: "world")     # gets tenant: current_user
#   end
#
# @example With request_id and tags
#   report = RubyLLM::Agents.track(
#     request_id: "voice_chat_#{SecureRandom.hex(4)}",
#     tags: { feature: "voice-chat", session_id: session.id }
#   ) do
#     transcript = TranscribeAgent.call(with: audio_path)
#     reply = ChatAgent.call(message: transcript.content)
#     audio = SpeakAgent.call(text: reply.content)
#     { transcript: transcript.content, reply: reply.content }
#   end
#
#   report.value[:reply]   # => "Here's my response..."
#   report.total_cost      # => cost of all 3 calls
#   report.request_id      # => "voice_chat_a1b2c3d4"
#
# @example Error handling (track never raises)
#   report = RubyLLM::Agents.track do
#     AgentA.call(query: "ok")
#     raise "something broke"
#   end
#
#   report.failed?     # => true
#   report.error       # => #<RuntimeError: something broke>
#   report.call_count  # => 1 (call before the raise)
#
# @example Nesting (inner results bubble to outer)
#   outer = RubyLLM::Agents.track do
#     AgentA.call(query: "outer")
#     inner = RubyLLM::Agents.track do
#       AgentB.call(query: "inner")
#     end
#     inner.total_cost  # cost of inner calls only
#   end
#   outer.call_count    # => 2 (both outer + inner)
#
# @example TrackReport API
#   report.successful?      # block completed without raising
#   report.failed?          # block raised
#   report.value            # block return value (nil if raised)
#   report.error            # exception (nil if successful)
#   report.results          # [Result, ...] in call order
#   report.call_count       # number of agent calls
#   report.request_id       # shared request_id
#   report.total_cost       # sum of all costs
#   report.total_tokens     # sum of all tokens
#   report.duration_ms      # wall clock time of block
#   report.models_used      # ["gpt-4o", "whisper-1"]
#   report.cost_breakdown   # per-call breakdown
#   report.all_successful?  # all results ok?
#   report.any_errors?      # any result errors?
#   report.to_h             # everything as a hash
#
# Dashboard: tracked requests appear on the "requests" page,
# grouped by request_id with aggregate cost/token/timing stats.

# Helper agents used in tracking examples
class SummarizeAgent < ApplicationAgent
  description "Summarizes text content"
  model "gpt-4o-mini"

  param :text, required: true

  user "Summarize this in one sentence: {text}"

  def metadata
    {showcase: "tracking", role: "summarizer"}
  end
end

class ClassifyAgent < ApplicationAgent
  description "Classifies text into categories"
  model "gpt-4o-mini"

  param :text, required: true

  user "Classify this text into one of: positive, negative, neutral. Text: {text}"

  def metadata
    {showcase: "tracking", role: "classifier"}
  end
end
