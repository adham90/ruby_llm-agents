# frozen_string_literal: true

require "bundler/setup"
require_relative "agent"

query = ARGV.join(" ")
abort 'Usage: bundle exec ruby run.rb "What changed in the latest Ruby release?"' if query.empty?

RubyLLM.configure do |config|
  config.openai_api_key = ENV.fetch("OPENAI_API_KEY")
end

# This standalone example has no Rails database for execution tracking.
RubyLLM::Agents.configure do |config|
  config.track_executions = false
end

client = nil
begin
  client = ParallelSearchExample.connect
  result = ParallelSearchExample::ResearchAgent.call(query: query, mcp_client: client)
  puts result.content
ensure
  client&.stop
end
