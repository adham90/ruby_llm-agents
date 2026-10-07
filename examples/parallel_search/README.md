# Parallel Search MCP example

Run a RubyLLM::Agents research agent with anonymous web search and page extraction
through [Parallel Search MCP](https://docs.parallel.ai/integrations/mcp/search-mcp).
The example uses the documented dynamic `tools` method and
[RubyLLM::MCP](https://github.com/patvice/ruby_llm-mcp)'s streamable HTTP transport.
It does not change the gem's dependencies or default tools.

From a checkout of this repository, with Ruby 3.2 or newer:

```bash
cd examples/parallel_search
bundle install
export OPENAI_API_KEY="your OpenAI key"
bundle exec ruby run.rb "What changed in the latest Ruby release? Cite sources."
```

`web_search` and `web_fetch` are discovered from `https://search.parallel.ai/mcp`
and registered with the agent. No Parallel API key or OAuth login is used.
Anonymous access is intended for exploration and light use and has rate limits;
model inference uses your OpenAI account and is billed separately. The connection
has a 30-second request timeout, sends a project User-Agent, and is closed after
the run, including when the agent raises an error.

This standalone runner disables database execution tracking in its own process.
To use the agent in a Rails app, add `gem "ruby_llm-mcp", "~> 1.0.1"` to your
app's Gemfile, copy `agent.rb`, and pass a connected client to `ResearchAgent.call`.
Keep the client alive until the call finishes and stop it in an `ensure` block,
as in `run.rb`. Your app's existing tracking configuration can remain enabled.

Run the offline test, which exercises the real agent loop against HTTP fixtures
for MCP discovery, search, fetch, and the model's responses:

```bash
bundle exec ruby test.rb
```
