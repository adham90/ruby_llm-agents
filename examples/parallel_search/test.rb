# frozen_string_literal: true

require "bundler/setup"
require "minitest/autorun"
require "webmock/minitest"
require_relative "agent"

# HTTPX registers its WebMock adapter when the MCP client is required.
WebMock.enable!

class ParallelSearchExampleTest < Minitest::Test
  URL = "https://search.parallel.ai/mcp"
  SOURCE = "https://www.ruby-lang.org/en/news/"

  def setup
    @original_key = RubyLLM.config.openai_api_key
    @original_tracking = RubyLLM::Agents.configuration.track_executions
    RubyLLM.configure { |config| config.openai_api_key = "fixture-key" }
    RubyLLM::Agents.configure { |config| config.track_executions = false }
    @requests = []
    @model_requests = []
    @tool_error = false

    stub_request(:get, URL).to_return(status: 405)
    stub_request(:delete, URL).to_return(status: 200)
    stub_request(:post, URL).to_return do |request|
      assert_equal "ruby_llm-agents/parallel-search-example", request.headers["User-Agent"]
      refute request.headers.key?("Authorization")
      payload = JSON.parse(request.body)
      @requests << payload
      result = case payload["method"]
      when "initialize"
        {protocolVersion: "2025-03-26", capabilities: {tools: {}},
         serverInfo: {name: "parallel-fixture", version: "1.0"}}
      when "tools/list"
        {tools: [tool_schema("web_search", {objective: {type: "string"},
          search_queries: {type: "array", items: {type: "string"}}}),
          tool_schema("web_fetch", {urls: {type: "array", items: {type: "string"}}})]}
      when "tools/call"
        {content: [{type: "text", text: @tool_error ? "Rate limit reached" : "Ruby release notes: #{SOURCE}"}],
         isError: @tool_error}
      end
      if payload.key?("id")
        {status: 200, headers: {"Content-Type" => "application/json"},
         body: {jsonrpc: "2.0", id: payload["id"], result: result}.to_json}
      else
        {status: 202, body: ""}
      end
    end
    stub_request(:post, "https://api.openai.com/v1/chat/completions").to_return do |request|
      body = JSON.parse(request.body)
      @model_requests << body
      step = @model_requests.length
      message = if step <= 2 && !@tool_error
        name, arguments = if step == 1
          ["web_search", {objective: "Find Ruby release notes", search_queries: ["Ruby latest release notes"]}]
        else
          ["web_fetch", {urls: [SOURCE]}]
        end
        {role: "assistant", content: nil, tool_calls: [{id: "call_#{step}", type: "function",
                                                        function: {name: name, arguments: arguments.to_json}}]}
      elsif step == 1
        {role: "assistant", content: nil, tool_calls: [{id: "call_error", type: "function",
                                                        function: {name: "web_search", arguments: {objective: "Find Ruby releases",
                                                                                                   search_queries: ["Ruby latest releases"]}.to_json}}]}
      else
        {role: "assistant", content: @tool_error ? "Search failed: Rate limit reached" : "Ruby release notes: #{SOURCE}"}
      end
      {status: 200, headers: {"Content-Type" => "application/json"}, body: {
        id: "fixture_#{step}", object: "chat.completion", created: 1, model: "gpt-4.1-mini",
        choices: [{index: 0, message: message, finish_reason: message[:tool_calls] ? "tool_calls" : "stop"}],
        usage: {prompt_tokens: 10, completion_tokens: 10, total_tokens: 20}
      }.to_json}
    end
  end

  def teardown
    @client&.stop
    RubyLLM.configure { |config| config.openai_api_key = @original_key }
    RubyLLM::Agents.configure { |config| config.track_executions = @original_tracking }
  end

  def test_agent_dispatches_search_and_fetch_and_returns_sources
    defaults = RubyLLM::Agents.configuration.default_tools.dup
    @client = ParallelSearchExample.connect
    result = ParallelSearchExample::ResearchAgent.call(query: "Find Ruby release notes", mcp_client: @client)

    assert_includes result.content, SOURCE
    assert_equal defaults, RubyLLM::Agents.configuration.default_tools
    assert_equal %w[web_search web_fetch], @model_requests.first["tools"].map { |tool| tool.dig("function", "name") }
    calls = @requests.select { |request| request["method"] == "tools/call" }
    assert_equal %w[web_search web_fetch], calls.map { |request| request.dig("params", "name") }
    assert_equal [SOURCE], calls.last.dig("params", "arguments", "urls")
    tool_messages = @model_requests.last["messages"].select { |message| message["role"] == "tool" }
    assert_equal 2, tool_messages.length
    tool_messages.each { |message| assert_includes message["content"], SOURCE }
  end

  def test_tool_errors_reach_the_model
    @tool_error = true
    @client = ParallelSearchExample.connect
    result = ParallelSearchExample::ResearchAgent.call(query: "Find Ruby releases", mcp_client: @client)

    assert_includes result.content, "Rate limit reached"
    tool_message = @model_requests.last["messages"].find { |message| message["role"] == "tool" }
    assert_includes tool_message["content"], "Rate limit reached"
  end

  private

  def tool_schema(name, properties)
    {name: name, description: "#{name} fixture", inputSchema: {
      type: "object", properties: properties, required: properties.keys.map(&:to_s)
    }}
  end
end
