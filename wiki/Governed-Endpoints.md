# Governed Endpoints

RubyLLM::Agents can run through any model provider supported by RubyLLM. In production Rails applications, some teams also route RubyLLM through an OpenAI-compatible gateway or control plane so model access, policy, audit trails, quotas, and cost controls are managed centrally.

The agent DSL and execution tracking remain in RubyLLM::Agents. The governed endpoint handles organization-wide controls before or after the model request.

## Example: Tuning Engines

Tuning Engines exposes an OpenAI-compatible endpoint that can be configured with RubyLLM's OpenAI provider settings:

```ruby
# config/initializers/ruby_llm_agents.rb
RubyLLM::Agents.configure do |config|
  config.openai_api_key = ENV["TUNING_ENGINES_API_KEY"]
  config.openai_api_base = "https://api.tuningengines.com/v1"
end
```

Then use a model alias that is enabled in your Tuning Engines catalog:

```ruby
class SupportRouter < ApplicationAgent
  model "support-triage-fast"
  temperature 0.0

  system "Route customer messages to the right support queue."
  user "{message}"

  route :billing, "Billing, charges, refunds, payments"
  route :technical, "Bugs, errors, crashes, technical issues"
  route :sales, "Pricing, plans, upgrades, discounts"
  default_route :general
end
```

If the alias is not present in RubyLLM's local model registry, configure the underlying RubyLLM call path with `assume_model_exists: true` where your application creates custom chats, or add the model alias to your registry.

## When this helps

Use this pattern when the Rails app needs agent-level features from RubyLLM::Agents and platform-level controls from a gateway:

- centralized model access by tenant, role, or environment
- policy and guardrail checks before model calls
- request approvals for high-risk tools or agent delegation
- cross-application traces and audit logs
- cost ceilings, quotas, fallbacks, and budget reporting

RubyLLM::Agents still records local execution metadata, tokens, latency, fallbacks, and costs. The gateway adds a second control plane for organization-wide policy and reporting.
